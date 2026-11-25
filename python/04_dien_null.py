"""Section 3b(i): seven conditional imputation rules with frozen donors.

No original.csv values are read. No input CSV or SQL raw table is overwritten.
Outputs are intermediate imputation results, not the final after.csv.
"""
from pathlib import Path
from copy import deepcopy
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP, localcontext
import hashlib
import json
import csv
import ast
import os
import sys
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'VoMinhHuy_Heart Failure Prediction_before.csv'
OUT = ROOT / 'ket_qua' / '04_dien_null'
SPEC = json.loads((ROOT / 'ket_qua/03_quy_tac_null/quy_tac_de_xuat.json').read_text(encoding='utf-8'))
RULES = SPEC['rules']
Q6, Q10 = Decimal('0.000001'), Decimal('0.0000000001')


def sha(text):
    # SQL HASHBYTES over NVARCHAR uses UTF-16 little endian.
    return hashlib.sha256(text.encode('utf-16le')).hexdigest().upper()


def decimal_or_none(value, column):
    value = (value or '').strip()
    if column == 'sex':
        value = {'m': '1', 'male': '1', 'f': '0', 'female': '0'}.get(value.lower(), value)
    if not value:
        return None
    try:
        return Decimal(value).quantize(Q6, rounding=ROUND_HALF_UP)
    except Exception:
        return None


def age_group(value):
    if value is None:
        return None
    return 1 if value < 50 else 2 if value < 60 else 3 if value < 70 else 4


def prepare():
    with SOURCE.open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        columns = reader.fieldnames
        source = list(reader)
    rows, duplicates, empty_lines = [], [], []
    seen = {}
    for line, raw in enumerate(source, 2):
        if all(not value.strip() for value in raw.values()):
            empty_lines.append(line)
            continue
        row = {c: decimal_or_none(raw[c], c) for c in columns}
        canonical = '|'.join(c + '=' + ('~' if row[c] is None else f'{row[c]:.6f}') for c in columns)
        key = sha(canonical)
        if key in seen:
            duplicates.append({'source_csv_line': line, 'kept_source_csv_line': seen[key], 'record_key': key})
            continue
        seen[key] = line
        row.update(record_key=key, source_csv_line=line, _raw=raw.copy())
        for c, invalid in SPEC['invalid_values_confirmed_by_audit'].items():
            if row[c] is not None and row[c] in [Decimal(str(v)) for v in invalid]:
                row[c] = None
        row['age_group'] = age_group(row['age'])
        row['invalid_target'] = row['DEATH_EVENT'] not in (Decimal(0), Decimal(1))
        rows.append(row)
    return columns, rows, duplicates, empty_lines


def statistic(values, method):
    with localcontext() as context:
        context.prec = 38
        values = sorted(values)
        if method == 'mode':
            frequency = Counter(values)
            highest = max(frequency.values())
            answer = min(v for v, n in frequency.items() if n == highest)
        elif method == 'median':
            answer = (values[(len(values)-1)//2] + values[len(values)//2]) / 2
        elif method == 'mean':
            answer = sum(values, Decimal(0)) / len(values)
        else:
            raise ValueError(method)
        return answer.quantize(Q10, rounding=ROUND_HALF_UP)


def group_description(keys, recipient):
    if not keys:
        return 'GLOBAL'
    return ';'.join(k + '=' + (str(recipient[k]) if k == 'age_group' else f'{recipient[k]:.6f}') for k in keys)


def impute(prepared, masks=()):
    donors = deepcopy(prepared)
    mask_set = set(masks)
    for row in donors:
        for c in [r['column'] for r in RULES]:
            if (row['record_key'], c) in mask_set:
                row[c] = None
                if c == 'age':
                    row['age_group'] = None
    work = deepcopy(donors)
    logs = []
    for rule in RULES:
        column = rule['column']
        for row in sorted(work, key=lambda x: x['source_csv_line']):
            if row[column] is not None:
                continue
            selected, selected_keys, priority = [], [], None
            for level, keys in enumerate(rule['groups'], 1):
                if any(row[k] is None for k in keys):
                    continue
                candidates = [d for d in donors if d[column] is not None and all(d[k] is not None and d[k] == row[k] for k in keys)]
                if len(candidates) >= SPEC['minimum_valid_donors']:
                    selected, selected_keys, priority = candidates, keys, level
                    break
            raw = row['_raw'][column]
            reason = ('MASKED_FOR_VALIDATION' if (row['record_key'], column) in mask_set else
                      'MISSING' if not raw.strip() else
                      'WRONG_TYPE' if decimal_or_none(raw, column) is None else 'INVALID_VALUE')
            unrounded = statistic([d[column] for d in selected], rule['statistic']) if selected else None
            value = unrounded.quantize(Decimal(1).scaleb(-rule['decimals']), rounding=ROUND_HALF_UP).quantize(Q6) if unrounded is not None else None
            description = group_description(selected_keys, row) if selected else 'NO_ELIGIBLE_GROUP'
            signature = sha('|'.join(sorted(d['record_key'] for d in selected))) if selected else None
            logs.append({'record_key': row['record_key'], 'source_csv_line': row['source_csv_line'],
                         'column_name': column, 'old_value': raw if raw else None,
                         'missing_reason': reason, 'rule_id': rule['id'],
                         'statistic': rule['statistic'], 'priority': priority,
                         'group_description': description, 'donor_count': len(selected),
                         'unrounded_value': unrounded, 'decimals': rule['decimals'],
                         'imputed_value': value, 'donor_set_hash': signature,
                         'status': 'FILLED' if value is not None else 'UNRESOLVED'})
            row[column] = value
            if column == 'age':
                row['age_group'] = age_group(value)
    return work, logs


def validate(prepared):
    metrics, masks_export = [], []
    for rule in RULES:
        column = rule['column']
        observed = [r for r in prepared if r[column] is not None]
        # Seeded hash order is identical in SQL and Python; no engine-specific RNG.
        observed.sort(key=lambda r: (sha('42|' + rule['id'] + '|' + r['record_key']), r['record_key']))
        count = (len(observed) + 4) // 5  # ceil(20% * n)
        hidden = observed[:count]
        masks = {(r['record_key'], column) for r in hidden}
        work, _ = impute(prepared, masks)
        predicted = {r['record_key']: r[column] for r in work}
        baseline_values = [r[column] for r in prepared if r[column] is not None and (r['record_key'], column) not in masks]
        baseline = statistic(baseline_values, rule['statistic']).quantize(Decimal(1).scaleb(-rule['decimals']), rounding=ROUND_HALF_UP).quantize(Q6)
        valid = [r for r in hidden if predicted[r['record_key']] is not None]
        categorical = column == 'sex'
        if len(valid) != len(hidden):
            score = None
        elif categorical:
            score = (Decimal(sum(predicted[r['record_key']] == r[column] for r in hidden)) / len(hidden)).quantize(Q10, rounding=ROUND_HALF_UP)
        else:
            score = (sum(abs(predicted[r['record_key']] - r[column]) for r in hidden) / len(hidden)).quantize(Q10, rounding=ROUND_HALF_UP)
        if categorical:
            baseline_score = (Decimal(sum(baseline == r[column] for r in hidden)) / len(hidden)).quantize(Q10, rounding=ROUND_HALF_UP)
        else:
            baseline_score = (sum(abs(baseline - r[column]) for r in hidden) / len(hidden)).quantize(Q10, rounding=ROUND_HALF_UP)
        metrics.append({'rule_id': rule['id'], 'column_name': column, 'hidden_count': len(hidden),
                        'predicted_count': len(valid), 'metric': 'accuracy' if categorical else 'MAE',
                        'group_score': score, 'baseline_score': baseline_score,
                        'baseline_value': baseline,
                        'better_than_baseline': score is not None and (score > baseline_score if categorical else score < baseline_score)})
        for row in hidden:
            masks_export.append({'rule_id': rule['id'], 'column_name': column,
                                 'record_key': row['record_key'], 'source_csv_line': row['source_csv_line'],
                                 'truth': row[column], 'prediction': predicted[row['record_key']], 'baseline': baseline})
    return metrics, masks_export


def frame(rows, columns):
    return pd.DataFrame([{c: r[c] for c in columns} for r in rows])


def run():
    OUT.mkdir(parents=True, exist_ok=True)
    checksum = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    columns, prepared, duplicates, empty_lines = prepare()
    work, log = impute(prepared)
    metrics, masks = validate(prepared)
    numeric = columns + ['age_group']
    prepared_by_key = {r['record_key']: r for r in prepared}
    for row in work:
        for c in numeric:
            old = prepared_by_key[row['record_key']][c]
            if old is not None:
                assert row[c] == old, (row['record_key'], c)
    assert len(prepared) == len(work) == 299
    assert len(duplicates) == len(empty_lines) == 5
    assert len(log) == 126 and all(r['status'] == 'FILLED' for r in log)
    assert sum(r['invalid_target'] for r in work) == 1
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == checksum
    prep_summary = [{'source_rows': len(work) + len(duplicates) + len(empty_lines),
                     'empty_rows_removed': len(empty_lines), 'duplicate_rows_removed': len(duplicates),
                     'working_rows': len(work), 'cells_to_impute': len(log),
                     'filled_cells': sum(r['status'] == 'FILLED' for r in log),
                     'unresolved_cells': sum(r['status'] != 'FILLED' for r in log),
                     'invalid_target_rows': sum(r['invalid_target'] for r in work)}]
    summary = []
    for rule in RULES:
        cases = [r for r in log if r['rule_id'] == rule['id']]
        summary.append({'rule_id': rule['id'], 'column_name': rule['column'],
                        'missing_cells': len(cases), 'filled_cells': sum(r['status'] == 'FILLED' for r in cases),
                        'fallback_cells': sum(r['priority'] is not None and r['priority'] > 1 for r in cases),
                        'min_donors': min(r['donor_count'] for r in cases),
                        'max_donors': max(r['donor_count'] for r in cases)})
    outputs = {'chuan_bi_python.csv': pd.DataFrame(prep_summary),
               'tong_hop_quy_tac_python.csv': pd.DataFrame(summary),
               'nhat_ky_dien_python.csv': pd.DataFrame(log),
               'kiem_chung_che_20_phan_tram_python.csv': pd.DataFrame(metrics),
               'danh_sach_che_python.csv': pd.DataFrame(masks),
               'du_lieu_sau_dien_python.csv': frame(work, ['record_key', 'source_csv_line'] + columns + ['age_group', 'invalid_target']),
               'du_lieu_truoc_dien_python.csv': frame(prepared, ['record_key', 'source_csv_line'] + columns + ['age_group', 'invalid_target']),
               'ho_so_sao_chep_python.csv': pd.DataFrame(duplicates)}
    for name, data in outputs.items():
        data.to_csv(OUT / name, index=False, encoding='utf-8-sig')
    (OUT / 'thong_tin_lan_chay.json').write_text(json.dumps({'input_sha256': checksum,
        'source': SOURCE.name, 'rules': [r['id'] for r in RULES],
        'note': 'Kết quả trung gian của 3b(i), chưa phải after cuối; nhãn 2 được giữ và gắn cờ.',
        'validation': 'Che ceil(20% * n_observed) mỗi cột, theo SHA256 UTF16LE(42|rule_id|record_key).'}, ensure_ascii=False, indent=2), encoding='utf-8')
    return outputs


def make_notebook():
    chunks = [
        ('markdown', '# Mục 3b(i) — Điền giá trị thiếu\n**Võ Minh Huy — 2311110117**\n\nThực hiện N01–N07 đã mô tả trong Word. Giữ nguyên CSV nguồn; không dùng original để tra đáp án. Kết quả là dữ liệu trung gian, chưa phải after cuối. Đọc code ở file `04_dien_null.py` để xem toàn bộ thuật toán.'),
        ('code', '''from pathlib import Path
import importlib.util

thu_muc = Path.cwd()
if thu_muc.name == "python":
    thu_muc = thu_muc.parent
spec = importlib.util.spec_from_file_location(
    "dien_null", thu_muc / "python" / "04_dien_null.py"
)
dien_null = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dien_null)
ket_qua = dien_null.run()
ket_qua["chuan_bi_python.csv"]'''),
        ('markdown', '## 1. Kết quả điền theo từng quy tắc\nMẫu cho được cố định trước điền. Nhóm dưới 5 mẫu chuyển sang cấp dự phòng. Chỉ sửa các ô thiếu hoặc sai đã gắn cờ trên bản làm việc.'),
        ('code', 'ket_qua["tong_hop_quy_tac_python.csv"]'),
        ('markdown', '## 2. Minh họa nhật ký\nGiữ mã hồ sơ, dòng CSV, nguyên nhân thiếu, nhóm sử dụng, số mẫu cho và giá trị điền.'),
        ('code', '''nhat_ky = ket_qua["nhat_ky_dien_python.csv"]
cot_hien_thi = ["rule_id", "source_csv_line", "column_name", "old_value",
                "missing_reason", "priority", "donor_count", "imputed_value"]
nhat_ky.groupby("rule_id", sort=False).head(2)[cot_hien_thi]'''),
        ('markdown', '## 3. Trường hợp dùng nhóm dự phòng'),
        ('code', 'nhat_ky.loc[nhat_ky["priority"] > 1, ["rule_id", "source_csv_line", "group_description", "donor_count", "imputed_value"]]'),
        ('markdown', '## 4. Kiểm chứng bằng cách che 20% dữ liệu đã biết\nChe độc lập từng cột. Thứ tự che dùng hash với seed 42, giống SQL. Mẫu bị che được loại khỏi tập mẫu cho và khóa nhóm dẫn xuất. Accuracy: cao hơn tốt hơn; MAE: thấp hơn tốt hơn. So với phương án nền toàn cột, không mặc định phương pháp nhóm sẽ tốt hơn.'),
        ('code', 'ket_qua["kiem_chung_che_20_phan_tram_python.csv"]'),
        ('markdown', '## 5. Nhãn kết quả không được tự điền\nHồ sơ có DEATH_EVENT = 2 vẫn được giữ, gắn cờ; không đưa vào phân tích cần nhãn hợp lệ.'),
        ('code', '''du_lieu = ket_qua["du_lieu_sau_dien_python.csv"]
du_lieu.loc[du_lieu["invalid_target"], ["source_csv_line", "DEATH_EVENT", "invalid_target"]]'''),
        ('markdown', 'Code đầy đủ, dữ liệu trung gian, nhật ký và kết quả kiểm chứng được lưu trong thư mục `ket_qua/04_dien_null`. Các kết quả này phải được đối chiếu từng ô với SQL trước khi kết luận hoàn thành mục 3b(i).'),
    ]
    os.chdir(ROOT / 'python')
    namespace, cells, execution = {}, [], 0
    for kind, source in chunks:
        cell = {'cell_type': kind, 'id': hashlib.sha1(source.encode()).hexdigest()[:10],
                'metadata': {}, 'source': source.splitlines(keepends=True)}
        if kind == 'code':
            execution += 1
            tree = ast.parse(source); last = tree.body.pop()
            exec(compile(tree, '<notebook>', 'exec'), namespace)
            result = eval(compile(ast.Expression(last.value), '<notebook>', 'eval'), namespace)
            cell.update(execution_count=execution, outputs=[{'output_type': 'execute_result',
                'execution_count': execution, 'metadata': {},
                'data': {'text/plain': result.to_string(index=False), 'text/html': result.to_html(index=False)}}])
        cells.append(cell)
    notebook = {'cells': cells, 'metadata': {'kernelspec': {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'},
                'language_info': {'name': 'python'}}, 'nbformat': 4, 'nbformat_minor': 5}
    (ROOT / 'python/04_dien_null.ipynb').write_text(json.dumps(notebook, ensure_ascii=False, indent=2), encoding='utf-8')
    print(namespace['ket_qua']['tong_hop_quy_tac_python.csv'].to_string(index=False))
    print(namespace['ket_qua']['kiem_chung_che_20_phan_tram_python.csv'].to_string(index=False))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    make_notebook()

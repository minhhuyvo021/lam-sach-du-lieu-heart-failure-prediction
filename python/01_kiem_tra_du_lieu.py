"""Audit the supplied CSV files. Does not clean or overwrite either input.

Run from any directory: python python/01_kiem_tra_du_lieu.py
Only pandas is required beyond the Python standard library.
"""
from pathlib import Path
from decimal import Decimal, InvalidOperation
from collections import Counter
import hashlib
import json
import csv
import io
import contextlib
import platform
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / 'ket_qua' / '01_khao_sat'
ORIGINAL = ROOT / 'heart_failure_clinical_records_dataset_original.csv'
BEFORE = ROOT / 'VoMinhHuy_Heart Failure Prediction_before.csv'
if not BEFORE.exists():
    BEFORE = ROOT / 'VoMinhHuy_Heart Failure Prediction.csv'
SOURCE = 'https://archive.ics.uci.edu/dataset/519/heart+failure+clinical+records'
FIELDS = [
    ('age', 'Tuổi bệnh nhân', 'năm', 'Số thực', 'Giữ tuổi thập phân trong dữ liệu gốc'),
    ('anaemia', 'Chỉ báo thiếu máu', '0/1', 'Nhị phân', '0: Không; 1: Có'),
    ('creatinine_phosphokinase', 'Nồng độ enzyme CPK trong máu', 'mcg/L', 'Số nguyên', 'Theo mô tả UCI'),
    ('diabetes', 'Chỉ báo đái tháo đường', '0/1', 'Nhị phân', '0: Không; 1: Có'),
    ('ejection_fraction', 'Phân suất tống máu', '%', 'Số nguyên', 'Tỷ lệ máu được tống ra trong mỗi lần co bóp'),
    ('high_blood_pressure', 'Chỉ báo tăng huyết áp', '0/1', 'Nhị phân', '0: Không; 1: Có'),
    ('platelets', 'Số lượng tiểu cầu trong máu', 'kiloplatelets/mL (theo UCI)', 'Số thực', 'Giữ nguyên thang số trong CSV'),
    ('serum_creatinine', 'Nồng độ creatinine huyết thanh', 'mg/dL', 'Số thực', 'Không nhầm với creatinine_phosphokinase'),
    ('serum_sodium', 'Nồng độ natri huyết thanh', 'mEq/L', 'Số nguyên', 'Theo mô tả UCI'),
    ('sex', 'Giới tính được mã hóa trong bộ dữ liệu', '0/1', 'Nhị phân', '0: Nữ; 1: Nam; bản before có thêm các cách ghi bằng chữ'),
    ('smoking', 'Chỉ báo hút thuốc', '0/1', 'Nhị phân', '0: Không; 1: Có'),
    ('time', 'Thời gian theo dõi', 'ngày', 'Số nguyên', 'Khoảng thời gian theo dõi, không phải ngày tháng lịch'),
    ('DEATH_EVENT', 'Tử vong trong thời gian theo dõi', '0/1', 'Nhãn nhị phân', '0: Không; 1: Có; không phải nhãn chẩn đoán suy tim'),
]
BOOLEAN = ['anaemia', 'diabetes', 'high_blood_pressure', 'sex', 'smoking', 'DEATH_EVENT']


def load_inputs():
    original = pd.read_csv(ORIGINAL, dtype=str, keep_default_na=False)
    before = pd.read_csv(BEFORE, dtype=str, keep_default_na=False)
    if list(original.columns) != list(before.columns):
        raise ValueError('Hai file không có cùng thứ tự cột; phải kiểm tra trước khi so sánh theo dòng.')
    return original, before


def decimal_value(value):
    try:
        return Decimal(str(value).strip())
    except InvalidOperation:
        return None


def canonical(value, column):
    value = str(value).strip()
    if column == 'sex':
        value = {'m': '1', 'male': '1', 'f': '0', 'female': '0'}.get(value.lower(), value)
    n = decimal_value(value)
    return str(n.normalize()) if n is not None else value


def write_csv(name, records, columns=None):
    frame = records if isinstance(records, pd.DataFrame) else pd.DataFrame(records, columns=columns)
    frame.to_csv(RESULTS / name, index=False, encoding='utf-8-sig')


def run():
    RESULTS.mkdir(parents=True, exist_ok=True)
    input_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (ORIGINAL, BEFORE)}
    original, before = load_inputs()
    empty = before.apply(lambda c: c.str.strip()).eq('').all(axis=1)
    nonempty = before.loc[~empty]
    profiles = []
    dictionary = []
    counts = []
    for column, meaning, unit, dtype, note in FIELDS:
        ov = pd.to_numeric(original[column], errors='coerce')
        dictionary.append(dict(column=column, meaning=meaning, unit=unit, logical_type=dtype,
                               original_min=ov.min(), original_max=ov.max(), note=note, source=SOURCE))
        for stage, frame in [('original', original), ('before', before), ('before_nonempty', nonempty)]:
            values = frame[column]
            missing = values.str.strip().eq('')
            numeric = pd.to_numeric(values.mask(missing), errors='coerce')
            profiles.append(dict(stage=stage, column=column, records=len(frame),
                                 missing=int(missing.sum()), missing_percent=round(100 * missing.mean(), 3),
                                 unique_nonempty=int(values[~missing].nunique()),
                                 whitespace_cells=int(values.ne(values.str.strip()).sum()),
                                 nonnumeric_nonempty=int((~missing & numeric.isna()).sum()),
                                 numeric_min=numeric.min(), numeric_max=numeric.max()))
            if column in BOOLEAN:
                for value, count in values.value_counts(dropna=False).items():
                    counts.append(dict(stage=stage, column=column, value=value,
                                       display_value=repr(value), count=int(count)))

    # Positional alignment is checked on the five columns unchanged in all 299 source rows.
    stable = ['anaemia', 'diabetes', 'high_blood_pressure', 'smoking', 'time']
    aligned = before.iloc[:len(original)]
    if len(aligned) != len(original) or not original[stable].equals(aligned[stable]):
        raise ValueError('Không xác nhận được thứ tự hồ sơ; không so sánh theo vị trí dòng.')
    changes = []
    for index in original.index:
        for column in original.columns:
            old, new = original.at[index, column], before.at[index, column]
            if old == new:
                continue
            if not new.strip():
                kind = 'missing'
            elif decimal_value(old) is not None and decimal_value(old) == decimal_value(new):
                kind = 'numeric_format_only'
            elif column == 'sex':
                kind = 'category_representation' if canonical(old, column) == canonical(new, column) else 'category_value_changed'
            elif column == 'DEATH_EVENT':
                kind = 'invalid_target'
            elif decimal_value(new) is None:
                kind = 'wrong_type'
            else:
                kind = 'numeric_value_changed'
            changes.append(dict(csv_line=int(index + 2), record_index=int(index + 1), column=column,
                                original_value=old, before_value=new, change_type=kind))

    exact = []; normalized = []
    seen_exact = {}; seen_normal = {}
    for index, row in nonempty.iterrows():
        key = tuple(row)
        norm = tuple(canonical(row[c], c) for c in before.columns)
        for seen, key_value, target in [(seen_exact, key, exact), (seen_normal, norm, normalized)]:
            if key_value in seen:
                target.append(dict(csv_line=int(index + 2), first_csv_line=seen[key_value]))
            else:
                seen[key_value] = int(index + 2)

    # These 7 synthetic edits are verified by direct original-before comparison.
    important = [r for r in changes if r['change_type'] in ('numeric_value_changed', 'wrong_type', 'invalid_target', 'category_value_changed')]
    observed_summary = {
        'original_rows': len(original), 'before_rows': len(before), 'columns': len(before.columns),
        'empty_rows': int(empty.sum()), 'nonempty_rows': len(nonempty),
        'exact_duplicate_extra_rows': len(exact),
        'normalized_duplicate_extra_rows': len(normalized),
        'appended_patient_rows': int((~empty.iloc[len(original):]).sum()),
        'empty_csv_lines': (before.index[empty] + 2).tolist(),
        'changed_cells_299_including_formatting': len(changes),
        'numeric_format_only_cells': sum(r['change_type'] == 'numeric_format_only' for r in changes),
        'substantive_changed_cells_299': sum(r['change_type'] != 'numeric_format_only' for r in changes),
        'missing_cells_first299': sum(r['change_type'] == 'missing' for r in changes),
        'missing_cells_nonempty_before': int(nonempty.apply(lambda c: c.str.strip()).eq('').sum().sum()),
        'change_type_counts_first299': dict(Counter(r['change_type'] for r in changes)),
        'input_sha256': input_hashes,
        'runtime': {'python': platform.python_version(), 'pandas': pd.__version__},
        'alignment_method': 'Thứ tự 299 dòng đầu; đối chiếu khớp toàn bộ anaemia, diabetes, high_blood_pressure, smoking, time.',
        'normalized_duplicate_rule': 'Trim + chuẩn hóa số + sex {m,male:1; f,female:0}; đây là kiểm tra bổ sung, chưa xóa hồ sơ.',
    }
    write_csv('tu_dien_du_lieu.csv', dictionary)
    write_csv('thong_ke_chat_luong.csv', profiles)
    write_csv('tan_suat_nhi_phan.csv', counts)
    write_csv('doi_chieu_tung_o.csv', changes)
    write_csv('thay_doi_can_luu_y.csv', important)
    write_csv('trung_lap_nguyen_trang.csv', exact, ['csv_line', 'first_csv_line'])
    write_csv('trung_lap_sau_chuan_hoa.csv', normalized, ['csv_line', 'first_csv_line'])
    (RESULTS / 'tong_quan.json').write_text(json.dumps(observed_summary, ensure_ascii=False, indent=2), encoding='utf-8')
    for path in (ORIGINAL, BEFORE):
        if hashlib.sha256(path.read_bytes()).hexdigest() != input_hashes[path.name]:
            raise RuntimeError('File nguồn đã thay đổi trong lúc kiểm tra.')
    print(json.dumps(observed_summary, ensure_ascii=False, indent=2))
    return observed_summary


def make_notebook():
    """Create a standard notebook, with actual audit outputs captured from executed cells."""
    chunks = [
        ('markdown', '# Khảo sát dữ liệu bệnh nhân suy tim\nVõ Minh Huy - 2311110117. Kiểm tra original và before; chưa tạo after. Số dòng CSV tính cả hàng tiêu đề ở dòng 1.'),
        ('code', "from pathlib import Path\nimport importlib.util\nimport pandas as pd\nroot = Path.cwd()\nif not (root / 'DanYMonHoc.pdf').exists():\n    root = root.parent\nspec = importlib.util.spec_from_file_location('audit', root / 'python' / '01_kiem_tra_du_lieu.py')\naudit = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(audit)\nsummary = audit.run()"),
        ('markdown', '## Từ điển dữ liệu\nKhoảng min-max là giá trị quan sát trong original, không phải ngưỡng sinh lý. Nguồn mô tả: ' + SOURCE),
        ('code', "dictionary = pd.read_csv(audit.RESULTS / 'tu_dien_du_lieu.csv')\nprint(dictionary[['column','meaning','unit','logical_type']].to_string(index=False))"),
        ('markdown', '## Giá trị thiếu và kiểu dữ liệu\nTách dòng trống khỏi thiếu từng ô để không đếm trùng hai loại vấn đề.'),
        ('code', "quality = pd.read_csv(audit.RESULTS / 'thong_ke_chat_luong.csv')\nprint(quality.loc[quality.stage == 'before_nonempty', ['column','missing','unique_nonempty','whitespace_cells','nonnumeric_nonempty']].to_string(index=False))"),
        ('markdown', '## Thay đổi đáng lưu ý\nSo sánh với original chỉ phục vụ kiểm chứng. Đặc biệt, m và F có thể được chuẩn hóa về mã hợp lệ nhưng vẫn sai so với giới tính gốc.'),
        ('code', "changes = pd.read_csv(audit.RESULTS / 'thay_doi_can_luu_y.csv')\nprint(changes.to_string(index=False))"),
        ('markdown', '## Hồ sơ sao chép\nSo sánh nguyên trạng tìm được 3 dòng dư. Chuẩn hóa số và cách ghi sex tìm được 5 dòng dư; cần xử lý trước khi điền thiếu.'),
        ('code', "print(pd.read_csv(audit.RESULTS / 'trung_lap_sau_chuan_hoa.csv').to_string(index=False))"),
        ('markdown', '## Bước tiếp theo\nXác lập quy tắc dữ liệu thiếu, giá trị sai và nhãn không hợp lệ; chạy Python; đối chiếu SQL sau. Không sao chép dữ liệu gốc để thay cho thuật toán điền thiếu. Không kết luận y khoa từ các thống kê mô tả.'),
    ]
    namespace = {'__name__': '__notebook__'}
    cells = []; counter = 0
    for kind, source in chunks:
        cell = dict(cell_type=kind, id=hashlib.sha1(source.encode()).hexdigest()[:10], metadata={}, source=source.splitlines(keepends=True))
        if kind == 'code':
            counter += 1
            captured = io.StringIO()
            with contextlib.redirect_stdout(captured):
                exec(source, namespace)
            cell.update(execution_count=counter, outputs=[dict(output_type='stream', name='stdout', text=captured.getvalue().splitlines(keepends=True))])
        cells.append(cell)
    nb = dict(cells=cells, metadata={'kernelspec': {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'}, 'language_info': {'name': 'python', 'version': platform.python_version()}}, nbformat=4, nbformat_minor=5)
    (ROOT / 'python' / '01_kiem_tra_du_lieu.ipynb').write_text(json.dumps(nb, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    import os, sys
    sys.stdout.reconfigure(encoding='utf-8')
    os.chdir(ROOT)
    make_notebook()
    print((RESULTS / 'tong_quan.json').read_text(encoding='utf-8'))

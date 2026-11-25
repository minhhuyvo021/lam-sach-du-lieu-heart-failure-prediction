"""Merge reviewed Python outputs and compare with the independent SQL export."""
from pathlib import Path
from decimal import Decimal
from collections import Counter
import csv
import json
import hashlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'ket_qua/18_after'
ORIGINAL = ['age', 'anaemia', 'creatinine_phosphokinase', 'diabetes',
            'ejection_fraction', 'high_blood_pressure', 'platelets',
            'serum_creatinine', 'serum_sodium', 'sex', 'smoking', 'time', 'DEATH_EVENT']
FIELDS = ['MaHoSo'] + ORIGINAL + ['MaNhomTuoi', 'MaBoolean',
          'platelets_mean_5_nhom', 'platelets_dieu_chinh_10pct']


def read(path):
    with path.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def indexed(relative):
    rows = read(ROOT / relative)
    result = {int(r['MaHoSo']): r for r in rows}
    if len(result) != len(rows):
        raise ValueError(f'Duplicate MaHoSo: {relative}')
    return result


def export_python():
    base = indexed('ket_qua/15_khong_nhat_quan/02_death_event/ban_lam_viec_nhan_python.csv')
    mean = indexed('ket_qua/13_lam_min/02_mean_5_nhom/ban_lam_viec_sau_mean_python.csv')
    adjust = indexed('ket_qua/13_lam_min/03_dieu_chinh_10_phan_tram/ban_lam_viec_sau_10_phan_tram_python.csv')
    codes = indexed('ket_qua/17_chuyen_doi/02_danh_muc_thu_tu/ma_danh_muc_thu_tu_python.csv')
    boolean = indexed('ket_qua/17_chuyen_doi/01_gop_5_boolean/bang_ma_python.csv')
    for table in (mean, adjust, codes, boolean):
        if table.keys() != base.keys():
            raise ValueError('Intermediate record keys differ')
    rows = []
    integer_fields = ['anaemia', 'diabetes', 'high_blood_pressure', 'sex',
                      'smoking', 'DEATH_EVENT', 'MaNhomTuoi']
    for key, source in base.items():
        row = {'MaHoSo': key, **{c: source[c] for c in ORIGINAL}}
        for c in integer_fields:
            row[c] = '' if codes[key][c] == '' else str(int(Decimal(codes[key][c])))
        row['MaBoolean'] = str(int(Decimal(boolean[key]['MaBoolean'])))
        row['platelets_mean_5_nhom'] = mean[key]['platelets']
        row['platelets_dieu_chinh_10pct'] = adjust[key]['platelets']
        rows.append(row)
    if len(rows) != 299:
        raise ValueError('Expected 299 records')
    for row in rows:
        if any(str(row[c]).strip() == '' for c in FIELDS if c != 'DEATH_EVENT'):
            raise ValueError('Missing predictor or key')
        if row['DEATH_EVENT'] not in ('', '0', '1'):
            raise ValueError('Invalid target')
    path = ROOT / 'VoMinhHuy_Heart Failure Prediction_after_Python.csv'
    with path.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    return path


def compare_exports():
    paths = [ROOT / f'VoMinhHuy_Heart Failure Prediction_after_{name}.csv'
             for name in ('SQL', 'Python')]
    data = [read(p) for p in paths]
    for rows in data:
        if not rows or list(rows[0]) != FIELDS:
            raise ValueError('After schema differs')
    # Compare the complete row multiset: independent SQL/Python internal IDs differ.
    columns = FIELDS[1:]
    def canonical(rows):
        return Counter(tuple(None if r[c] == '' else Decimal(r[c]) for c in columns)
                       for r in rows)
    left, right = map(canonical, data)
    mismatch = sum((left - right).values()) + sum((right - left).values())
    report = {'status': 'PASS' if mismatch == 0 else 'FAIL',
              'rows_sql': len(data[0]), 'rows_python': len(data[1]),
              'columns_including_internal_id': len(FIELDS),
              'compared_columns': len(columns), 'compared_values': len(data[0]) * len(columns),
              'mismatching_rows_both_directions': mismatch,
              'comparison': 'Complete numeric row multiset, including NULL and multiplicity; excludes local MaHoSo',
              'unknown_targets': [sum(r['DEATH_EVENT'] == '' for r in rows) for rows in data],
              'sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'doi_chieu_sql_python.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    if mismatch or len(data[0]) != 299 or len(data[1]) != 299:
        raise ValueError(report)
    return report


if __name__ == '__main__':
    print(export_python().name)
    print(json.dumps(compare_exports(), ensure_ascii=False, indent=2))

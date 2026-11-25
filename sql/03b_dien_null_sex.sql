-- N01: chỉ điền NULL của sex. Chạy sau file chuẩn bị trong CÙNG tab.
-- Mode theo cấp: 4 biến -> anaemia,diabetes -> diabetes -> toàn cột.
-- Nhóm phải đủ 5 mẫu hợp lệ; đồng mode chọn 0 trước 1.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#SexWork') IS NULL
    THROW 51000, N'Chạy 03a_chuan_bi_dien_sex.sql trong tab này trước.', 1;
DROP TABLE IF EXISTS #SexLog;

SELECT r.MaHoSo, r.anaemia, r.diabetes, r.smoking, r.high_blood_pressure,
    chosen.CapNhom, chosen.SoMauCho, chosen.GiaTriDien
INTO #SexLog
FROM #SexWork r
OUTER APPLY (
    SELECT TOP (1) f.CapNhom, f.sex AS GiaTriDien,
        SUM(f.TanSuat) OVER(PARTITION BY f.CapNhom) AS SoMauCho
    FROM (
        SELECT level.CapNhom, d.sex, COUNT(*) AS TanSuat
        FROM #SexDonors d
        CROSS JOIN (VALUES (1),(2),(3),(4)) level(CapNhom)
        WHERE (level.CapNhom=1 AND d.anaemia=r.anaemia AND d.diabetes=r.diabetes
                   AND d.smoking=r.smoking AND d.high_blood_pressure=r.high_blood_pressure)
           OR (level.CapNhom=2 AND d.anaemia=r.anaemia AND d.diabetes=r.diabetes)
           OR (level.CapNhom=3 AND d.diabetes=r.diabetes)
           OR level.CapNhom=4
        GROUP BY level.CapNhom, d.sex
    ) f
    ORDER BY CASE WHEN SUM(f.TanSuat) OVER(PARTITION BY f.CapNhom)>=5
                  THEN 0 ELSE 1 END, f.CapNhom, f.TanSuat DESC, f.sex
) chosen
WHERE r.sex IS NULL;

UPDATE w SET sex=l.GiaTriDien
FROM #SexWork w JOIN #SexLog l ON w.MaHoSo=l.MaHoSo
WHERE w.sex IS NULL AND l.SoMauCho>=5;

-- Chụp bảng 1: tổng kết trước/sau.
SELECT (SELECT COUNT(*) FROM #SexWork) AS SoHoSo,
    COUNT(*) AS SoSexThieuTruocDien,
    SUM(CASE WHEN SoMauCho>=5 THEN 1 ELSE 0 END) AS SoODaDien,
    (SELECT COUNT(*) FROM #SexWork WHERE sex IS NULL) AS SoSexThieuSauDien
FROM #SexLog;

-- Chụp bảng 2: nhóm, số mẫu cho và giá trị điền của 20 hồ sơ.
SELECT * FROM #SexLog ORDER BY MaHoSo;

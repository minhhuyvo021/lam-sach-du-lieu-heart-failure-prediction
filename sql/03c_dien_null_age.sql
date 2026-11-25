-- N02: điền age bằng median, sau khi hoàn thành N01 sex.
-- Chạy trong CÙNG tab SQL đã chạy 03a và 03b.
-- Cấp 1: sex,diabetes -> cấp 2: sex -> cấp 3: toàn cột.
-- Nhóm cần ít nhất 5 mẫu; chỉ tuổi vừa điền được làm tròn 1 chữ số.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#SexWork') IS NULL
 OR OBJECT_ID('tempdb..#SexDonors') IS NULL
 OR OBJECT_ID('tempdb..#SexLog') IS NULL
    THROW 51000, N'Chạy bước chuẩn bị và điền sex trong tab này trước.', 1;
IF EXISTS(SELECT 1 FROM #SexWork WHERE sex IS NULL)
    THROW 51001, N'Chưa hoàn thành điền sex; kiểm tra N01 trước.', 1;
DROP TABLE IF EXISTS #AgeWork, #AgeDonors, #AgeTargets, #AgeLog;

-- Tạo bản nối tiếp riêng, để có thể chạy lại N02 mà không tính ô vừa điền.
SELECT * INTO #AgeWork FROM #SexWork;
SELECT MaHoSo, age AS TuoiTruoc, sex, diabetes,
    CASE WHEN age IN(-12,250) THEN N'Tuổi bị làm nhiễu'
         ELSE N'NULL hoặc sai kiểu' END AS LyDo
INTO #AgeTargets FROM #AgeWork WHERE age IS NULL OR age IN(-12,250);

-- Lấy sex QUAN SÁT từ #SexDonors, không lấy sex đã ước lượng làm khóa mẫu cho.
-- Mẫu thiếu sex vẫn có thể cho tuổi ở cấp toàn cột.
SELECT w.age, original.sex, w.diabetes
INTO #AgeDonors FROM #AgeWork w
LEFT JOIN #SexDonors original ON original.MaHoSo=w.MaHoSo
WHERE w.age IS NOT NULL AND w.age NOT IN(-12,250);
UPDATE #AgeWork SET age=NULL WHERE age IN(-12,250);

-- Xếp tuổi để lấy median chính xác của nhóm đủ 5 mẫu.
;WITH Ranked AS (
    SELECT r.MaHoSo, level.CapNhom, d.age,
        ROW_NUMBER() OVER(PARTITION BY r.MaHoSo,level.CapNhom ORDER BY d.age) AS rn,
        COUNT(*) OVER(PARTITION BY r.MaHoSo,level.CapNhom) AS SoMauCho
    FROM #AgeTargets r CROSS JOIN (VALUES(1),(2),(3)) level(CapNhom)
    JOIN #AgeDonors d ON
        (level.CapNhom=1 AND d.sex=r.sex AND d.diabetes=r.diabetes)
        OR (level.CapNhom=2 AND d.sex=r.sex) OR level.CapNhom=3
), Medians AS (
    SELECT MaHoSo,CapNhom,MAX(SoMauCho) AS SoMauCho,AVG(age) AS MedianNhom
    FROM Ranked WHERE SoMauCho>=5 AND rn IN((SoMauCho+1)/2,(SoMauCho+2)/2)
    GROUP BY MaHoSo,CapNhom
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY MaHoSo ORDER BY CapNhom) AS uu_tien
    FROM Medians
)
SELECT r.*,p.CapNhom,p.SoMauCho,p.MedianNhom,
    CAST(ROUND(p.MedianNhom,1) AS decimal(18,1)) AS TuoiDien
INTO #AgeLog FROM #AgeTargets r
LEFT JOIN Preferred p ON p.MaHoSo=r.MaHoSo AND p.uu_tien=1;

UPDATE w SET age=l.TuoiDien
FROM #AgeWork w JOIN #AgeLog l ON l.MaHoSo=w.MaHoSo
WHERE w.age IS NULL AND l.TuoiDien IS NOT NULL;

-- CHỤP BẢNG 1: 21 ô NULL/sai kiểu + 2 tuổi nhiễu = 23 ô cần xử lý.
SELECT (SELECT COUNT(*) FROM #AgeWork) AS SoHoSo,
    SUM(CASE WHEN TuoiTruoc IS NULL THEN 1 ELSE 0 END) AS SoNullHoacSaiKieu,
    SUM(CASE WHEN TuoiTruoc IN(-12,250) THEN 1 ELSE 0 END) AS SoTuoiNhieu,
    COUNT(*) AS SoOCanDien,COUNT(TuoiDien) AS SoODaDien,
    (SELECT COUNT(*) FROM #AgeWork WHERE age IS NULL) AS SoAgeThieuSauDien
FROM #AgeLog;

-- CHỤP BẢNG 2: các khóa nhóm, median trước làm tròn và tuổi được điền.
SELECT * FROM #AgeLog ORDER BY MaHoSo;
-- Bản làm việc nối tiếp là #AgeWork; chưa phải bảng after cuối.

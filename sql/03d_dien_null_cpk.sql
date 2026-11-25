-- N03: điền creatinine_phosphokinase (CPK) bằng median, sau N02 age.
-- Chạy trong CÙNG tab đã chạy 03a, 03b và 03c.
-- Nhóm tuổi: A1 <50; A2 [50,60); A3 [60,70); A4 >=70.
-- Cấp 1: nhóm tuổi,anaemia -> cấp 2: nhóm tuổi -> cấp 3: toàn cột.
-- Nhóm cần ít nhất 5 mẫu; chỉ CPK vừa điền được làm tròn số nguyên.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#AgeWork') IS NULL
 OR OBJECT_ID('tempdb..#SexWork') IS NULL
    THROW 51000, N'Chạy các bước chuẩn bị, sex và age trong tab này trước.', 1;
IF EXISTS(SELECT 1 FROM #AgeWork WHERE age IS NULL OR age IN(-12,250))
    THROW 51001, N'Chưa hoàn thành N02 age; kiểm tra trước khi chia nhóm tuổi.', 1;
DROP TABLE IF EXISTS #CPKWork, #CPKDonors, #CPKTargets, #CPKLog;

-- Hồ sơ NHẬN được chia nhóm bằng tuổi sau N02, kể cả tuổi vừa điền.
SELECT w.*, CASE WHEN age<50 THEN 'A1' WHEN age<60 THEN 'A2'
    WHEN age<70 THEN 'A3' ELSE 'A4' END AS age_group
INTO #CPKWork FROM #AgeWork w;
SELECT MaHoSo,creatinine_phosphokinase AS CPKTruoc,age,age_group,anaemia,
    CASE WHEN creatinine_phosphokinase=99999 THEN N'CPK bị làm nhiễu'
         ELSE N'NULL hoặc sai kiểu' END AS LyDo
INTO #CPKTargets FROM #CPKWork
WHERE creatinine_phosphokinase IS NULL OR creatinine_phosphokinase=99999;

-- Mẫu CHO dùng CPK và nhóm tuổi quan sát trước mọi bước điền.
-- Tuổi thiếu/nhiễu không tạo khóa nhóm, nhưng CPK hợp lệ vẫn dùng ở cấp toàn cột.
SELECT creatinine_phosphokinase AS CPK,anaemia,
    CASE WHEN age IS NULL OR age IN(-12,250) THEN NULL
         WHEN age<50 THEN 'A1' WHEN age<60 THEN 'A2'
         WHEN age<70 THEN 'A3' ELSE 'A4' END AS age_group
INTO #CPKDonors FROM #SexWork
WHERE creatinine_phosphokinase IS NOT NULL AND creatinine_phosphokinase<>99999;
UPDATE #CPKWork SET creatinine_phosphokinase=NULL WHERE creatinine_phosphokinase=99999;

;WITH Ranked AS (
    SELECT r.MaHoSo,level.CapNhom,d.CPK,
        ROW_NUMBER() OVER(PARTITION BY r.MaHoSo,level.CapNhom ORDER BY d.CPK) AS rn,
        COUNT(*) OVER(PARTITION BY r.MaHoSo,level.CapNhom) AS SoMauCho
    FROM #CPKTargets r CROSS JOIN (VALUES(1),(2),(3)) level(CapNhom)
    JOIN #CPKDonors d ON
        (level.CapNhom=1 AND d.age_group=r.age_group AND d.anaemia=r.anaemia)
        OR (level.CapNhom=2 AND d.age_group=r.age_group) OR level.CapNhom=3
), Medians AS (
    SELECT MaHoSo,CapNhom,MAX(SoMauCho) AS SoMauCho,AVG(CPK) AS MedianNhom
    FROM Ranked WHERE SoMauCho>=5 AND rn IN((SoMauCho+1)/2,(SoMauCho+2)/2)
    GROUP BY MaHoSo,CapNhom
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY MaHoSo ORDER BY CapNhom) AS uu_tien
    FROM Medians
)
SELECT r.*,p.CapNhom,p.SoMauCho,p.MedianNhom,
    CAST(ROUND(p.MedianNhom,0) AS decimal(18,0)) AS CPKDien
INTO #CPKLog FROM #CPKTargets r
LEFT JOIN Preferred p ON p.MaHoSo=r.MaHoSo AND p.uu_tien=1;

UPDATE w SET creatinine_phosphokinase=l.CPKDien
FROM #CPKWork w JOIN #CPKLog l ON l.MaHoSo=w.MaHoSo
WHERE w.creatinine_phosphokinase IS NULL AND l.CPKDien IS NOT NULL;

-- CHỤP BẢNG 1: tổng kết 20 ô NULL/sai kiểu + 1 CPK nhiễu = 21 ô cần điền.
SELECT (SELECT COUNT(*) FROM #CPKWork) AS SoHoSo,
    SUM(CASE WHEN CPKTruoc IS NULL THEN 1 ELSE 0 END) AS SoNullHoacSaiKieu,
    SUM(CASE WHEN CPKTruoc=99999 THEN 1 ELSE 0 END) AS SoCPKNhieu,
    COUNT(*) AS SoOCanDien,COUNT(CPKDien) AS SoODaDien,
    (SELECT COUNT(*) FROM #CPKWork WHERE creatinine_phosphokinase IS NULL) AS SoCPKThieuSauDien
FROM #CPKLog;

-- CHỤP BẢNG 2: nhóm tuổi, anaemia, số mẫu cho, median và CPK được điền.
SELECT * FROM #CPKLog ORDER BY MaHoSo;
-- Bản làm việc nối tiếp là #CPKWork; chưa phải bảng after cuối.

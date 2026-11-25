-- N06: điền serum_sodium bằng mode, nối tiếp N05 serum_creatinine.
-- Chạy trong CÙNG tab đã chạy các bước 03a đến 03f.
-- Cấp 1: nhóm tuổi,diabetes -> cấp 2: nhóm tuổi -> cấp 3: toàn cột.
-- Nhóm cần ít nhất 5 mẫu; đồng mode chọn giá trị số nhỏ nhất.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#CreatinineWork') IS NULL
 OR OBJECT_ID('tempdb..#SexWork') IS NULL
    THROW 51000, N'Chạy các bước trước đến N05 serum_creatinine trong tab này trước.', 1;
IF EXISTS(SELECT 1 FROM #CreatinineWork WHERE serum_creatinine IS NULL OR age IS NULL)
    THROW 51001, N'Kiểm tra các bước trước: vẫn còn serum_creatinine hoặc age thiếu.', 1;
DROP TABLE IF EXISTS #SodiumWork,#SodiumDonors,#SodiumTargets,#SodiumLog;

SELECT * INTO #SodiumWork FROM #CreatinineWork;
SELECT MaHoSo,serum_sodium AS SodiumTruoc,age,age_group,diabetes,
    CASE WHEN serum_sodium=999 THEN N'Natri bị làm nhiễu'
         ELSE N'NULL hoặc sai kiểu' END AS LyDo
INTO #SodiumTargets FROM #SodiumWork
WHERE serum_sodium IS NULL OR serum_sodium=999;

-- Mẫu cho cố định: natri và nhóm tuổi quan sát trước mọi bước điền.
-- Tuổi thiếu/nhiễu không tạo khóa nhóm, nhưng natri hợp lệ vẫn dùng ở cấp toàn cột.
SELECT serum_sodium AS Sodium,diabetes,
    CASE WHEN age IS NULL OR age IN(-12,250) THEN NULL
         WHEN age<50 THEN 'A1' WHEN age<60 THEN 'A2'
         WHEN age<70 THEN 'A3' ELSE 'A4' END AS age_group
INTO #SodiumDonors FROM #SexWork
WHERE serum_sodium IS NOT NULL AND serum_sodium<>999;
UPDATE #SodiumWork SET serum_sodium=NULL WHERE serum_sodium=999;

;WITH Frequencies AS (
    SELECT r.MaHoSo,level.CapNhom,d.Sodium,COUNT(*) AS TanSuat
    FROM #SodiumTargets r CROSS JOIN (VALUES(1),(2),(3)) level(CapNhom)
    JOIN #SodiumDonors d ON
        (level.CapNhom=1 AND d.age_group=r.age_group AND d.diabetes=r.diabetes)
        OR (level.CapNhom=2 AND d.age_group=r.age_group) OR level.CapNhom=3
    GROUP BY r.MaHoSo,level.CapNhom,d.Sodium
), GroupSizes AS (
    SELECT *,SUM(TanSuat) OVER(PARTITION BY MaHoSo,CapNhom) AS SoMauCho
    FROM Frequencies
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY MaHoSo
        ORDER BY CapNhom,TanSuat DESC,Sodium) AS uu_tien
    FROM GroupSizes WHERE SoMauCho>=5
)
SELECT r.*,p.CapNhom,p.SoMauCho,p.TanSuat AS TanSuatMode,p.Sodium AS ModeNhom,
    CAST(ROUND(p.Sodium,0) AS decimal(18,0)) AS SodiumDien
INTO #SodiumLog FROM #SodiumTargets r
LEFT JOIN Preferred p ON p.MaHoSo=r.MaHoSo AND p.uu_tien=1;

UPDATE w SET serum_sodium=l.SodiumDien
FROM #SodiumWork w JOIN #SodiumLog l ON l.MaHoSo=w.MaHoSo
WHERE w.serum_sodium IS NULL AND l.SodiumDien IS NOT NULL;

-- CHỤP BẢNG 1: 20 ô thiếu + 1 natri nhiễu 999 = 21 ô cần xử lý.
SELECT (SELECT COUNT(*) FROM #SodiumWork) AS SoHoSo,
    SUM(CASE WHEN SodiumTruoc IS NULL THEN 1 ELSE 0 END) AS SoNullHoacSaiKieu,
    SUM(CASE WHEN SodiumTruoc=999 THEN 1 ELSE 0 END) AS SoSodiumNhieu,
    COUNT(*) AS SoOCanDien,COUNT(SodiumDien) AS SoODaDien,
    (SELECT COUNT(*) FROM #SodiumWork WHERE serum_sodium IS NULL) AS SoSodiumThieuSauDien
FROM #SodiumLog;

-- CHỤP BẢNG 2: nhóm, số mẫu cho, tần suất mode và giá trị điền.
SELECT * FROM #SodiumLog ORDER BY MaHoSo;
-- Bản làm việc nối tiếp là #SodiumWork; chưa phải bảng after cuối.

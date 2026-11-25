-- N05: điền serum_creatinine bằng median, nối tiếp N04 platelets.
-- Chạy trong CÙNG tab đã chạy các bước từ 03a đến 03e.
-- Cấp 1: nhóm tuổi,high_blood_pressure -> cấp 2: nhóm tuổi -> cấp 3: toàn cột.
-- Nhóm cần ít nhất 5 mẫu; chỉ giá trị mới điền được làm tròn 2 chữ số.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#PlateletsWork') IS NULL
 OR OBJECT_ID('tempdb..#SexWork') IS NULL
    THROW 51000, N'Chạy các bước trước đến N04 platelets trong tab này trước.', 1;
IF EXISTS(SELECT 1 FROM #PlateletsWork WHERE platelets IS NULL OR age IS NULL)
    THROW 51001, N'Kiểm tra các bước trước: vẫn còn platelets hoặc age thiếu.', 1;
DROP TABLE IF EXISTS #CreatinineWork,#CreatinineDonors,#CreatinineTargets,#CreatinineLog;

-- Hồ sơ nhận dùng nhóm tuổi sau N02, đã có trong bảng làm việc.
SELECT * INTO #CreatinineWork FROM #PlateletsWork;
SELECT MaHoSo,serum_creatinine AS CreatinineTruoc,age,age_group,high_blood_pressure
INTO #CreatinineTargets FROM #CreatinineWork WHERE serum_creatinine IS NULL;

-- Mẫu cho cố định: creatinine và khóa nhóm quan sát trước mọi bước điền.
-- Tuổi thiếu/nhiễu không tạo khóa nhóm, nhưng creatinine hợp lệ vẫn dùng ở cấp toàn cột.
SELECT serum_creatinine AS Creatinine,high_blood_pressure,
    CASE WHEN age IS NULL OR age IN(-12,250) THEN NULL
         WHEN age<50 THEN 'A1' WHEN age<60 THEN 'A2'
         WHEN age<70 THEN 'A3' ELSE 'A4' END AS age_group
INTO #CreatinineDonors FROM #SexWork WHERE serum_creatinine IS NOT NULL;

;WITH Ranked AS (
    SELECT r.MaHoSo,level.CapNhom,d.Creatinine,
        ROW_NUMBER() OVER(PARTITION BY r.MaHoSo,level.CapNhom ORDER BY d.Creatinine) AS rn,
        COUNT(*) OVER(PARTITION BY r.MaHoSo,level.CapNhom) AS SoMauCho
    FROM #CreatinineTargets r CROSS JOIN (VALUES(1),(2),(3)) level(CapNhom)
    JOIN #CreatinineDonors d ON
        (level.CapNhom=1 AND d.age_group=r.age_group
             AND d.high_blood_pressure=r.high_blood_pressure)
        OR (level.CapNhom=2 AND d.age_group=r.age_group) OR level.CapNhom=3
), Medians AS (
    SELECT MaHoSo,CapNhom,MAX(SoMauCho) AS SoMauCho,AVG(Creatinine) AS MedianNhom
    FROM Ranked WHERE SoMauCho>=5 AND rn IN((SoMauCho+1)/2,(SoMauCho+2)/2)
    GROUP BY MaHoSo,CapNhom
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY MaHoSo ORDER BY CapNhom) AS uu_tien
    FROM Medians
)
SELECT r.*,p.CapNhom,p.SoMauCho,p.MedianNhom,
    CAST(ROUND(p.MedianNhom,2) AS decimal(18,2)) AS CreatinineDien
INTO #CreatinineLog FROM #CreatinineTargets r
LEFT JOIN Preferred p ON p.MaHoSo=r.MaHoSo AND p.uu_tien=1;

UPDATE w SET serum_creatinine=l.CreatinineDien
FROM #CreatinineWork w JOIN #CreatinineLog l ON l.MaHoSo=w.MaHoSo
WHERE w.serum_creatinine IS NULL AND l.CreatinineDien IS NOT NULL;

-- CHỤP BẢNG 1: tổng kết số ô trước/sau điền.
SELECT (SELECT COUNT(*) FROM #CreatinineWork) AS SoHoSo,
    COUNT(*) AS SoCreatinineThieuTruocDien,COUNT(CreatinineDien) AS SoODaDien,
    (SELECT COUNT(*) FROM #CreatinineWork WHERE serum_creatinine IS NULL) AS SoCreatinineThieuSauDien
FROM #CreatinineLog;

-- CHỤP BẢNG 2: khóa nhóm, cấp nhóm, số mẫu cho, median và giá trị điền.
SELECT * FROM #CreatinineLog ORDER BY MaHoSo;
-- Bản làm việc nối tiếp là #CreatinineWork; chưa phải bảng after cuối.

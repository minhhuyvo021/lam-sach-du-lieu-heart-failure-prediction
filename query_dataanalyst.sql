IF DB_ID(N'HeartFailure_DoAn') IS NULL
    CREATE DATABASE HeartFailure_DoAn;
GO

--Check số dòng của data
USE HeartFailure_DoAn;
GO

SELECT
    COUNT(*) AS TongSoDong,
    SUM(CASE
        WHEN age = N'Invalid_Age' THEN 1 ELSE 0
    END) AS SoOInvalidAge
FROM dbo.heart_before_raw;

--KHẢO SÁT DỮ LIỆU THÔ BAN ĐẦU
USE HeartFailure_DoAn;
GO
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.heart_before_raw', N'U') IS NULL
    THROW 51000, N'Không tìm thấy dbo.heart_before_raw trong HeartFailure_DoAn.', 1;

-- KẾT QUẢ 1: Số dòng và số cột.
SELECT
    COUNT(*) AS TongSoDong,
    (SELECT COUNT(*) FROM sys.columns
     WHERE object_id = OBJECT_ID(N'dbo.heart_before_raw')) AS TongSoCot
FROM dbo.heart_before_raw;

-- KẾT QUẢ 2: Kiểu lưu trữ hiện tại, chưa phải kiểu logic sau làm sạch.
SELECT
    ORDINAL_POSITION AS STT,
    COLUMN_NAME AS TenCot,
    DATA_TYPE AS KieuLuuTru,
    CHARACTER_MAXIMUM_LENGTH AS DoDaiToiDa,
    IS_NULLABLE AS ChoPhepNull
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'dbo' AND TABLE_NAME = N'heart_before_raw'
ORDER BY ORDINAL_POSITION;

-- KẾT QUẢ 3: Số ô thiếu từng cột trên toàn bộ 309 dòng.
-- Coi SQL NULL hoặc chuỗi rỗng sau trim là thiếu.
-- Bao gồm 5 dòng trống hoàn toàn; chưa xóa dòng nào.
SELECT
    v.STT,
    v.TenCot,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(v.GiaTri)), N'') IS NULL
             THEN 1 ELSE 0 END) AS SoGiaTriThieu,
    CAST(100.0 * SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(v.GiaTri)), N'') IS NULL
        THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(6,2)) AS TyLeThieuPhanTram
FROM dbo.heart_before_raw AS r
CROSS APPLY (VALUES
    (1, N'age', r.age),
    (2, N'anaemia', r.anaemia),
    (3, N'creatinine_phosphokinase', r.creatinine_phosphokinase),
    (4, N'diabetes', r.diabetes),
    (5, N'ejection_fraction', r.ejection_fraction),
    (6, N'high_blood_pressure', r.high_blood_pressure),
    (7, N'platelets', r.platelets),
    (8, N'serum_creatinine', r.serum_creatinine),
    (9, N'serum_sodium', r.serum_sodium),
    (10, N'sex', r.sex),
    (11, N'smoking', r.smoking),
    (12, N'time', r.time),
    (13, N'DEATH_EVENT', r.DEATH_EVENT)
) AS v(STT, TenCot, GiaTri)
GROUP BY v.STT, v.TenCot
ORDER BY v.STT;

-- KẾT QUẢ 4: Tần suất nguyên trạng của 6 biến nhị phân, kể cả nhãn kết quả.
-- Dấu [] giúp nhìn thấy khoảng trắng; SoKyTu tính cả khoảng trắng cuối.
-- Nhóm theo bytes để SQL không gộp các cách viết khác nhau do collation
-- hoặc bỏ qua khoảng trắng cuối. Không dùng TRIM để nhóm giá trị.
;WITH GiaTriTho AS (
    SELECT v.STT, v.TenCot, v.GiaTri,
           CONVERT(VARBINARY(200), v.GiaTri) AS MaNguyenTrang
    FROM dbo.heart_before_raw AS r
    CROSS APPLY (VALUES
        (1, N'anaemia', r.anaemia),
        (2, N'diabetes', r.diabetes),
        (3, N'high_blood_pressure', r.high_blood_pressure),
        (4, N'sex', r.sex),
        (5, N'smoking', r.smoking),
        (6, N'DEATH_EVENT', r.DEATH_EVENT)
    ) AS v(STT, TenCot, GiaTri)
)
SELECT
    STT, TenCot,
    CASE WHEN MaNguyenTrang IS NULL THEN N'<NULL>'
         ELSE N'[' + MAX(GiaTri) + N']' END AS GiaTriHienThi,
    CASE WHEN MaNguyenTrang IS NULL THEN NULL
         ELSE DATALENGTH(MAX(GiaTri)) / 2 END AS SoKyTu,
    COUNT(*) AS SoLuong
FROM GiaTriTho
GROUP BY STT, TenCot, MaNguyenTrang
ORDER BY STT, MaNguyenTrang;


--Điền Null ở Sex
USE HeartFailure_DoAn;
GO
SET NOCOUNT ON;
DROP TABLE IF EXISTS #SexWork, #SexDonors, #SexLog;

-- Loại dòng rỗng, chuẩn hóa cách ghi và nhận diện trùng trên 13 cột.
-- Chỉ dùng bảng tạm; các lỗi ở cột khác sẽ xử lý ở phần tương ứng.
;WITH Normalized AS (
    SELECT
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(age)), '')) AS age,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(anaemia)), '')) AS anaemia,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(creatinine_phosphokinase)), '')) AS creatinine_phosphokinase,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(diabetes)), '')) AS diabetes,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(ejection_fraction)), '')) AS ejection_fraction,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(high_blood_pressure)), '')) AS high_blood_pressure,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(platelets)), '')) AS platelets,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(serum_creatinine)), '')) AS serum_creatinine,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(serum_sodium)), '')) AS serum_sodium,
        TRY_CONVERT(decimal(18,6), CASE LOWER(LTRIM(RTRIM(sex)))
            WHEN 'm' THEN '1' WHEN 'male' THEN '1'
            WHEN 'f' THEN '0' WHEN 'female' THEN '0'
            ELSE NULLIF(LTRIM(RTRIM(sex)), '') END) AS sex,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(smoking)), '')) AS smoking,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(time)), '')) AS time,
        TRY_CONVERT(decimal(18,6), NULLIF(LTRIM(RTRIM(DEATH_EVENT)), '')) AS DEATH_EVENT
    FROM dbo.heart_before_raw
    WHERE NULLIF(LTRIM(RTRIM(CONCAT(age,anaemia,creatinine_phosphokinase,
        diabetes,ejection_fraction,high_blood_pressure,platelets,
        serum_creatinine,serum_sodium,sex,smoking,time,DEATH_EVENT))), '') IS NOT NULL
), UniqueRecords AS (
    SELECT DISTINCT * FROM Normalized
)
SELECT IDENTITY(int,1,1) AS MaHoSo, * INTO #SexWork FROM UniqueRecords;

-- Cố định mẫu cho: chỉ sex 0/1 đã quan sát, không lấy ô vừa điền.
SELECT * INTO #SexDonors FROM #SexWork WHERE sex IN (0,1);
SELECT COUNT(*) AS SoHoSo, SUM(CASE WHEN sex IS NULL THEN 1 ELSE 0 END)
    AS SoSexThieuTruocDien FROM #SexWork;

--=================================

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

--Điền Cột Age

-- N02: điền age bằng median, sau khi hoàn thành N01 sex.
-- Chạy trong CÙNG tab SSMS đã chạy 03a và 03b.
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
--=================================

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
--=========================================================================

--Điền Null platelets

-- N04: điền platelets bằng mean, nối tiếp N03 CPK.
-- Chạy trong CÙNG tab đã chạy 03a, 03b, 03c, 03d.
-- Cấp 1: sex,anaemia -> cấp 2: sex -> cấp 3: toàn cột.
-- Nhóm cần ít nhất 5 mẫu; chỉ giá trị mới điền được làm tròn 2 chữ số.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#CPKWork') IS NULL
 OR OBJECT_ID('tempdb..#SexWork') IS NULL
 OR OBJECT_ID('tempdb..#SexDonors') IS NULL
    THROW 51000, N'Chạy các bước chuẩn bị, sex, age và CPK trong tab này trước.', 1;
IF EXISTS(SELECT 1 FROM #CPKWork WHERE creatinine_phosphokinase IS NULL OR sex IS NULL)
    THROW 51001, N'Kiểm tra các bước trước: vẫn còn CPK hoặc sex thiếu.', 1;
DROP TABLE IF EXISTS #PlateletsWork,#PlateletsDonors,#PlateletsTargets,#PlateletsLog;

SELECT * INTO #PlateletsWork FROM #CPKWork;
SELECT MaHoSo,platelets AS PlateletsTruoc,sex,anaemia
INTO #PlateletsTargets FROM #PlateletsWork WHERE platelets IS NULL;

-- Cố định mẫu cho từ platelets và sex QUAN SÁT trước mọi bước điền.
-- Hồ sơ thiếu sex quan sát vẫn cho platelets ở cấp toàn cột.
SELECT w.platelets,original.sex,w.anaemia
INTO #PlateletsDonors FROM #SexWork w
LEFT JOIN #SexDonors original ON original.MaHoSo=w.MaHoSo
WHERE w.platelets IS NOT NULL;

-- Mean = tổng platelets / số mẫu. Giữ 10 số lẻ trước làm tròn cuối.
;WITH Means AS (
    SELECT r.MaHoSo,level.CapNhom,COUNT(*) AS SoMauCho,
        CAST(CAST(SUM(d.platelets) AS decimal(22,6))
             / CAST(COUNT(*) AS decimal(10,0)) AS decimal(28,10)) AS MeanNhom
    FROM #PlateletsTargets r CROSS JOIN (VALUES(1),(2),(3)) level(CapNhom)
    JOIN #PlateletsDonors d ON
        (level.CapNhom=1 AND d.sex=r.sex AND d.anaemia=r.anaemia)
        OR (level.CapNhom=2 AND d.sex=r.sex) OR level.CapNhom=3
    GROUP BY r.MaHoSo,level.CapNhom HAVING COUNT(*)>=5
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY MaHoSo ORDER BY CapNhom) AS uu_tien
    FROM Means
)
SELECT r.*,p.CapNhom,p.SoMauCho,p.MeanNhom,
    CAST(ROUND(p.MeanNhom,2) AS decimal(18,2)) AS PlateletsDien
INTO #PlateletsLog FROM #PlateletsTargets r
LEFT JOIN Preferred p ON p.MaHoSo=r.MaHoSo AND p.uu_tien=1;

UPDATE w SET platelets=l.PlateletsDien
FROM #PlateletsWork w JOIN #PlateletsLog l ON l.MaHoSo=w.MaHoSo
WHERE w.platelets IS NULL AND l.PlateletsDien IS NOT NULL;

-- CHỤP BẢNG 1: tổng kết số ô trước/sau điền.
SELECT (SELECT COUNT(*) FROM #PlateletsWork) AS SoHoSo,
    COUNT(*) AS SoPlateletsThieuTruocDien,COUNT(PlateletsDien) AS SoODaDien,
    (SELECT COUNT(*) FROM #PlateletsWork WHERE platelets IS NULL) AS SoPlateletsThieuSauDien
FROM #PlateletsLog;

-- CHỤP BẢNG 2: khóa nhóm, cấp nhóm, số mẫu cho, mean và giá trị điền.
SELECT * FROM #PlateletsLog ORDER BY MaHoSo;
-- Bản làm việc nối tiếp là #PlateletsWork; chưa phải bảng after cuối.

--=============================================================================

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

--========================================


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

--========================================================================

-- N07: xử lý ejection_fraction bằng median, nối tiếp N06 serum_sodium.
-- Chạy trong CÙNG tab đã chạy các bước 03a đến 03g.
-- Cấp 1: sex,high_blood_pressure -> cấp 2: sex -> cấp 3: toàn cột.
-- Nhóm cần ít nhất 5 mẫu; chỉ giá trị mới điền được làm tròn số nguyên.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#SodiumWork') IS NULL
 OR OBJECT_ID('tempdb..#SexWork') IS NULL
 OR OBJECT_ID('tempdb..#SexDonors') IS NULL
    THROW 51000, N'Chạy các bước trước đến N06 serum_sodium trong tab này trước.', 1;
IF EXISTS(SELECT 1 FROM #SodiumWork WHERE serum_sodium IS NULL OR serum_sodium=999 OR sex IS NULL)
    THROW 51001, N'Kiểm tra các bước trước: serum_sodium hoặc sex chưa xử lý xong.', 1;
DROP TABLE IF EXISTS #EFWork,#EFDonors,#EFTargets,#EFLog;

SELECT * INTO #EFWork FROM #SodiumWork;
SELECT MaHoSo,ejection_fraction AS EFTruoc,sex,high_blood_pressure,
    CASE WHEN ejection_fraction=150 THEN N'EF bị làm nhiễu'
         ELSE N'NULL hoặc sai kiểu' END AS LyDo
INTO #EFTargets FROM #EFWork
WHERE ejection_fraction IS NULL OR ejection_fraction=150;
UPDATE #EFWork SET ejection_fraction=NULL WHERE ejection_fraction=150;

-- Mẫu cho cố định: EF hợp lệ và sex QUAN SÁT trước N01.
-- Mẫu thiếu sex quan sát vẫn cho EF ở cấp toàn cột; không dùng EF nhiễu 150.
SELECT w.ejection_fraction AS EF,original.sex,w.high_blood_pressure
INTO #EFDonors FROM #SexWork w
LEFT JOIN #SexDonors original ON original.MaHoSo=w.MaHoSo
WHERE w.ejection_fraction IS NOT NULL AND w.ejection_fraction<>150;

;WITH Ranked AS (
    SELECT r.MaHoSo,level.CapNhom,d.EF,
        ROW_NUMBER() OVER(PARTITION BY r.MaHoSo,level.CapNhom ORDER BY d.EF) AS rn,
        COUNT(*) OVER(PARTITION BY r.MaHoSo,level.CapNhom) AS SoMauCho
    FROM #EFTargets r CROSS JOIN (VALUES(1),(2),(3)) level(CapNhom)
    JOIN #EFDonors d ON
        (level.CapNhom=1 AND d.sex=r.sex AND d.high_blood_pressure=r.high_blood_pressure)
        OR (level.CapNhom=2 AND d.sex=r.sex) OR level.CapNhom=3
), Medians AS (
    SELECT MaHoSo,CapNhom,MAX(SoMauCho) AS SoMauCho,AVG(EF) AS MedianNhom
    FROM Ranked WHERE SoMauCho>=5 AND rn IN((SoMauCho+1)/2,(SoMauCho+2)/2)
    GROUP BY MaHoSo,CapNhom
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY MaHoSo ORDER BY CapNhom) AS uu_tien
    FROM Medians
)
SELECT r.*,p.CapNhom,p.SoMauCho,p.MedianNhom,
    CAST(ROUND(p.MedianNhom,0) AS decimal(18,0)) AS EFDien
INTO #EFLog FROM #EFTargets r
LEFT JOIN Preferred p ON p.MaHoSo=r.MaHoSo AND p.uu_tien=1;

UPDATE w SET ejection_fraction=l.EFDien
FROM #EFWork w JOIN #EFLog l ON l.MaHoSo=w.MaHoSo
WHERE w.ejection_fraction IS NULL AND l.EFDien IS NOT NULL;

-- CHỤP BẢNG 1: 0 ô thiếu ban đầu + 1 EF nhiễu 150 = 1 ô cần xử lý.
SELECT (SELECT COUNT(*) FROM #EFWork) AS SoHoSo,
    SUM(CASE WHEN EFTruoc IS NULL THEN 1 ELSE 0 END) AS SoNullHoacSaiKieu,
    SUM(CASE WHEN EFTruoc=150 THEN 1 ELSE 0 END) AS SoEFNhieu,
    COUNT(*) AS SoOCanDien,COUNT(EFDien) AS SoODaDien,
    (SELECT COUNT(*) FROM #EFWork WHERE ejection_fraction IS NULL) AS SoEFThieuSauDien
FROM #EFLog;

-- CHỤP BẢNG 2: EF trước xử lý, nhóm, số mẫu cho, median và EF điền.
SELECT * FROM #EFLog ORDER BY MaHoSo;
-- Bản làm việc nối tiếp là #EFWork; chưa phải bảng after cuối.

--====================================================================



-- KIỂM CHỨNG N01: che 20% sex quan sát, seed 42, so hai cách dự đoán.
-- Chạy trong CÙNG tab có #SexDonors từ bước 03a.
-- Chỉ tạo bảng tạm kiểm chứng; không sửa raw hoặc kết quả N01-N07.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#SexDonors') IS NULL
    THROW 51000,N'Chạy bước 03a trong tab này trước để có mẫu quan sát gốc.',1;
DROP TABLE IF EXISTS #CvSexObserved,#CvSexMask,#CvSexDonors,#CvSexLog;

-- Mã TỰ TÍNH từ 13 giá trị chuẩn hóa, để SQL/Python chọn cùng hồ sơ.
-- Không có danh sách mã ghi sẵn. MaHoSo không dùng để chọn mẫu.
SELECT d.*,CONVERT(char(64),HASHBYTES('SHA2_256',CONCAT(
    CONVERT(nvarchar(max),N'age='),COALESCE(CONVERT(nvarchar(40),age),N'~'),
    N'|anaemia=',COALESCE(CONVERT(nvarchar(40),anaemia),N'~'),
    N'|creatinine_phosphokinase=',COALESCE(CONVERT(nvarchar(40),creatinine_phosphokinase),N'~'),
    N'|diabetes=',COALESCE(CONVERT(nvarchar(40),diabetes),N'~'),
    N'|ejection_fraction=',COALESCE(CONVERT(nvarchar(40),ejection_fraction),N'~'),
    N'|high_blood_pressure=',COALESCE(CONVERT(nvarchar(40),high_blood_pressure),N'~'),
    N'|platelets=',COALESCE(CONVERT(nvarchar(40),platelets),N'~'),
    N'|serum_creatinine=',COALESCE(CONVERT(nvarchar(40),serum_creatinine),N'~'),
    N'|serum_sodium=',COALESCE(CONVERT(nvarchar(40),serum_sodium),N'~'),
    N'|sex=',COALESCE(CONVERT(nvarchar(40),sex),N'~'),
    N'|smoking=',COALESCE(CONVERT(nvarchar(40),smoking),N'~'),
    N'|time=',COALESCE(CONVERT(nvarchar(40),time),N'~'),
    N'|DEATH_EVENT=',COALESCE(CONVERT(nvarchar(40),DEATH_EVENT),N'~'))),2) AS record_key
INTO #CvSexObserved FROM #SexDonors d WHERE sex IN(0,1);

DECLARE @SoMauChe int=(SELECT (COUNT(*)+4)/5 FROM #CvSexObserved);
SELECT TOP (@SoMauChe) * INTO #CvSexMask FROM #CvSexObserved
ORDER BY CONVERT(char(64),HASHBYTES('SHA2_256',N'42|N01|'+record_key),2),record_key;
SELECT o.* INTO #CvSexDonors FROM #CvSexObserved o
WHERE NOT EXISTS(SELECT 1 FROM #CvSexMask m WHERE m.record_key=o.record_key);
IF (SELECT COUNT(*) FROM #CvSexDonors)<5
    THROW 51001,N'Không đủ 5 mẫu cho sau khi che; dừng kiểm chứng.',1;

-- Chỉ phần CHƯA che được dùng tính mode nhóm và mode nền toàn cột.
DECLARE @ModeToanCot decimal(18,6);
SELECT TOP(1) @ModeToanCot=sex FROM #CvSexDonors
GROUP BY sex ORDER BY COUNT(*) DESC,sex;

;WITH Frequencies AS (
    SELECT r.record_key,level.CapNhom,d.sex,COUNT(*) AS TanSuat
    FROM #CvSexMask r CROSS JOIN (VALUES(1),(2),(3),(4)) level(CapNhom)
    JOIN #CvSexDonors d ON
        (level.CapNhom=1 AND d.anaemia=r.anaemia AND d.diabetes=r.diabetes
            AND d.smoking=r.smoking AND d.high_blood_pressure=r.high_blood_pressure)
        OR (level.CapNhom=2 AND d.anaemia=r.anaemia AND d.diabetes=r.diabetes)
        OR (level.CapNhom=3 AND d.diabetes=r.diabetes) OR level.CapNhom=4
    GROUP BY r.record_key,level.CapNhom,d.sex
), GroupSizes AS (
    SELECT *,SUM(TanSuat) OVER(PARTITION BY record_key,CapNhom) AS SoMauCho
    FROM Frequencies
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY record_key
        ORDER BY CapNhom,TanSuat DESC,sex) AS uu_tien
    FROM GroupSizes WHERE SoMauCho>=5
)
SELECT r.record_key,r.MaHoSo,r.sex AS SexThuc,r.anaemia,r.diabetes,
    r.smoking,r.high_blood_pressure,p.CapNhom,p.SoMauCho,
    p.sex AS DuDoanTheoNhom,@ModeToanCot AS DuDoanToanCot
INTO #CvSexLog FROM #CvSexMask r
LEFT JOIN Preferred p ON p.record_key=r.record_key AND p.uu_tien=1;

-- CHỤP BẢNG 1: quy mô chia mẫu kiểm chứng.
SELECT (SELECT COUNT(*) FROM #CvSexObserved) AS SexQuanSatHopLe,
    (SELECT COUNT(*) FROM #CvSexMask) AS SoMauBiChe,
    (SELECT COUNT(*) FROM #CvSexDonors) AS SoMauChoConLai,42 AS Seed;

-- CHỤP BẢNG 2: Accuracy = số đúng / số mẫu bị che * 100%.
SELECT N'Mode theo nhóm' AS PhuongPhap,COUNT(*) AS SoMauCanDuDoan,
    COUNT(DuDoanTheoNhom) AS SoMauDuDoanDuoc,
    SUM(CASE WHEN DuDoanTheoNhom=SexThuc THEN 1 ELSE 0 END) AS SoDung,
    CASE WHEN COUNT(DuDoanTheoNhom)=COUNT(*) THEN
        CAST(100.0*SUM(CASE WHEN DuDoanTheoNhom=SexThuc THEN 1 ELSE 0 END)
             / COUNT(*) AS decimal(6,2)) END AS AccuracyPhanTram
FROM #CvSexLog
UNION ALL
SELECT N'Mode toàn cột',COUNT(*),COUNT(DuDoanToanCot),
    SUM(CASE WHEN DuDoanToanCot=SexThuc THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN DuDoanToanCot=SexThuc THEN 1 ELSE 0 END)
         / COUNT(*) AS decimal(6,2))
FROM #CvSexLog;

-- CHỤP BẢNG 3: mười ví dụ; giá trị thật chỉ dùng chấm kết quả.
SELECT TOP(10) MaHoSo,SexThuc,CapNhom,SoMauCho,DuDoanTheoNhom,DuDoanToanCot
FROM #CvSexLog ORDER BY MaHoSo;
-- Nhật ký đủ 56 mẫu và khóa đối chiếu vẫn được giữ tại #CvSexLog.

--=================================================================================

-- MỤC 3b(ii): bước 1, chọn thuộc tính theo yêu cầu làm mịn.
-- Chạy trong CÙNG tab đã hoàn thành N07, có bảng #EFWork.
-- Chỉ khảo sát; chưa thay đổi giá trị hay thực hiện làm mịn.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#EFWork') IS NULL
    THROW 51000,N'Cần bảng #EFWork sau N07 trong cùng tab kết nối.',1;
DROP TABLE IF EXISTS #SmoothStats;

-- Khảo sát 12 thuộc tính gốc, không làm mịn ID hoặc nhãn DEATH_EVENT.
-- Miền giá trị được tính bằng Max-Min; độ lệch chuẩn mẫu dùng STDEV.
SELECT v.TenCot,COUNT(v.GiaTri) AS SoGiaTri,
    MIN(v.GiaTri) AS [Min],MAX(v.GiaTri) AS [Max],
    MAX(v.GiaTri)-MIN(v.GiaTri) AS MienGiaTri,
    STDEV(CONVERT(float,v.GiaTri)) AS DoLechChuan
INTO #SmoothStats
FROM #EFWork w
CROSS APPLY (VALUES
    (N'age',w.age),
    (N'anaemia',w.anaemia),
    (N'creatinine_phosphokinase',w.creatinine_phosphokinase),
    (N'diabetes',w.diabetes),
    (N'ejection_fraction',w.ejection_fraction),
    (N'high_blood_pressure',w.high_blood_pressure),
    (N'platelets',w.platelets),
    (N'serum_creatinine',w.serum_creatinine),
    (N'serum_sodium',w.serum_sodium),
    (N'sex',w.sex),
    (N'smoking',w.smoking),
    (N'time',w.time)
) v(TenCot,GiaTri)
GROUP BY v.TenCot;

-- CHỤP BẢNG 1: thống kê dùng để lựa chọn, sắp miền giá trị giảm dần.
SELECT TenCot,SoGiaTri,
    CAST([Min] AS decimal(18,2)) AS [Min],
    CAST([Max] AS decimal(18,2)) AS [Max],
    CAST(MienGiaTri AS decimal(18,2)) AS MienGiaTri,
    CAST(DoLechChuan AS decimal(18,2)) AS DoLechChuan
FROM #SmoothStats ORDER BY MienGiaTri DESC,TenCot;

-- CHỤP BẢNG 2: chọn riêng theo từng tiêu chí, không mặc định cùng một cột.
SELECT N'Miền giá trị lớn nhất' AS TieuChi,TenCot AS ThuocTinh,
    CAST(MienGiaTri AS decimal(18,2)) AS GiaTriTieuChi
FROM (SELECT TOP(1) * FROM #SmoothStats ORDER BY MienGiaTri DESC,TenCot) a
UNION ALL
SELECT N'Độ lệch chuẩn lớn nhất',TenCot,
    CAST(DoLechChuan AS decimal(18,2))
FROM (SELECT TOP(1) * FROM #SmoothStats ORDER BY DoLechChuan DESC,TenCot) b;
-- Tiếp theo mới chia >=5 nhóm và tăng/giảm 10% theo yêu cầu đề.

--=====================================================

-- MỤC 3b(ii): chia miền platelets thành 5 khoảng bằng nhau, làm mịn bằng mean.
-- Chạy trong CÙNG tab có #EFWork sau N07. Đầu vào là trước mọi phép làm mịn.
-- Chỉ sửa #SmoothMeanWork; giữ nguyên #EFWork và dữ liệu nguồn.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#EFWork') IS NULL
    THROW 51000,N'Cần bảng #EFWork sau N07 trong cùng tab kết nối.',1;
IF EXISTS(SELECT 1 FROM #EFWork WHERE platelets IS NULL)
    THROW 51001,N'Platelets vẫn còn thiếu; hoàn thành điền trước khi làm mịn.',1;
DROP TABLE IF EXISTS #SmoothMeanWork,#PlateletsBins,#PlateletsGroupMean,#SmoothMeanLog;

DECLARE @SoNhom int=5;
DECLARE @Min decimal(18,6)=(SELECT MIN(platelets) FROM #EFWork);
DECLARE @Max decimal(18,6)=(SELECT MAX(platelets) FROM #EFWork);
IF @Min IS NULL OR @Max<=@Min
    THROW 51002,N'Miền platelets không đủ để chia nhóm.',1;
DECLARE @DoRong decimal(18,6)=(@Max-@Min)/@SoNhom;

SELECT * INTO #SmoothMeanWork FROM #EFWork;
-- Khoảng trái đóng, phải mở; riêng nhóm 5 lấy cả giá trị Max.
SELECT MaHoSo,platelets AS PlateletsTruoc,
    CASE WHEN platelets=@Max THEN @SoNhom
         ELSE 1+CONVERT(int,FLOOR((platelets-@Min)/@DoRong)) END AS Nhom
INTO #PlateletsBins FROM #EFWork;

-- Tính thống kê từ bản TRƯỚC làm mịn, không tính lại sau mỗi cập nhật.
;WITH GroupStats AS (
    SELECT Nhom,COUNT(*) AS SoHoSo,
        CAST(CAST(SUM(PlateletsTruoc) AS decimal(22,6))
             / CAST(COUNT(*) AS decimal(10,0)) AS decimal(28,10)) AS MeanNhom
    FROM #PlateletsBins GROUP BY Nhom
)
SELECT g.Nhom,@Min+(g.Nhom-1)*@DoRong AS CanDuoi,
    @Min+g.Nhom*@DoRong AS CanTren,
    COALESCE(s.SoHoSo,0) AS SoHoSo,s.MeanNhom,
    CAST(ROUND(s.MeanNhom,2) AS decimal(18,2)) AS PlateletsSau
INTO #PlateletsGroupMean
FROM (VALUES(1),(2),(3),(4),(5)) g(Nhom)
LEFT JOIN GroupStats s ON s.Nhom=g.Nhom;

UPDATE w SET platelets=g.PlateletsSau
FROM #SmoothMeanWork w JOIN #PlateletsBins b ON b.MaHoSo=w.MaHoSo
JOIN #PlateletsGroupMean g ON g.Nhom=b.Nhom
WHERE g.SoHoSo>0;

SELECT b.MaHoSo,b.Nhom,b.PlateletsTruoc,g.MeanNhom,w.platelets AS PlateletsSau
INTO #SmoothMeanLog
FROM #PlateletsBins b JOIN #PlateletsGroupMean g ON g.Nhom=b.Nhom
JOIN #SmoothMeanWork w ON w.MaHoSo=b.MaHoSo;

-- CHỤP BẢNG 1: tổng kết phép làm mịn.
SELECT COUNT(*) AS SoHoSo,@SoNhom AS SoNhom,
    CAST(@DoRong AS decimal(18,2)) AS DoRongNhom,
    COUNT(PlateletsSau) AS SoHoSoDaLamMin,
    SUM(CASE WHEN PlateletsTruoc<>PlateletsSau THEN 1 ELSE 0 END) AS SoGiaTriThayDoi
FROM #SmoothMeanLog;

-- CHỤP BẢNG 2: 5 khoảng, số hồ sơ, mean nhóm và giá trị thay thế.
SELECT Nhom,CAST(CanDuoi AS decimal(18,2)) AS CanDuoi,
    CAST(CanTren AS decimal(18,2)) AS CanTren,
    SoHoSo,MeanNhom,PlateletsSau
FROM #PlateletsGroupMean ORDER BY Nhom;

-- CHỤP BẢNG 3: hai ví dụ mỗi nhóm, tổng 10 trường hợp trước/sau.
;WITH Examples AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY Nhom ORDER BY PlateletsTruoc,MaHoSo) AS rn
    FROM #SmoothMeanLog
)
SELECT MaHoSo,Nhom,PlateletsTruoc,MeanNhom,
    CAST(PlateletsSau AS decimal(18,2)) AS PlateletsSau
FROM Examples WHERE rn<=2 ORDER BY Nhom,PlateletsTruoc,MaHoSo;
-- Nhật ký đủ 299 hồ sơ ở #SmoothMeanLog.
-- Tăng/giảm 10% cho các giá trị cực trị là bước riêng tiếp theo.

--==================================================

-- MỤC 3b(ii): thuộc tính có độ lệch chuẩn lớn nhất là platelets.
-- Chạy trong CÙNG tab có #EFWork sau N07.
-- Đây là phép riêng trên đầu vào trước làm mịn; không lấy #SmoothMeanWork.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#EFWork') IS NULL
    THROW 51000,N'Cần #EFWork sau N07 trong cùng tab kết nối.',1;
IF (SELECT COUNT(*) FROM #EFWork)<10
    OR EXISTS(SELECT 1 FROM #EFWork WHERE platelets IS NULL)
    THROW 51001,N'Cần ít nhất 10 hồ sơ và platelets không còn thiếu.',1;
DROP TABLE IF EXISTS #Smooth10Work,#Smooth10Log;

SELECT * INTO #Smooth10Work FROM #EFWork;

-- Chọn đúng 5 hồ sơ mỗi phía từ giá trị TRƯỚC cập nhật.
-- Nếu bằng nhau, dùng MaHoSo để xác định thứ tự trong cùng bản làm việc.
;WITH Ranked AS (
    SELECT MaHoSo,platelets AS PlateletsTruoc,
        ROW_NUMBER() OVER(ORDER BY platelets,MaHoSo) AS HangTang,
        ROW_NUMBER() OVER(ORDER BY platelets DESC,MaHoSo DESC) AS HangGiam
    FROM #EFWork
)
SELECT MaHoSo,
    CASE WHEN HangTang<=5 THEN N'5 nhỏ nhất' ELSE N'5 lớn nhất' END AS Nhom,
    CASE WHEN HangTang<=5 THEN HangTang ELSE HangGiam END AS ThuHang,
    PlateletsTruoc,
    CASE WHEN HangTang<=5 THEN 10 ELSE -10 END AS TyLePhanTram,
    CAST(ROUND(PlateletsTruoc *
        CASE WHEN HangTang<=5 THEN CAST(1.10 AS decimal(3,2))
             ELSE CAST(0.90 AS decimal(3,2)) END,2) AS decimal(18,2)) AS PlateletsSau
INTO #Smooth10Log
FROM Ranked WHERE HangTang<=5 OR HangGiam<=5;

UPDATE w SET platelets=l.PlateletsSau
FROM #Smooth10Work w JOIN #Smooth10Log l ON l.MaHoSo=w.MaHoSo;

-- CHỤP BẢNG 1: tổng kết, 299 hồ sơ và đúng 10 giá trị thay đổi.
SELECT (SELECT COUNT(*) FROM #Smooth10Work) AS SoHoSo,
    SUM(CASE WHEN TyLePhanTram=10 THEN 1 ELSE 0 END) AS SoTang10PhanTram,
    SUM(CASE WHEN TyLePhanTram=-10 THEN 1 ELSE 0 END) AS SoGiam10PhanTram,
    SUM(CASE WHEN PlateletsTruoc<>PlateletsSau THEN 1 ELSE 0 END) AS SoGiaTriThayDoi,
    (SELECT COUNT(*) FROM #Smooth10Work)-COUNT(*) AS SoHoSoGiuNguyen
FROM #Smooth10Log;

-- CHỤP BẢNG 2: đủ 10 hồ sơ trước/sau, tăng trước rồi giảm.
SELECT Nhom,ThuHang,MaHoSo,
    CAST(PlateletsTruoc AS decimal(18,2)) AS PlateletsTruoc,
    TyLePhanTram,PlateletsSau,
    CAST(PlateletsSau-PlateletsTruoc AS decimal(18,2)) AS ChenhLech
FROM #Smooth10Log
ORDER BY TyLePhanTram DESC,ThuHang;
-- Giữ nguyên #EFWork, #SmoothMeanWork và CSV nguồn.

--=============================================================

-- MỤC 3b(iii): five number summary và ngoại lệ theo quy tắc 1,5 IQR.
-- Chạy trong CÙNG tab có #EFWork sau N07.
-- Dùng bản trước các phép làm mịn để khảo sát trên cùng một mốc dữ liệu.
-- Chỉ đánh dấu, không xóa hồ sơ hay sửa giá trị.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#EFWork') IS NULL
    THROW 51000,N'Cần #EFWork sau N07 trong cùng tab kết nối.',1;
DROP TABLE IF EXISTS #OutlierValues,#FiveNumbers,#OutlierLog;

-- Khảo sát đủ 13 cột gốc lưu số; loại MaHoSo và cột phụ age_group.
SELECT w.MaHoSo,v.STT,v.TenCot,v.GiaTri
INTO #OutlierValues
FROM #EFWork w
CROSS APPLY (VALUES
    (1,N'age',w.age),
    (2,N'anaemia',w.anaemia),
    (3,N'creatinine_phosphokinase',w.creatinine_phosphokinase),
    (4,N'diabetes',w.diabetes),
    (5,N'ejection_fraction',w.ejection_fraction),
    (6,N'high_blood_pressure',w.high_blood_pressure),
    (7,N'platelets',w.platelets),
    (8,N'serum_creatinine',w.serum_creatinine),
    (9,N'serum_sodium',w.serum_sodium),
    (10,N'sex',w.sex),
    (11,N'smoking',w.smoking),
    (12,N'time',w.time),
    (13,N'DEATH_EVENT',w.DEATH_EVENT)
) v(STT,TenCot,GiaTri);

-- PERCENTILE_CONT nội suy tuyến tính, cùng cách quantile(linear) trong Python.
-- Bỏ NULL khi tính phân vị; giữ thống kê số giá trị quan sát cho từng cột.
;WITH Q AS (
    SELECT STT,TenCot,GiaTri,
        PERCENTILE_CONT(0.25) WITHIN GROUP(ORDER BY GiaTri)
            OVER(PARTITION BY STT) AS Q1,
        PERCENTILE_CONT(0.50) WITHIN GROUP(ORDER BY GiaTri)
            OVER(PARTITION BY STT) AS Median,
        PERCENTILE_CONT(0.75) WITHIN GROUP(ORDER BY GiaTri)
            OVER(PARTITION BY STT) AS Q3
    FROM #OutlierValues WHERE GiaTri IS NOT NULL
)
SELECT STT,TenCot,COUNT(*) AS SoGiaTri,
    MIN(GiaTri) AS [Min],CAST(MAX(Q1) AS decimal(18,6)) AS Q1,
    CAST(MAX(Median) AS decimal(18,6)) AS Median,
    CAST(MAX(Q3) AS decimal(18,6)) AS Q3,MAX(GiaTri) AS [Max]
INTO #FiveNumbers FROM Q GROUP BY STT,TenCot;

-- IQR = Q3-Q1; ngoại lệ khi x < Q1-1,5*IQR hoặc x > Q3+1,5*IQR.
-- Giá trị đúng bằng cận không bị đánh dấu. Không làm tròn trước so sánh.
SELECT v.*,f.Q1,f.Q3,f.Q3-f.Q1 AS IQR,
    f.Q1-1.5*(f.Q3-f.Q1) AS CanDuoi,
    f.Q3+1.5*(f.Q3-f.Q1) AS CanTren,
    CASE WHEN v.GiaTri<f.Q1-1.5*(f.Q3-f.Q1) THEN N'Dưới cận'
         WHEN v.GiaTri>f.Q3+1.5*(f.Q3-f.Q1) THEN N'Trên cận' END AS ViTri
INTO #OutlierLog
FROM #OutlierValues v JOIN #FiveNumbers f ON f.STT=v.STT;

-- CHỤP BẢNG 1: Min, Q1, Median, Q3, Max của đủ 13 cột.
SELECT TenCot,SoGiaTri,
    CAST([Min] AS decimal(18,2)) AS [Min],
    CAST(Q1 AS decimal(18,2)) AS Q1,
    CAST(Median AS decimal(18,2)) AS Median,
    CAST(Q3 AS decimal(18,2)) AS Q3,
    CAST([Max] AS decimal(18,2)) AS [Max]
FROM #FiveNumbers ORDER BY STT;

-- CHỤP BẢNG 2: khoảng IQR và số ngoại lệ từng cột.
SELECT TenCot,CAST(MAX(IQR) AS decimal(18,2)) AS IQR,
    CAST(MAX(CanDuoi) AS decimal(18,2)) AS CanDuoi,
    CAST(MAX(CanTren) AS decimal(18,2)) AS CanTren,
    SUM(CASE WHEN ViTri=N'Dưới cận' THEN 1 ELSE 0 END) AS SoDuoiCan,
    SUM(CASE WHEN ViTri=N'Trên cận' THEN 1 ELSE 0 END) AS SoTrenCan,
    COUNT(ViTri) AS TongNgoaiLe
FROM #OutlierLog GROUP BY STT,TenCot ORDER BY STT;

-- CHỤP BẢNG 3: tối đa 3 ví dụ mỗi cột có ngoại lệ.
;WITH Examples AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY STT ORDER BY GiaTri,MaHoSo) AS rn
    FROM #OutlierLog WHERE ViTri IS NOT NULL
)
SELECT TenCot,MaHoSo,CAST(GiaTri AS decimal(18,2)) AS GiaTri,
    CAST(CanDuoi AS decimal(18,2)) AS CanDuoi,
    CAST(CanTren AS decimal(18,2)) AS CanTren,ViTri
FROM Examples WHERE rn<=3 ORDER BY STT,rn;
-- Nhật ký đầy đủ ở #OutlierLog; lọc ViTri IS NOT NULL để lấy mọi ô bị đánh dấu.
-- Với 6 cột mã danh mục/nhị phân, IQR chỉ là khảo sát số học.
-- Kiểm tra miền mã hợp lệ 0/1 riêng; DEATH_EVENT=2 là mã sai, không phải nhãn mới.
-- Ngoại lệ thống kê không đồng nghĩa lỗi dữ liệu, không tự động loại bỏ.

--========================================================

-- MỤC 3b(iv): chủ động tạo 5 cách ghi sex khác nhau rồi hiệu chỉnh.
-- Chạy trong CÙNG tab có #EFWork sau N07.
-- Đây là 5 ví dụ thực hành tạo thêm trên BẢN SAO, không phải 5 lỗi mới tìm thấy.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#EFWork') IS NULL
    THROW 51000,N'Cần #EFWork sau N07 trong cùng tab kết nối.',1;
IF (SELECT COUNT(*) FROM #EFWork WHERE sex IN(0,1))<5
    THROW 51001,N'Cần ít nhất 5 hồ sơ có sex hợp lệ.',1;
DROP TABLE IF EXISTS #CategoryPractice,#CategoryPracticeLog;

-- Giữ sex dạng chuỗi để có thể nhập các cách viết không nhất quán.
SELECT MaHoSo,CONVERT(nvarchar(50),CONVERT(int,sex)) AS SexText
INTO #CategoryPractice FROM #EFWork;

-- Lưu giá trị gốc TRƯỚC khi chủ động chỉnh 5 ô.
;WITH Chosen AS (
    SELECT TOP(5) MaHoSo,CONVERT(int,sex) AS SexGoc
    FROM #EFWork WHERE sex IN(0,1) ORDER BY MaHoSo
), Numbered AS (
    SELECT *,ROW_NUMBER() OVER(ORDER BY MaHoSo) AS STT FROM Chosen
)
SELECT n.STT,n.MaHoSo,n.SexGoc,
    CASE WHEN n.SexGoc=1 THEN v.CachGhiNam ELSE v.CachGhiNu END AS SexKhongNhatQuan
INTO #CategoryPracticeLog
FROM Numbered n JOIN (VALUES
    (1,N'M',       N'F'),
    (2,N'm',       N'f'),
    (3,N'Male',    N'Female'),
    (4,N'  male  ',N'  female  '),
    (5,N'MALE',    N'FEMALE')
) v(STT,CachGhiNam,CachGhiNu) ON v.STT=n.STT;

-- Chủ động chỉnh đúng 5 ô, giữ các ô còn lại.
UPDATE w SET SexText=l.SexKhongNhatQuan
FROM #CategoryPractice w JOIN #CategoryPracticeLog l ON l.MaHoSo=w.MaHoSo;

-- Hiệu chỉnh bằng QUY TẮC, không lấy SexGoc để gán đáp án.
-- Bỏ khoảng trắng đầu/cuối, đổi chữ thường: m/male -> 1; f/female -> 0.
UPDATE #CategoryPractice SET SexText=
    CASE LOWER(LTRIM(RTRIM(SexText)))
        WHEN N'm' THEN N'1' WHEN N'male' THEN N'1'
        WHEN N'f' THEN N'0' WHEN N'female' THEN N'0'
        ELSE LTRIM(RTRIM(SexText)) END;

-- CHỤP BẢNG 1: đủ 5 ví dụ gốc -> cách ghi khác -> sau hiệu chỉnh.
-- Dấu [] và số ký tự giúp thấy khoảng trắng, kể cả ở cuối chuỗi.
SELECT l.STT,l.MaHoSo,l.SexGoc,
    N'['+l.SexKhongNhatQuan+N']' AS CachGhiTruocSua,
    DATALENGTH(l.SexKhongNhatQuan)/2 AS SoKyTu,
    w.SexText AS SexSauSua,
    CASE WHEN TRY_CONVERT(int,w.SexText)=l.SexGoc THEN N'Khớp gốc'
         ELSE N'Cần kiểm tra' END AS DoiChieu
FROM #CategoryPracticeLog l JOIN #CategoryPractice w ON w.MaHoSo=l.MaHoSo
ORDER BY l.STT;

-- CHỤP BẢNG 2: tổng kết việc khôi phục 5 ví dụ.
SELECT (SELECT COUNT(*) FROM #CategoryPractice) AS SoHoSo,
    COUNT(*) AS SoViDuChuDongTao,
    SUM(CASE WHEN TRY_CONVERT(int,w.SexText)=l.SexGoc THEN 1 ELSE 0 END) AS SoKhopGiaTriGoc,
    (SELECT COUNT(*) FROM #CategoryPractice
     WHERE SexText IS NULL OR SexText NOT IN(N'0',N'1')) AS SoMaSexKhongHopLeSauSua
FROM #CategoryPracticeLog l JOIN #CategoryPractice w ON w.MaHoSo=l.MaHoSo;
-- Giữ nguyên #EFWork, CSV before và các kết quả đã làm.
-- sex đã được chuẩn hóa trong chuẩn bị N01; đây là minh chứng 5 ô theo đề.
-- DEATH_EVENT=2 sẽ xử lý riêng; không dùng quy tắc giới tính để sửa nhãn kết quả.

--=========================================================


-- MỤC 3b(iv): xử lý mã DEATH_EVENT không thuộc miền 0/1.
-- Chạy trong CÙNG tab có #EFWork sau N07. Không sửa nguồn.
-- Không có căn cứ đổi nhãn 2 thành 0 hay 1; chuyển thành NULL trên bản sao.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#EFWork') IS NULL
    THROW 51000,N'Cần #EFWork sau N07 trong cùng tab kết nối.',1;
DROP TABLE IF EXISTS #LabelWork,#LabelLog,#LabelValid,#LabelPending;

SELECT * INTO #LabelWork FROM #EFWork;

-- Lưu nhãn trước xử lý để có thể kiểm tra lại.
SELECT MaHoSo,DEATH_EVENT AS NhanTruoc,
    CASE WHEN DEATH_EVENT IS NULL THEN N'Nhãn bị thiếu'
         ELSE N'Nhãn ngoài miền 0/1' END AS LyDo
INTO #LabelLog FROM #LabelWork
WHERE DEATH_EVENT IS NULL OR DEATH_EVENT NOT IN(0,1);

UPDATE #LabelWork SET DEATH_EVENT=NULL
WHERE DEATH_EVENT NOT IN(0,1);

-- Giữ đủ hồ sơ trong #LabelWork; tách hai tập để dùng đúng mục đích.
-- #LabelValid: dùng khi phân tích cần nhãn hợp lệ (so sánh nhóm 0/1, huấn luyện).
-- #LabelPending: giữ đủ thuộc tính để kiểm tra; không xóa bệnh nhân khỏi nguồn.
SELECT * INTO #LabelValid FROM #LabelWork WHERE DEATH_EVENT IN(0,1);
SELECT * INTO #LabelPending FROM #LabelWork WHERE DEATH_EVENT IS NULL;

-- CHỤP BẢNG 1: tổng kết, dự kiến 299 = 298 hợp lệ + 1 chờ xác minh.
SELECT (SELECT COUNT(*) FROM #EFWork) AS SoHoSoTruoc,
    (SELECT COUNT(*) FROM #LabelWork) AS SoHoSoGiuLai,
    (SELECT COUNT(*) FROM #LabelLog WHERE NhanTruoc NOT IN(0,1)) AS SoNhanSai,
    (SELECT COUNT(*) FROM #LabelValid) AS SoNhanHopLe,
    (SELECT COUNT(*) FROM #LabelPending) AS SoChoXacMinh,
    (SELECT COUNT(*) FROM #LabelWork WHERE DEATH_EVENT NOT IN(0,1)) AS SoNhanSaiSauXuLy;

-- CHỤP BẢNG 2: nhật ký nhãn sai/thiếu trước và sau.
SELECT l.MaHoSo,CAST(l.NhanTruoc AS decimal(18,0)) AS NhanTruoc,
    CAST(w.DEATH_EVENT AS decimal(18,0)) AS NhanSau,l.LyDo,
    N'Giữ hồ sơ; chờ xác minh nhãn' AS CachXuLy
FROM #LabelLog l JOIN #LabelWork w ON w.MaHoSo=l.MaHoSo
ORDER BY l.MaHoSo;

-- CHỤP BẢNG 3: tần suất nhãn trước/sau; 0 và 1 phải giữ nguyên số lượng.
;WITH Frequencies AS (
    SELECT 1 AS STT,N'Trước xử lý' AS GiaiDoan,DEATH_EVENT AS Nhan,COUNT(*) AS SoLuong
    FROM #EFWork GROUP BY DEATH_EVENT
    UNION ALL
    SELECT 2,N'Sau xử lý',DEATH_EVENT,COUNT(*)
    FROM #LabelWork GROUP BY DEATH_EVENT
)
SELECT GiaiDoan,CASE WHEN Nhan IS NULL THEN N'<NULL>'
    ELSE CONVERT(nvarchar(30),CAST(Nhan AS decimal(18,0))) END AS Nhan,SoLuong
FROM Frequencies ORDER BY STT,Nhan;
-- NULL sau xử lý vẫn là nhãn chưa biết, không phải đã khôi phục đúng nhãn gốc.
-- Đây là bản làm việc trung gian; chưa hợp nhất thành CSV after cuối.

--==============================================================

-- MỤC 3d: trường hợp 1, giảm số chiều theo mục tiêu thống kê định lượng.
-- Chạy trong CÙNG tab có #LabelWork sau xử lý nhãn.
-- Tạo bảng con; không thay thế dữ liệu chính hoặc kết luận các biến khác vô ích.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
    THROW 51000,N'Cần #LabelWork; chạy 07b_xu_ly_death_event.sql trong tab này trước.',1;
DROP TABLE IF EXISTS #ReducedClinical6;

-- Giữ 6 biến: tuổi, CPK, EF, tiểu cầu, creatinine và natri.
-- Không đưa 5 mã danh mục và thời gian theo dõi vào bảng chỉ số định lượng này.
-- Nhãn DEATH_EVENT giữ ở #LabelWork, không tính là thuộc tính đầu vào.
-- MaHoSo chỉ là khóa liên kết, không tính vào 6 chiều.
SELECT MaHoSo,age,creatinine_phosphokinase,ejection_fraction,
    platelets,serum_creatinine,serum_sodium
INTO #ReducedClinical6 FROM #LabelWork;

-- CHỤP BẢNG 1: quy mô trước/sau, so 12 đầu vào với 6 thuộc tính giữ lại.
DECLARE @SoCotGoc int=(
    SELECT COUNT(*) FROM tempdb.sys.columns
    WHERE object_id=OBJECT_ID('tempdb..#LabelWork')
      AND name NOT IN(N'MaHoSo',N'age_group'));
DECLARE @SoCotSau int=(
    SELECT COUNT(*) FROM tempdb.sys.columns
    WHERE object_id=OBJECT_ID('tempdb..#ReducedClinical6') AND name<>N'MaHoSo');
SELECT (SELECT COUNT(*) FROM #LabelWork) AS SoHoSoTruoc,
    (SELECT COUNT(*) FROM #ReducedClinical6) AS SoHoSoSau,
    @SoCotGoc AS SoCotGocGomNhan,
    @SoCotGoc-1 AS SoThuocTinhDauVao,
    @SoCotSau AS SoThuocTinhGiuLai,
    CAST(100.0*(@SoCotGoc-1-@SoCotSau)/NULLIF(@SoCotGoc-1,0)
         AS decimal(6,2)) AS TyLeGiamPhanTram;

-- CHỤP BẢNG 2: danh sách 6 chiều thực tế của bảng kết quả.
SELECT ROW_NUMBER() OVER(ORDER BY column_id) AS STT,name AS ThuocTinhGiuLai
FROM tempdb.sys.columns
WHERE object_id=OBJECT_ID('tempdb..#ReducedClinical6') AND name<>N'MaHoSo'
ORDER BY column_id;

-- CHỤP BẢNG 3: năm hồ sơ minh họa, giá trị giữ nguyên từ #LabelWork.
SELECT TOP(5) MaHoSo,
    CAST(age AS decimal(18,1)) AS age,
    CAST(creatinine_phosphokinase AS decimal(18,0)) AS CPK,
    CAST(ejection_fraction AS decimal(18,0)) AS EF,
    CAST(platelets AS decimal(18,2)) AS platelets,
    CAST(serum_creatinine AS decimal(18,2)) AS serum_creatinine,
    CAST(serum_sodium AS decimal(18,0)) AS serum_sodium
FROM #ReducedClinical6 ORDER BY MaHoSo;
-- Chỉ định dạng bảng minh họa; dữ liệu trong #ReducedClinical6 không làm tròn lại.
-- Bảng con phục vụ thống kê 6 biến; không dùng thay tập đầy đủ khi cần giới tính,
-- tiền sử, hút thuốc, thời gian hoặc nhãn kết quả. Có thể nối lại bằng MaHoSo.
-- Trường hợp 2 (tổng hợp nhóm để giảm số dòng) sẽ thực hiện riêng.

--=============================================================

-- MỤC 3d: trường hợp 2, giảm số dòng bằng tổng hợp nhóm.
-- Chạy trong CÙNG tab có #LabelWork (299 hồ sơ sau xử lý nhãn).
-- Dùng bảng đầy đủ, không dùng bảng con sáu chiều vì cần sex.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
    THROW 51000,N'Cần #LabelWork trong cùng tab kết nối.',1;
IF EXISTS(SELECT 1 FROM #LabelWork WHERE age IS NULL OR age<=0
    OR sex IS NULL OR sex NOT IN(0,1))
    THROW 51001,N'Cần tuổi và sex hợp lệ trước khi tổng hợp nhóm.',1;
DROP TABLE IF EXISTS #GroupReductionInput,#ReducedAgeSex;

-- Tuổi sau N02: A1 <50; A2 [50,60); A3 [60,70); A4 >=70.
-- sex sau N01: 0 = nữ, 1 = nam, gồm cả giá trị đã điền.
SELECT MaHoSo,
    CASE WHEN age<50 THEN N'A1' WHEN age<60 THEN N'A2'
         WHEN age<70 THEN N'A3' ELSE N'A4' END AS NhomTuoi,
    CONVERT(int,sex) AS sex,ejection_fraction,platelets,serum_creatinine
INTO #GroupReductionInput FROM #LabelWork;

-- Một dòng cho mỗi tổ hợp nhóm tuổi và giới tính có hồ sơ.
-- Giữ mean với 10 số lẻ; chỉ làm tròn hai chữ số khi hiển thị.
SELECT NhomTuoi,sex,COUNT(*) AS SoHoSo,
    CAST(CAST(SUM(ejection_fraction) AS decimal(22,6)) /
         CAST(COUNT(ejection_fraction) AS decimal(10,0)) AS decimal(28,10)) AS EFMean,
    CAST(CAST(SUM(platelets) AS decimal(22,6)) /
         CAST(COUNT(platelets) AS decimal(10,0)) AS decimal(28,10)) AS PlateletsMean,
    CAST(CAST(SUM(serum_creatinine) AS decimal(22,6)) /
         CAST(COUNT(serum_creatinine) AS decimal(10,0)) AS decimal(28,10)) AS CreatinineMean
INTO #ReducedAgeSex
FROM #GroupReductionInput GROUP BY NhomTuoi,sex;

-- CHỤP BẢNG 1: quy mô và kiểm tra đủ hồ sơ, dự kiến 299 -> 8 dòng nhóm.
SELECT (SELECT COUNT(*) FROM #LabelWork) AS SoDongTruoc,
    COUNT(*) AS SoDongTongHop,SUM(SoHoSo) AS TongHoSoDaiDien,
    CAST(100.0*((SELECT COUNT(*) FROM #LabelWork)-COUNT(*))
         / NULLIF((SELECT COUNT(*) FROM #LabelWork),0) AS decimal(6,2)) AS TyLeGiamPhanTram,
    CASE WHEN SUM(SoHoSo)=(SELECT COUNT(*) FROM #LabelWork)
         THEN N'Đủ hồ sơ' ELSE N'Cần kiểm tra' END AS KiemTra
FROM #ReducedAgeSex;

-- CHỤP BẢNG 2: toàn bộ bảng tổng hợp nhóm.
SELECT NhomTuoi,
    CASE NhomTuoi WHEN N'A1' THEN N'Dưới 50' WHEN N'A2' THEN N'50 đến dưới 60'
         WHEN N'A3' THEN N'60 đến dưới 70' ELSE N'Từ 70 trở lên' END AS KhoangTuoi,
    sex,CASE sex WHEN 0 THEN N'Nữ' ELSE N'Nam' END AS GioiTinh,
    SoHoSo,CAST(EFMean AS decimal(18,2)) AS EFTrungBinh,
    CAST(PlateletsMean AS decimal(18,2)) AS TieuCauTrungBinh,
    CAST(CreatinineMean AS decimal(18,2)) AS CreatinineTrungBinh
FROM #ReducedAgeSex ORDER BY NhomTuoi,sex;
-- Một dòng giờ đại diện MỘT NHÓM, không phải một bệnh nhân.
-- Bảng nhóm không giữ chi tiết từng hồ sơ và phân bố trong nhóm.
-- Không thể khôi phục dữ liệu cá nhân chỉ từ count và mean.
-- Khi tổng hợp tiếp phải dùng SoHoSo làm trọng số, không lấy mean các mean.
-- Không sử dụng DEATH_EVENT nên hồ sơ chờ xác minh nhãn vẫn được đại diện.
-- Giữ nguyên #LabelWork và CSV nguồn; chỉ tạo bảng tổng hợp riêng.


--====================================================================

-- MỤC 3e: chuyển 5 field boolean thành 1 field số nguyên.
-- Chạy trong CÙNG tab có #LabelWork. Chỉ tạo bảng riêng, không sửa nguồn.
-- Thứ tự cố định: anaemia, diabetes, high_blood_pressure, sex, smoking.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
    THROW 51000,N'Cần #LabelWork trong cùng tab kết nối.',1;
IF EXISTS(
    SELECT 1 FROM #LabelWork w
    CROSS APPLY(VALUES(w.anaemia),(w.diabetes),(w.high_blood_pressure),
                      (w.sex),(w.smoking)) v(GiaTri)
    WHERE v.GiaTri IS NULL OR v.GiaTri NOT IN(0,1))
    THROW 51001,N'Cả 5 field phải đủ giá trị 0/1 trước khi mã hóa.',1;
DROP TABLE IF EXISTS #BoolEncoded,#BoolDecoded;

-- Gộp thực sự: bảng này chỉ có khóa và MỘT cột mã thay cho 5 field.
SELECT MaHoSo,CONVERT(int,
    anaemia + 2*diabetes + 4*high_blood_pressure + 8*sex + 16*smoking) AS MaBoolean
INTO #BoolEncoded FROM #LabelWork;

-- Giải mã: lấy bit tương ứng bằng phép chia nguyên và phần dư.
SELECT MaHoSo,MaBoolean,
    MaBoolean % 2 AS anaemia,
    (MaBoolean / 2) % 2 AS diabetes,
    (MaBoolean / 4) % 2 AS high_blood_pressure,
    (MaBoolean / 8) % 2 AS sex,
    (MaBoolean / 16) % 2 AS smoking
INTO #BoolDecoded FROM #BoolEncoded;

-- CHỤP BẢNG 1: quy ước mã hóa và giải mã, phải giữ nguyên thứ tự này.
SELECT ThuTu,ThuocTinh,TrongSo
FROM (VALUES
    (1,N'anaemia',1),(2,N'diabetes',2),(3,N'high_blood_pressure',4),
    (4,N'sex',8),(5,N'smoking',16)
) v(ThuTu,ThuocTinh,TrongSo) ORDER BY ThuTu;

-- CHỤP BẢNG 2: kiểm tra toàn bộ hồ sơ, không chỉ các ví dụ.
SELECT COUNT(*) AS SoHoSo,5 AS SoFieldTruoc,1 AS SoFieldSau,
    MIN(d.MaBoolean) AS MaNhoNhat,MAX(d.MaBoolean) AS MaLonNhat,
    COUNT(DISTINCT d.MaBoolean) AS SoMaXuatHien,
    SUM(CASE WHEN d.anaemia=w.anaemia AND d.diabetes=w.diabetes
        AND d.high_blood_pressure=w.high_blood_pressure AND d.sex=w.sex
        AND d.smoking=w.smoking THEN 0 ELSE 1 END) AS SoHoSoGiaiMaSai
FROM #BoolDecoded d JOIN #LabelWork w ON w.MaHoSo=d.MaHoSo;

-- CHỤP BẢNG 3: chọn 5 mã khác nhau để minh họa các tổ hợp.
;WITH Examples AS (
    SELECT d.*,ROW_NUMBER() OVER(PARTITION BY d.MaBoolean ORDER BY d.MaHoSo) AS rn
    FROM #BoolDecoded d
)
SELECT TOP(5) e.MaHoSo,
    CONVERT(int,w.anaemia) AS anaemia,CONVERT(int,w.diabetes) AS diabetes,
    CONVERT(int,w.high_blood_pressure) AS high_blood_pressure,
    CONVERT(int,w.sex) AS sex,CONVERT(int,w.smoking) AS smoking,e.MaBoolean,
    CONCAT(e.anaemia,N'|',e.diabetes,N'|',e.high_blood_pressure,N'|',e.sex,N'|',e.smoking)
        AS GiaiMaTheoThuTu
FROM Examples e JOIN #LabelWork w ON w.MaHoSo=e.MaHoSo
WHERE e.rn=1 ORDER BY e.MaBoolean;
-- Miền mã có thể có: 0..31, tương ứng 32 tổ hợp; dữ liệu không nhất thiết đủ 32.
-- Mã lớn hơn không có nghĩa bệnh nặng hơn. Không dùng mã gộp như biến liên tục
-- để tính khoảng cách, tương quan hoặc suy ra mức rủi ro; cần giải mã khi phân tích.
-- DEATH_EVENT là nhãn, không gộp vào 5 đặc trưng. #LabelWork giữ nguyên đầy đủ.

--==================================================================


-- MỤC 3e: mã danh mục và thứ tự sang kiểu số nguyên.
-- Chạy trong CÙNG tab có #LabelWork. Chỉ tạo bảng mã riêng.
-- age_group là thuộc tính thứ tự đã phát sinh từ tuổi sau N02, không phải cột gốc.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
    THROW 51000,N'Cần #LabelWork trong cùng tab kết nối.',1;
IF EXISTS(SELECT 1 FROM #LabelWork w
    CROSS APPLY(VALUES(w.anaemia),(w.diabetes),(w.high_blood_pressure),
                      (w.sex),(w.smoking)) v(GiaTri)
    WHERE v.GiaTri IS NULL OR v.GiaTri NOT IN(0,1))
    THROW 51001,N'Năm mã danh mục phải đủ giá trị 0/1.',1;
IF EXISTS(SELECT 1 FROM #LabelWork WHERE DEATH_EVENT NOT IN(0,1))
    THROW 51002,N'Cần xử lý nhãn ngoài miền trước; NULL chờ xác minh được giữ.',1;
IF EXISTS(SELECT 1 FROM #LabelWork WHERE age IS NULL OR age<=0
    OR age_group IS NULL OR age_group NOT IN(N'A1',N'A2',N'A3',N'A4'))
    THROW 51003,N'Cần tuổi và age_group hợp lệ.',1;
DROP TABLE IF EXISTS #CategoryOrdinalWork;

-- Các mã 0/1 giữ nguyên ý nghĩa; chỉ chuyển kiểu lưu trữ thành int.
-- A1<A2<A3<A4 được chuyển thành 1<2<3<4, giữ thứ tự nhóm tuổi.
SELECT MaHoSo,CONVERT(int,anaemia) AS anaemia,
    CONVERT(int,diabetes) AS diabetes,
    CONVERT(int,high_blood_pressure) AS high_blood_pressure,
    CONVERT(int,sex) AS sex,CONVERT(int,smoking) AS smoking,
    CONVERT(int,DEATH_EVENT) AS DEATH_EVENT,
    CASE age_group WHEN N'A1' THEN 1 WHEN N'A2' THEN 2
         WHEN N'A3' THEN 3 WHEN N'A4' THEN 4 END AS MaNhomTuoi
INTO #CategoryOrdinalWork FROM #LabelWork;

-- CHỤP BẢNG 1: bảng quy ước thứ tự và tần suất, tổng vẫn là 299.
SELECT v.NhomTuoi,v.KhoangTuoi,v.MaNhomTuoi,COUNT(w.MaHoSo) AS SoHoSo
FROM (VALUES
    (N'A1',N'Dưới 50',1),(N'A2',N'50 đến dưới 60',2),
    (N'A3',N'60 đến dưới 70',3),(N'A4',N'Từ 70 trở lên',4)
) v(NhomTuoi,KhoangTuoi,MaNhomTuoi)
LEFT JOIN #CategoryOrdinalWork w ON w.MaNhomTuoi=v.MaNhomTuoi
GROUP BY v.NhomTuoi,v.KhoangTuoi,v.MaNhomTuoi ORDER BY v.MaNhomTuoi;

-- CHỤP BẢNG 2: kiểm tra trên TOÀN BỘ hồ sơ, kể cả nhãn thiếu.
SELECT COUNT(*) AS SoHoSo,
    (SELECT COUNT(*) FROM tempdb.sys.columns
     WHERE object_id=OBJECT_ID('tempdb..#CategoryOrdinalWork')
       AND name<>N'MaHoSo' AND TYPE_NAME(system_type_id)=N'int') AS SoCotMaKieuInt,
    COUNT(DISTINCT c.MaNhomTuoi) AS SoNhomTuoi,
    SUM(CASE WHEN c.MaNhomTuoi=CASE WHEN w.age<50 THEN 1 WHEN w.age<60 THEN 2
             WHEN w.age<70 THEN 3 ELSE 4 END THEN 0 ELSE 1 END) AS SoSaiKhoangTuoi,
    SUM(CASE WHEN c.DEATH_EVENT IS NULL THEN 1 ELSE 0 END) AS SoNhanChoXacMinh
FROM #CategoryOrdinalWork c JOIN #LabelWork w ON w.MaHoSo=c.MaHoSo;

-- CHỤP BẢNG 3: một hồ sơ mỗi nhóm tuổi, minh họa chữ -> mã số.
;WITH Examples AS (
    SELECT c.MaHoSo,w.age,w.age_group,c.MaNhomTuoi,
        ROW_NUMBER() OVER(PARTITION BY c.MaNhomTuoi ORDER BY c.MaHoSo) AS rn
    FROM #CategoryOrdinalWork c JOIN #LabelWork w ON w.MaHoSo=c.MaHoSo
)
SELECT MaHoSo,CAST(age AS decimal(18,1)) AS age,
    age_group AS NhomTuoiTruoc,MaNhomTuoi AS MaThuTuSau
FROM Examples WHERE rn=1 ORDER BY MaNhomTuoi;
-- Mã tuổi chỉ biểu thị thứ tự; khoảng cách 1 mã không đồng nghĩa cùng số năm.
-- #CategoryOrdinalWork chứa các field đã mã hóa, không thay thế bảng đầy đủ.
-- DEATH_EVENT NULL vẫn chưa biết nhãn; không biến NULL thành một loại bệnh mới.
-- Không có chuỗi chứa danh sách con nên không tạo ví dụ tách chuỗi giả.


-- XUAT KET QUA AFTER
-- Hợp nhất các kết quả đã làm; chạy trong cùng tab có các bảng tạm bên dưới.
-- Không sửa raw. Hai phép làm mịn chạy độc lập từ #EFWork.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
 OR OBJECT_ID('tempdb..#SmoothMeanWork') IS NULL
 OR OBJECT_ID('tempdb..#Smooth10Work') IS NULL
 OR OBJECT_ID('tempdb..#CategoryOrdinalWork') IS NULL
 OR OBJECT_ID('tempdb..#BoolEncoded') IS NULL
    THROW 51000,N'Cần chạy các bước làm sạch, làm mịn và mã hóa trong cùng tab.',1;
DROP TABLE IF EXISTS #HeartAfter;
SELECT w.MaHoSo,w.age,c.anaemia,w.creatinine_phosphokinase,c.diabetes,
    w.ejection_fraction,c.high_blood_pressure,w.platelets,w.serum_creatinine,
    w.serum_sodium,c.sex,c.smoking,w.time,c.DEATH_EVENT,c.MaNhomTuoi,b.MaBoolean,
    m.platelets AS platelets_mean_5_nhom,
    t.platelets AS platelets_dieu_chinh_10pct
INTO #HeartAfter
FROM #LabelWork w
JOIN #CategoryOrdinalWork c ON c.MaHoSo=w.MaHoSo
JOIN #BoolEncoded b ON b.MaHoSo=w.MaHoSo
JOIN #SmoothMeanWork m ON m.MaHoSo=w.MaHoSo
JOIN #Smooth10Work t ON t.MaHoSo=w.MaHoSo;
IF (SELECT COUNT(*) FROM #HeartAfter)<>(SELECT COUNT(*) FROM #LabelWork)
 OR (SELECT COUNT(DISTINCT MaHoSo) FROM #HeartAfter)<>(SELECT COUNT(*) FROM #HeartAfter)
    THROW 51001,N'Ghép bảng làm mất hoặc nhân bản hồ sơ.',1;
IF EXISTS(SELECT 1 FROM #HeartAfter a CROSS APPLY(VALUES
    (a.age),(a.anaemia),(a.creatinine_phosphokinase),(a.diabetes),
    (a.ejection_fraction),(a.high_blood_pressure),(a.platelets),
    (a.serum_creatinine),(a.serum_sodium),(a.sex),(a.smoking),(a.time),
    (a.MaNhomTuoi),(a.MaBoolean),(a.platelets_mean_5_nhom),
    (a.platelets_dieu_chinh_10pct)) v(GiaTri) WHERE v.GiaTri IS NULL)
    THROW 51002,N'Còn thiếu thuộc tính trong bảng after.',1;
-- Chụp bảng này để minh chứng quy mô và các phép làm mịn độc lập.
SELECT COUNT(*) AS SoHoSo,
    (SELECT COUNT(*) FROM tempdb.sys.columns WHERE object_id=OBJECT_ID('tempdb..#HeartAfter')) AS SoCotGomMaHoSo,
    SUM(CASE WHEN DEATH_EVENT IS NULL THEN 1 ELSE 0 END) AS SoNhanChoXacMinh,
    SUM(CASE WHEN platelets<>platelets_mean_5_nhom THEN 1 ELSE 0 END) AS SoThayDoiMean,
    SUM(CASE WHEN platelets<>platelets_dieu_chinh_10pct THEN 1 ELSE 0 END) AS SoThayDoi10Pct
FROM #HeartAfter;
SELECT * FROM #HeartAfter ORDER BY MaHoSo;
-- MaHoSo là khóa nội bộ, không phải số dòng CSV nguồn hay đặc trưng phân tích.
-- Giữ năm biến riêng để diễn giải; MaBoolean là biểu diễn bổ sung có thể giải mã.
-- Chỉ dùng 298 nhãn hợp lệ cho phân tích cần nhãn; các bước không cần nhãn dùng 299.

--===================================================


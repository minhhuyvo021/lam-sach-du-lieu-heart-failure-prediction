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

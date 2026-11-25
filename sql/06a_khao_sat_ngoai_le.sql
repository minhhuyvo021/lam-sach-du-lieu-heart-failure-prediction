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

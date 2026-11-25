-- MỤC 3f: thống kê sau tiền xử lý trên bảng cố định.
-- Trước tiên nạp dữ liệu vào HeartFailure_DoAn (qua BULK INSERT hoặc công cụ Import).
-- Chọn bản after_SQL.csv, đặt bảng dbo.heart_after, gồm 18 cột.
-- Ưu tiên decimal(18,6); DEATH_EVENT phải Allow Nulls.
-- Theo lựa chọn của người thực hiện, giữ bảng đã import bằng float.
-- Một số giá trị lệch ở hàng phần trăm so với CSV; đối chiếu cần báo sai số,
-- không kết luận bảng import khớp tuyệt đối với CSV hoặc kết quả Python.
-- Chỉ đọc bảng after; không cập nhật dữ liệu hoặc chạy lại làm sạch.
USE HeartFailure_DoAn;
GO
-- ================= PHẦN B: THỐNG KÊ MỤC 3f =================
-- Phần này chỉ đọc bảng cố định; chạy lại trong phiên kết nối SQL mới vẫn được.
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.heart_after',N'U') IS NULL
    THROW 51010,N'Chưa có dbo.heart_after. Import CSV after thành bảng này trước.',1;

-- Kiểm tra kiểu lưu trữ trước khi dùng các phép tính.
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.heart_after'))<>18
    THROW 51011,N'Bảng after phải có 18 cột.',1;
IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.heart_after')
    AND TYPE_NAME(system_type_id) NOT IN(N'int',N'bigint',N'smallint',N'tinyint',N'bit',
        N'decimal',N'numeric',N'float',N'real',N'money',N'smallmoney'))
    THROW 51012,N'Cần nhập các cột ở kiểu số; không dùng nvarchar.',1;
IF (SELECT COUNT(*) FROM dbo.heart_after)<>299
 OR (SELECT COUNT(DISTINCT MaHoSo) FROM dbo.heart_after)<>299
 OR (SELECT COUNT(*) FROM dbo.heart_after WHERE DEATH_EVENT IS NULL)<>1
 OR EXISTS(SELECT 1 FROM dbo.heart_after WHERE DEATH_EVENT NOT IN(0,1))
    THROW 51013,N'Kiểm tra import: cần 299 khóa khác nhau, 298 nhãn 0/1 và 1 nhãn NULL.',1;

-- BẢNG 1: kiểm tra quy mô sau nhập.
SELECT COUNT(*) AS SoHoSo,
    (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.heart_after')) AS SoCot,
    COUNT(DEATH_EVENT) AS SoNhanHopLe,
    SUM(CASE WHEN DEATH_EVENT IS NULL THEN 1 ELSE 0 END) AS SoNhanChoXacMinh
FROM dbo.heart_after;

-- Chín biến định lượng: bảy biến gốc và hai kết quả làm mịn độc lập.
-- Không tính mean/std cho ID, mã danh mục, thứ tự và mã gộp Boolean.
DROP TABLE IF EXISTS #StatsValues,#StatsQuantiles;
SELECT v.STT,v.TenCot,v.GiaTri
INTO #StatsValues
FROM dbo.heart_after a CROSS APPLY(VALUES
    (1,N'age',a.age),
    (2,N'creatinine_phosphokinase',a.creatinine_phosphokinase),
    (3,N'ejection_fraction',a.ejection_fraction),
    (4,N'platelets',a.platelets),
    (5,N'serum_creatinine',a.serum_creatinine),
    (6,N'serum_sodium',a.serum_sodium),
    (7,N'time',a.time),
    (8,N'platelets_mean_5_nhom',a.platelets_mean_5_nhom),
    (9,N'platelets_dieu_chinh_10pct',a.platelets_dieu_chinh_10pct)
) v(STT,TenCot,GiaTri);

-- Phân vị nội suy tuyến tính, cùng quy ước với Python quantile linear.
SELECT DISTINCT STT,
    PERCENTILE_CONT(0.25) WITHIN GROUP(ORDER BY GiaTri) OVER(PARTITION BY STT) AS Q1,
    PERCENTILE_CONT(0.50) WITHIN GROUP(ORDER BY GiaTri) OVER(PARTITION BY STT) AS Median,
    PERCENTILE_CONT(0.75) WITHIN GROUP(ORDER BY GiaTri) OVER(PARTITION BY STT) AS Q3
INTO #StatsQuantiles FROM #StatsValues;

-- BẢNG 2: thống kê định lượng. Std dùng mẫu (n-1).
-- Nếu nhiều mode: hiển thị mode nhỏ nhất và số lượng mode đồng hạng.
-- Chỉ làm tròn khi hiển thị, không UPDATE dữ liệu after.
;WITH Frequencies AS (
    SELECT STT,GiaTri,COUNT(*) AS TanSuat
    FROM #StatsValues WHERE GiaTri IS NOT NULL GROUP BY STT,GiaTri
), RankedModes AS (
    SELECT *,DENSE_RANK() OVER(PARTITION BY STT ORDER BY TanSuat DESC) AS Hang
    FROM Frequencies
), Modes AS (
    SELECT STT,MIN(GiaTri) AS ModeNhoNhat,COUNT(*) AS SoMode
    FROM RankedModes WHERE Hang=1 GROUP BY STT
)
SELECT s.TenCot,COUNT(s.GiaTri) AS SoHopLe,COUNT(*)-COUNT(s.GiaTri) AS SoThieu,
    CAST(AVG(s.GiaTri) AS decimal(18,2)) AS Mean,
    CAST(m.ModeNhoNhat AS decimal(18,2)) AS ModeNhoNhat,m.SoMode,
    CAST(q.Median AS decimal(18,2)) AS Median_Q2,
    CAST(STDEV(s.GiaTri) AS decimal(18,2)) AS StdMau,
    CAST(MIN(s.GiaTri) AS decimal(18,2)) AS Min,
    CAST(q.Q1 AS decimal(18,2)) AS Q1,
    CAST(q.Q3 AS decimal(18,2)) AS Q3,
    CAST(MAX(s.GiaTri) AS decimal(18,2)) AS Max
FROM #StatsValues s JOIN #StatsQuantiles q ON q.STT=s.STT
LEFT JOIN Modes m ON m.STT=s.STT
GROUP BY s.STT,s.TenCot,m.ModeNhoNhat,m.SoMode,q.Median,q.Q1,q.Q3
ORDER BY s.STT;

-- BẢNG 3: tần suất/mode cho mã nhị phân, nhãn, nhóm tuổi và mã gộp.
-- NULL của nhãn hiển thị riêng, không tham gia chọn mode.
;WITH Codes AS (
    SELECT v.STT,v.TenCot,v.Ma FROM dbo.heart_after a
    CROSS APPLY(VALUES (1,N'anaemia',a.anaemia),(2,N'diabetes',a.diabetes),
        (3,N'high_blood_pressure',a.high_blood_pressure),(4,N'sex',a.sex),
        (5,N'smoking',a.smoking),(6,N'DEATH_EVENT',a.DEATH_EVENT),
        (7,N'MaNhomTuoi',a.MaNhomTuoi),(8,N'MaBoolean',a.MaBoolean)) v(STT,TenCot,Ma)
), Frequencies AS (
    SELECT STT,TenCot,Ma,COUNT(*) AS SoLuong FROM Codes GROUP BY STT,TenCot,Ma
)
SELECT TenCot,COALESCE(CONVERT(nvarchar(20),Ma),N'<NULL>') AS Ma,
    SoLuong,CAST(100.0*SoLuong/SUM(SoLuong) OVER(PARTITION BY STT) AS decimal(6,2)) AS TyLePhanTram,
    CASE WHEN Ma IS NOT NULL AND SoLuong=MAX(CASE WHEN Ma IS NOT NULL THEN SoLuong END)
        OVER(PARTITION BY STT) THEN N'Mode' ELSE N'' END AS GhiChu
FROM Frequencies ORDER BY STT,Ma;
-- Tỷ lệ tính trên toàn bộ 299 hồ sơ, gồm nhãn NULL.
-- Hai ma trận cho ba hồ sơ sẽ thực hiện ở bước tiếp theo.

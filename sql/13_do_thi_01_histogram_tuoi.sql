-- CHƯƠNG 4 - ĐỒ THỊ 01: HISTOGRAM PHÂN BỐ TUỔI.
-- SQL tạo bảng tần suất kiểm chứng; Python vẽ histogram theo cùng các cận.
-- Dùng đủ 299 hồ sơ: biểu đồ tuổi không cần nhãn DEATH_EVENT.
-- Các khoảng 10 năm dùng riêng để vẽ, không thay mã nhóm tuổi A1-A4.
USE HeartFailure_DoAn;
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.heart_after',N'U') IS NULL
    THROW 51000,N'Cần bảng cố định dbo.heart_after.',1;
IF EXISTS(SELECT 1 FROM dbo.heart_after WHERE age IS NULL OR age<40 OR age>=100)
    THROW 51001,N'Cần kiểm tra tuổi; các khoảng đồ thị đang bao phủ [40,100).',1;
IF (SELECT COUNT(*) FROM dbo.heart_after)<>299
    THROW 51002,N'Dự kiến dữ liệu after có 299 hồ sơ.',1;

-- BẢNG 1: quy mô và thống kê dùng để nhận xét đồ thị.
SELECT COUNT(*) AS SoHoSo,
    CAST(MIN(age) AS decimal(18,2)) AS TuoiNhoNhat,
    CAST(MAX(age) AS decimal(18,2)) AS TuoiLonNhat,
    CAST(AVG(CONVERT(float,age)) AS decimal(18,2)) AS TuoiTrungBinh,
    (SELECT TOP(1) CAST(PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY age) OVER() AS decimal(18,2))
     FROM dbo.heart_after) AS TrungVi,
    10 AS DoRongKhoang
FROM dbo.heart_after;

-- BẢNG 2: trái đóng, phải mở. Tuổi 50 vào [50,60), không vào [40,50).
-- Giữ cả khoảng không có hồ sơ để histogram thể hiện đúng độ rộng.
;WITH Khoang AS (
    SELECT * FROM (VALUES(1,40,50),(2,50,60),(3,60,70),
                        (4,70,80),(5,80,90),(6,90,100)) v(STT,CanDuoi,CanTren)
)
SELECT k.STT,k.CanDuoi,k.CanTren,
    CONCAT(N'[',k.CanDuoi,N', ',k.CanTren,N')') AS KhoangTuoi,
    COUNT(a.MaHoSo) AS SoHoSo,
    CAST(100.0*COUNT(a.MaHoSo)/(SELECT COUNT(*) FROM dbo.heart_after) AS decimal(6,2)) AS TyLePhanTram
FROM Khoang k LEFT JOIN dbo.heart_after a ON a.age>=k.CanDuoi AND a.age<k.CanTren
GROUP BY k.STT,k.CanDuoi,k.CanTren ORDER BY k.STT;
-- Trục X: Tuổi (năm); trục Y: Số hồ sơ. Dùng histogram dạng tần số.
-- Dữ liệu đã có tuổi điền bằng median nhóm; đồ thị phản ánh dữ liệu sau xử lý,
-- không xem toàn bộ giá trị tuổi là quan sát nguyên gốc.

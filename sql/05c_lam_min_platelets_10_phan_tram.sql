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

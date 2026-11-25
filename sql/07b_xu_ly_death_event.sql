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

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

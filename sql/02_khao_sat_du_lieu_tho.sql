-- MỤC 3a: KHẢO SÁT DỮ LIỆU THÔ BAN ĐẦU
-- Võ Minh Huy - 2311110117
-- Chỉ đọc dữ liệu, không UPDATE/DELETE/chuẩn hóa giá trị trong bảng raw.
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

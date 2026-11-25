-- Chạy một lần trước 03b_dien_null_sex.sql, trong CÙNG tab SQL.
-- Bảng làm việc riêng cho ví dụ sex, không phải dữ liệu after cuối.
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

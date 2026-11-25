-- Bước chuẩn bị: xác nhận bản before đã được nhập bằng Import Flat File.
-- Chỉ đọc, không sửa dữ liệu.
USE HeartFailure_DoAn;
GO

SELECT
    COUNT(*) AS TongSoDong,
    SUM(CASE WHEN age = N'Invalid_Age' THEN 1 ELSE 0 END) AS SoOInvalidAge
FROM dbo.heart_before_raw;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'dbo' AND TABLE_NAME = N'heart_before_raw'
ORDER BY ORDINAL_POSITION;

SELECT COUNT(*) AS DongTrong
FROM dbo.heart_before_raw
WHERE NULLIF(LTRIM(RTRIM(age)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(anaemia)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(creatinine_phosphokinase)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(diabetes)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(ejection_fraction)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(high_blood_pressure)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(platelets)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(serum_creatinine)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(serum_sodium)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(sex)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(smoking)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(time)), N'') IS NULL
  AND NULLIF(LTRIM(RTRIM(DEATH_EVENT)), N'') IS NULL;

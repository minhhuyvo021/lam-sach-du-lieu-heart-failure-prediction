-- MỤC 3e: chuyển 5 field boolean thành 1 field số nguyên.
-- Chạy trong CÙNG tab có #LabelWork. Chỉ tạo bảng riêng, không sửa nguồn.
-- Thứ tự cố định: anaemia, diabetes, high_blood_pressure, sex, smoking.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
    THROW 51000,N'Cần #LabelWork trong cùng tab kết nối.',1;
IF EXISTS(
    SELECT 1 FROM #LabelWork w
    CROSS APPLY(VALUES(w.anaemia),(w.diabetes),(w.high_blood_pressure),
                      (w.sex),(w.smoking)) v(GiaTri)
    WHERE v.GiaTri IS NULL OR v.GiaTri NOT IN(0,1))
    THROW 51001,N'Cả 5 field phải đủ giá trị 0/1 trước khi mã hóa.',1;
DROP TABLE IF EXISTS #BoolEncoded,#BoolDecoded;

-- Gộp thực sự: bảng này chỉ có khóa và MỘT cột mã thay cho 5 field.
SELECT MaHoSo,CONVERT(int,
    anaemia + 2*diabetes + 4*high_blood_pressure + 8*sex + 16*smoking) AS MaBoolean
INTO #BoolEncoded FROM #LabelWork;

-- Giải mã: lấy bit tương ứng bằng phép chia nguyên và phần dư.
SELECT MaHoSo,MaBoolean,
    MaBoolean % 2 AS anaemia,
    (MaBoolean / 2) % 2 AS diabetes,
    (MaBoolean / 4) % 2 AS high_blood_pressure,
    (MaBoolean / 8) % 2 AS sex,
    (MaBoolean / 16) % 2 AS smoking
INTO #BoolDecoded FROM #BoolEncoded;

-- CHỤP BẢNG 1: quy ước mã hóa và giải mã, phải giữ nguyên thứ tự này.
SELECT ThuTu,ThuocTinh,TrongSo
FROM (VALUES
    (1,N'anaemia',1),(2,N'diabetes',2),(3,N'high_blood_pressure',4),
    (4,N'sex',8),(5,N'smoking',16)
) v(ThuTu,ThuocTinh,TrongSo) ORDER BY ThuTu;

-- CHỤP BẢNG 2: kiểm tra toàn bộ hồ sơ, không chỉ các ví dụ.
SELECT COUNT(*) AS SoHoSo,5 AS SoFieldTruoc,1 AS SoFieldSau,
    MIN(d.MaBoolean) AS MaNhoNhat,MAX(d.MaBoolean) AS MaLonNhat,
    COUNT(DISTINCT d.MaBoolean) AS SoMaXuatHien,
    SUM(CASE WHEN d.anaemia=w.anaemia AND d.diabetes=w.diabetes
        AND d.high_blood_pressure=w.high_blood_pressure AND d.sex=w.sex
        AND d.smoking=w.smoking THEN 0 ELSE 1 END) AS SoHoSoGiaiMaSai
FROM #BoolDecoded d JOIN #LabelWork w ON w.MaHoSo=d.MaHoSo;

-- CHỤP BẢNG 3: chọn 5 mã khác nhau để minh họa các tổ hợp.
;WITH Examples AS (
    SELECT d.*,ROW_NUMBER() OVER(PARTITION BY d.MaBoolean ORDER BY d.MaHoSo) AS rn
    FROM #BoolDecoded d
)
SELECT TOP(5) e.MaHoSo,
    CONVERT(int,w.anaemia) AS anaemia,CONVERT(int,w.diabetes) AS diabetes,
    CONVERT(int,w.high_blood_pressure) AS high_blood_pressure,
    CONVERT(int,w.sex) AS sex,CONVERT(int,w.smoking) AS smoking,e.MaBoolean,
    CONCAT(e.anaemia,N'|',e.diabetes,N'|',e.high_blood_pressure,N'|',e.sex,N'|',e.smoking)
        AS GiaiMaTheoThuTu
FROM Examples e JOIN #LabelWork w ON w.MaHoSo=e.MaHoSo
WHERE e.rn=1 ORDER BY e.MaBoolean;
-- Miền mã có thể có: 0..31, tương ứng 32 tổ hợp; dữ liệu không nhất thiết đủ 32.
-- Mã lớn hơn không có nghĩa bệnh nặng hơn. Không dùng mã gộp như biến liên tục
-- để tính khoảng cách, tương quan hoặc suy ra mức rủi ro; cần giải mã khi phân tích.
-- DEATH_EVENT là nhãn, không gộp vào 5 đặc trưng. #LabelWork giữ nguyên đầy đủ.

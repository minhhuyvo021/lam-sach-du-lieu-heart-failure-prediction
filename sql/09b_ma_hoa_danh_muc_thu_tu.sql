-- MỤC 3e: mã danh mục và thứ tự sang kiểu số nguyên.
-- Chạy trong CÙNG tab có #LabelWork. Chỉ tạo bảng mã riêng.
-- age_group là thuộc tính thứ tự đã phát sinh từ tuổi sau N02, không phải cột gốc.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
    THROW 51000,N'Cần #LabelWork trong cùng tab kết nối.',1;
IF EXISTS(SELECT 1 FROM #LabelWork w
    CROSS APPLY(VALUES(w.anaemia),(w.diabetes),(w.high_blood_pressure),
                      (w.sex),(w.smoking)) v(GiaTri)
    WHERE v.GiaTri IS NULL OR v.GiaTri NOT IN(0,1))
    THROW 51001,N'Năm mã danh mục phải đủ giá trị 0/1.',1;
IF EXISTS(SELECT 1 FROM #LabelWork WHERE DEATH_EVENT NOT IN(0,1))
    THROW 51002,N'Cần xử lý nhãn ngoài miền trước; NULL chờ xác minh được giữ.',1;
IF EXISTS(SELECT 1 FROM #LabelWork WHERE age IS NULL OR age<=0
    OR age_group IS NULL OR age_group NOT IN(N'A1',N'A2',N'A3',N'A4'))
    THROW 51003,N'Cần tuổi và age_group hợp lệ.',1;
DROP TABLE IF EXISTS #CategoryOrdinalWork;

-- Các mã 0/1 giữ nguyên ý nghĩa; chỉ chuyển kiểu lưu trữ thành int.
-- A1<A2<A3<A4 được chuyển thành 1<2<3<4, giữ thứ tự nhóm tuổi.
SELECT MaHoSo,CONVERT(int,anaemia) AS anaemia,
    CONVERT(int,diabetes) AS diabetes,
    CONVERT(int,high_blood_pressure) AS high_blood_pressure,
    CONVERT(int,sex) AS sex,CONVERT(int,smoking) AS smoking,
    CONVERT(int,DEATH_EVENT) AS DEATH_EVENT,
    CASE age_group WHEN N'A1' THEN 1 WHEN N'A2' THEN 2
         WHEN N'A3' THEN 3 WHEN N'A4' THEN 4 END AS MaNhomTuoi
INTO #CategoryOrdinalWork FROM #LabelWork;

-- CHỤP BẢNG 1: bảng quy ước thứ tự và tần suất, tổng vẫn là 299.
SELECT v.NhomTuoi,v.KhoangTuoi,v.MaNhomTuoi,COUNT(w.MaHoSo) AS SoHoSo
FROM (VALUES
    (N'A1',N'Dưới 50',1),(N'A2',N'50 đến dưới 60',2),
    (N'A3',N'60 đến dưới 70',3),(N'A4',N'Từ 70 trở lên',4)
) v(NhomTuoi,KhoangTuoi,MaNhomTuoi)
LEFT JOIN #CategoryOrdinalWork w ON w.MaNhomTuoi=v.MaNhomTuoi
GROUP BY v.NhomTuoi,v.KhoangTuoi,v.MaNhomTuoi ORDER BY v.MaNhomTuoi;

-- CHỤP BẢNG 2: kiểm tra trên TOÀN BỘ hồ sơ, kể cả nhãn thiếu.
SELECT COUNT(*) AS SoHoSo,
    (SELECT COUNT(*) FROM tempdb.sys.columns
     WHERE object_id=OBJECT_ID('tempdb..#CategoryOrdinalWork')
       AND name<>N'MaHoSo' AND TYPE_NAME(system_type_id)=N'int') AS SoCotMaKieuInt,
    COUNT(DISTINCT c.MaNhomTuoi) AS SoNhomTuoi,
    SUM(CASE WHEN c.MaNhomTuoi=CASE WHEN w.age<50 THEN 1 WHEN w.age<60 THEN 2
             WHEN w.age<70 THEN 3 ELSE 4 END THEN 0 ELSE 1 END) AS SoSaiKhoangTuoi,
    SUM(CASE WHEN c.DEATH_EVENT IS NULL THEN 1 ELSE 0 END) AS SoNhanChoXacMinh
FROM #CategoryOrdinalWork c JOIN #LabelWork w ON w.MaHoSo=c.MaHoSo;

-- CHỤP BẢNG 3: một hồ sơ mỗi nhóm tuổi, minh họa chữ -> mã số.
;WITH Examples AS (
    SELECT c.MaHoSo,w.age,w.age_group,c.MaNhomTuoi,
        ROW_NUMBER() OVER(PARTITION BY c.MaNhomTuoi ORDER BY c.MaHoSo) AS rn
    FROM #CategoryOrdinalWork c JOIN #LabelWork w ON w.MaHoSo=c.MaHoSo
)
SELECT MaHoSo,CAST(age AS decimal(18,1)) AS age,
    age_group AS NhomTuoiTruoc,MaNhomTuoi AS MaThuTuSau
FROM Examples WHERE rn=1 ORDER BY MaNhomTuoi;
-- Mã tuổi chỉ biểu thị thứ tự; khoảng cách 1 mã không đồng nghĩa cùng số năm.
-- #CategoryOrdinalWork chứa các field đã mã hóa, không thay thế bảng đầy đủ.
-- DEATH_EVENT NULL vẫn chưa biết nhãn; không biến NULL thành một loại bệnh mới.
-- Không có chuỗi chứa danh sách con nên không tạo ví dụ tách chuỗi giả.

-- Hợp nhất các kết quả đã làm; chạy trong cùng tab có các bảng tạm bên dưới.
-- Không sửa raw. Hai phép làm mịn chạy độc lập từ #EFWork.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
 OR OBJECT_ID('tempdb..#SmoothMeanWork') IS NULL
 OR OBJECT_ID('tempdb..#Smooth10Work') IS NULL
 OR OBJECT_ID('tempdb..#CategoryOrdinalWork') IS NULL
 OR OBJECT_ID('tempdb..#BoolEncoded') IS NULL
    THROW 51000,N'Cần chạy các bước làm sạch, làm mịn và mã hóa trong cùng tab.',1;
DROP TABLE IF EXISTS #HeartAfter;
SELECT w.MaHoSo,w.age,c.anaemia,w.creatinine_phosphokinase,c.diabetes,
    w.ejection_fraction,c.high_blood_pressure,w.platelets,w.serum_creatinine,
    w.serum_sodium,c.sex,c.smoking,w.time,c.DEATH_EVENT,c.MaNhomTuoi,b.MaBoolean,
    m.platelets AS platelets_mean_5_nhom,
    t.platelets AS platelets_dieu_chinh_10pct
INTO #HeartAfter
FROM #LabelWork w
JOIN #CategoryOrdinalWork c ON c.MaHoSo=w.MaHoSo
JOIN #BoolEncoded b ON b.MaHoSo=w.MaHoSo
JOIN #SmoothMeanWork m ON m.MaHoSo=w.MaHoSo
JOIN #Smooth10Work t ON t.MaHoSo=w.MaHoSo;
IF (SELECT COUNT(*) FROM #HeartAfter)<>(SELECT COUNT(*) FROM #LabelWork)
 OR (SELECT COUNT(DISTINCT MaHoSo) FROM #HeartAfter)<>(SELECT COUNT(*) FROM #HeartAfter)
    THROW 51001,N'Ghép bảng làm mất hoặc nhân bản hồ sơ.',1;
IF EXISTS(SELECT 1 FROM #HeartAfter a CROSS APPLY(VALUES
    (a.age),(a.anaemia),(a.creatinine_phosphokinase),(a.diabetes),
    (a.ejection_fraction),(a.high_blood_pressure),(a.platelets),
    (a.serum_creatinine),(a.serum_sodium),(a.sex),(a.smoking),(a.time),
    (a.MaNhomTuoi),(a.MaBoolean),(a.platelets_mean_5_nhom),
    (a.platelets_dieu_chinh_10pct)) v(GiaTri) WHERE v.GiaTri IS NULL)
    THROW 51002,N'Còn thiếu thuộc tính trong bảng after.',1;
-- Chụp bảng này để minh chứng quy mô và các phép làm mịn độc lập.
SELECT COUNT(*) AS SoHoSo,
    (SELECT COUNT(*) FROM tempdb.sys.columns WHERE object_id=OBJECT_ID('tempdb..#HeartAfter')) AS SoCotGomMaHoSo,
    SUM(CASE WHEN DEATH_EVENT IS NULL THEN 1 ELSE 0 END) AS SoNhanChoXacMinh,
    SUM(CASE WHEN platelets<>platelets_mean_5_nhom THEN 1 ELSE 0 END) AS SoThayDoiMean,
    SUM(CASE WHEN platelets<>platelets_dieu_chinh_10pct THEN 1 ELSE 0 END) AS SoThayDoi10Pct
FROM #HeartAfter;
SELECT * FROM #HeartAfter ORDER BY MaHoSo;
-- MaHoSo là khóa nội bộ, không phải số dòng CSV nguồn hay đặc trưng phân tích.
-- Giữ năm biến riêng để diễn giải; MaBoolean là biểu diễn bổ sung có thể giải mã.
-- Chỉ dùng 298 nhãn hợp lệ cho phân tích cần nhãn; các bước không cần nhãn dùng 299.

-- MỤC 3b(ii): chia miền platelets thành 5 khoảng bằng nhau, làm mịn bằng mean.
-- Chạy trong CÙNG tab có #EFWork sau N07. Đầu vào là trước mọi phép làm mịn.
-- Chỉ sửa #SmoothMeanWork; giữ nguyên #EFWork và dữ liệu nguồn.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#EFWork') IS NULL
    THROW 51000,N'Cần bảng #EFWork sau N07 trong cùng tab kết nối.',1;
IF EXISTS(SELECT 1 FROM #EFWork WHERE platelets IS NULL)
    THROW 51001,N'Platelets vẫn còn thiếu; hoàn thành điền trước khi làm mịn.',1;
DROP TABLE IF EXISTS #SmoothMeanWork,#PlateletsBins,#PlateletsGroupMean,#SmoothMeanLog;

DECLARE @SoNhom int=5;
DECLARE @Min decimal(18,6)=(SELECT MIN(platelets) FROM #EFWork);
DECLARE @Max decimal(18,6)=(SELECT MAX(platelets) FROM #EFWork);
IF @Min IS NULL OR @Max<=@Min
    THROW 51002,N'Miền platelets không đủ để chia nhóm.',1;
DECLARE @DoRong decimal(18,6)=(@Max-@Min)/@SoNhom;

SELECT * INTO #SmoothMeanWork FROM #EFWork;
-- Khoảng trái đóng, phải mở; riêng nhóm 5 lấy cả giá trị Max.
SELECT MaHoSo,platelets AS PlateletsTruoc,
    CASE WHEN platelets=@Max THEN @SoNhom
         ELSE 1+CONVERT(int,FLOOR((platelets-@Min)/@DoRong)) END AS Nhom
INTO #PlateletsBins FROM #EFWork;

-- Tính thống kê từ bản TRƯỚC làm mịn, không tính lại sau mỗi cập nhật.
;WITH GroupStats AS (
    SELECT Nhom,COUNT(*) AS SoHoSo,
        CAST(CAST(SUM(PlateletsTruoc) AS decimal(22,6))
             / CAST(COUNT(*) AS decimal(10,0)) AS decimal(28,10)) AS MeanNhom
    FROM #PlateletsBins GROUP BY Nhom
)
SELECT g.Nhom,@Min+(g.Nhom-1)*@DoRong AS CanDuoi,
    @Min+g.Nhom*@DoRong AS CanTren,
    COALESCE(s.SoHoSo,0) AS SoHoSo,s.MeanNhom,
    CAST(ROUND(s.MeanNhom,2) AS decimal(18,2)) AS PlateletsSau
INTO #PlateletsGroupMean
FROM (VALUES(1),(2),(3),(4),(5)) g(Nhom)
LEFT JOIN GroupStats s ON s.Nhom=g.Nhom;

UPDATE w SET platelets=g.PlateletsSau
FROM #SmoothMeanWork w JOIN #PlateletsBins b ON b.MaHoSo=w.MaHoSo
JOIN #PlateletsGroupMean g ON g.Nhom=b.Nhom
WHERE g.SoHoSo>0;

SELECT b.MaHoSo,b.Nhom,b.PlateletsTruoc,g.MeanNhom,w.platelets AS PlateletsSau
INTO #SmoothMeanLog
FROM #PlateletsBins b JOIN #PlateletsGroupMean g ON g.Nhom=b.Nhom
JOIN #SmoothMeanWork w ON w.MaHoSo=b.MaHoSo;

-- CHỤP BẢNG 1: tổng kết phép làm mịn.
SELECT COUNT(*) AS SoHoSo,@SoNhom AS SoNhom,
    CAST(@DoRong AS decimal(18,2)) AS DoRongNhom,
    COUNT(PlateletsSau) AS SoHoSoDaLamMin,
    SUM(CASE WHEN PlateletsTruoc<>PlateletsSau THEN 1 ELSE 0 END) AS SoGiaTriThayDoi
FROM #SmoothMeanLog;

-- CHỤP BẢNG 2: 5 khoảng, số hồ sơ, mean nhóm và giá trị thay thế.
SELECT Nhom,CAST(CanDuoi AS decimal(18,2)) AS CanDuoi,
    CAST(CanTren AS decimal(18,2)) AS CanTren,
    SoHoSo,MeanNhom,PlateletsSau
FROM #PlateletsGroupMean ORDER BY Nhom;

-- CHỤP BẢNG 3: hai ví dụ mỗi nhóm, tổng 10 trường hợp trước/sau.
;WITH Examples AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY Nhom ORDER BY PlateletsTruoc,MaHoSo) AS rn
    FROM #SmoothMeanLog
)
SELECT MaHoSo,Nhom,PlateletsTruoc,MeanNhom,
    CAST(PlateletsSau AS decimal(18,2)) AS PlateletsSau
FROM Examples WHERE rn<=2 ORDER BY Nhom,PlateletsTruoc,MaHoSo;
-- Nhật ký đủ 299 hồ sơ ở #SmoothMeanLog.
-- Tăng/giảm 10% cho các giá trị cực trị là bước riêng tiếp theo.

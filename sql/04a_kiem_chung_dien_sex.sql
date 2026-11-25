-- KIỂM CHỨNG N01: che 20% sex quan sát, seed 42, so hai cách dự đoán.
-- Chạy trong CÙNG tab có #SexDonors từ bước 03a.
-- Chỉ tạo bảng tạm kiểm chứng; không sửa raw hoặc kết quả N01-N07.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#SexDonors') IS NULL
    THROW 51000,N'Chạy bước 03a trong tab này trước để có mẫu quan sát gốc.',1;
DROP TABLE IF EXISTS #CvSexObserved,#CvSexMask,#CvSexDonors,#CvSexLog;

-- Mã TỰ TÍNH từ 13 giá trị chuẩn hóa, để SQL/Python chọn cùng hồ sơ.
-- Không có danh sách mã ghi sẵn. MaHoSo không dùng để chọn mẫu.
SELECT d.*,CONVERT(char(64),HASHBYTES('SHA2_256',CONCAT(
    CONVERT(nvarchar(max),N'age='),COALESCE(CONVERT(nvarchar(40),age),N'~'),
    N'|anaemia=',COALESCE(CONVERT(nvarchar(40),anaemia),N'~'),
    N'|creatinine_phosphokinase=',COALESCE(CONVERT(nvarchar(40),creatinine_phosphokinase),N'~'),
    N'|diabetes=',COALESCE(CONVERT(nvarchar(40),diabetes),N'~'),
    N'|ejection_fraction=',COALESCE(CONVERT(nvarchar(40),ejection_fraction),N'~'),
    N'|high_blood_pressure=',COALESCE(CONVERT(nvarchar(40),high_blood_pressure),N'~'),
    N'|platelets=',COALESCE(CONVERT(nvarchar(40),platelets),N'~'),
    N'|serum_creatinine=',COALESCE(CONVERT(nvarchar(40),serum_creatinine),N'~'),
    N'|serum_sodium=',COALESCE(CONVERT(nvarchar(40),serum_sodium),N'~'),
    N'|sex=',COALESCE(CONVERT(nvarchar(40),sex),N'~'),
    N'|smoking=',COALESCE(CONVERT(nvarchar(40),smoking),N'~'),
    N'|time=',COALESCE(CONVERT(nvarchar(40),time),N'~'),
    N'|DEATH_EVENT=',COALESCE(CONVERT(nvarchar(40),DEATH_EVENT),N'~'))),2) AS record_key
INTO #CvSexObserved FROM #SexDonors d WHERE sex IN(0,1);

DECLARE @SoMauChe int=(SELECT (COUNT(*)+4)/5 FROM #CvSexObserved);
SELECT TOP (@SoMauChe) * INTO #CvSexMask FROM #CvSexObserved
ORDER BY CONVERT(char(64),HASHBYTES('SHA2_256',N'42|N01|'+record_key),2),record_key;
SELECT o.* INTO #CvSexDonors FROM #CvSexObserved o
WHERE NOT EXISTS(SELECT 1 FROM #CvSexMask m WHERE m.record_key=o.record_key);
IF (SELECT COUNT(*) FROM #CvSexDonors)<5
    THROW 51001,N'Không đủ 5 mẫu cho sau khi che; dừng kiểm chứng.',1;

-- Chỉ phần CHƯA che được dùng tính mode nhóm và mode nền toàn cột.
DECLARE @ModeToanCot decimal(18,6);
SELECT TOP(1) @ModeToanCot=sex FROM #CvSexDonors
GROUP BY sex ORDER BY COUNT(*) DESC,sex;

;WITH Frequencies AS (
    SELECT r.record_key,level.CapNhom,d.sex,COUNT(*) AS TanSuat
    FROM #CvSexMask r CROSS JOIN (VALUES(1),(2),(3),(4)) level(CapNhom)
    JOIN #CvSexDonors d ON
        (level.CapNhom=1 AND d.anaemia=r.anaemia AND d.diabetes=r.diabetes
            AND d.smoking=r.smoking AND d.high_blood_pressure=r.high_blood_pressure)
        OR (level.CapNhom=2 AND d.anaemia=r.anaemia AND d.diabetes=r.diabetes)
        OR (level.CapNhom=3 AND d.diabetes=r.diabetes) OR level.CapNhom=4
    GROUP BY r.record_key,level.CapNhom,d.sex
), GroupSizes AS (
    SELECT *,SUM(TanSuat) OVER(PARTITION BY record_key,CapNhom) AS SoMauCho
    FROM Frequencies
), Preferred AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY record_key
        ORDER BY CapNhom,TanSuat DESC,sex) AS uu_tien
    FROM GroupSizes WHERE SoMauCho>=5
)
SELECT r.record_key,r.MaHoSo,r.sex AS SexThuc,r.anaemia,r.diabetes,
    r.smoking,r.high_blood_pressure,p.CapNhom,p.SoMauCho,
    p.sex AS DuDoanTheoNhom,@ModeToanCot AS DuDoanToanCot
INTO #CvSexLog FROM #CvSexMask r
LEFT JOIN Preferred p ON p.record_key=r.record_key AND p.uu_tien=1;

-- CHỤP BẢNG 1: quy mô chia mẫu kiểm chứng.
SELECT (SELECT COUNT(*) FROM #CvSexObserved) AS SexQuanSatHopLe,
    (SELECT COUNT(*) FROM #CvSexMask) AS SoMauBiChe,
    (SELECT COUNT(*) FROM #CvSexDonors) AS SoMauChoConLai,42 AS Seed;

-- CHỤP BẢNG 2: Accuracy = số đúng / số mẫu bị che * 100%.
SELECT N'Mode theo nhóm' AS PhuongPhap,COUNT(*) AS SoMauCanDuDoan,
    COUNT(DuDoanTheoNhom) AS SoMauDuDoanDuoc,
    SUM(CASE WHEN DuDoanTheoNhom=SexThuc THEN 1 ELSE 0 END) AS SoDung,
    CASE WHEN COUNT(DuDoanTheoNhom)=COUNT(*) THEN
        CAST(100.0*SUM(CASE WHEN DuDoanTheoNhom=SexThuc THEN 1 ELSE 0 END)
             / COUNT(*) AS decimal(6,2)) END AS AccuracyPhanTram
FROM #CvSexLog
UNION ALL
SELECT N'Mode toàn cột',COUNT(*),COUNT(DuDoanToanCot),
    SUM(CASE WHEN DuDoanToanCot=SexThuc THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN DuDoanToanCot=SexThuc THEN 1 ELSE 0 END)
         / COUNT(*) AS decimal(6,2))
FROM #CvSexLog;

-- CHỤP BẢNG 3: mười ví dụ; giá trị thật chỉ dùng chấm kết quả.
SELECT TOP(10) MaHoSo,SexThuc,CapNhom,SoMauCho,DuDoanTheoNhom,DuDoanToanCot
FROM #CvSexLog ORDER BY MaHoSo;
-- Nhật ký đủ 56 mẫu và khóa đối chiếu vẫn được giữ tại #CvSexLog.

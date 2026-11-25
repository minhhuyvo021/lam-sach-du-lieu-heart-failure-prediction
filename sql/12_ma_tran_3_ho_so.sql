-- MỤC 3f: ma trận tương quan và ma trận khác biệt cho đúng 3 RECORDS.
-- Đọc bảng cố định dbo.heart_after; không cập nhật after hoặc dữ liệu nguồn.
-- Sáu thuộc tính: age, CPK, EF, platelets, serum_creatinine, serum_sodium.
-- Dùng platelets đã làm sạch; không thêm hai nhánh làm mịn để tránh lặp trọng số.
-- Không dùng ID, nhãn, mã danh mục, nhóm tuổi hoặc mã Boolean làm tọa độ.
USE HeartFailure_DoAn;
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.heart_after',N'U') IS NULL
    THROW 51000,N'Cần import CSV after vào dbo.heart_after trước.',1;
IF (SELECT COUNT(*) FROM dbo.heart_after)<3
 OR EXISTS(SELECT 1 FROM dbo.heart_after WHERE age IS NULL
    OR creatinine_phosphokinase IS NULL OR ejection_fraction IS NULL
    OR platelets IS NULL OR serum_creatinine IS NULL OR serum_sodium IS NULL)
    THROW 51001,N'Cần ít nhất 3 hồ sơ và đủ giá trị ở sáu thuộc tính.',1;
IF (SELECT COUNT(DISTINCT MaHoSo) FROM dbo.heart_after)<>(SELECT COUNT(*) FROM dbo.heart_after)
    THROW 51002,N'MaHoSo phải duy nhất trong bảng after.',1;
DROP TABLE IF EXISTS #MatrixValues,#MatrixScale,#MatrixThree,#MatrixZ,#MatrixPairs;

-- Tính mean và độ lệch chuẩn MẪU từ toàn bộ 299 hồ sơ, không chỉ từ 3 hồ sơ.
SELECT a.MaHoSo,v.ThuTu,v.ThuocTinh,CONVERT(float,v.GiaTri) AS GiaTri
INTO #MatrixValues
FROM dbo.heart_after a CROSS APPLY(VALUES
    (1,N'age',a.age),(2,N'creatinine_phosphokinase',a.creatinine_phosphokinase),
    (3,N'ejection_fraction',a.ejection_fraction),(4,N'platelets',a.platelets),
    (5,N'serum_creatinine',a.serum_creatinine),(6,N'serum_sodium',a.serum_sodium)
) v(ThuTu,ThuocTinh,GiaTri);
SELECT ThuTu,ThuocTinh,COUNT(*) AS SoMau,AVG(GiaTri) AS Mean,STDEV(GiaTri) AS StdMau
INTO #MatrixScale FROM #MatrixValues GROUP BY ThuTu,ThuocTinh;
IF EXISTS(SELECT 1 FROM #MatrixScale WHERE StdMau IS NULL OR StdMau<=0)
    THROW 51003,N'Không chuẩn hóa Z-score được thuộc tính có std bằng 0.',1;

-- Chọn 3 hồ sơ theo thứ tự giá trị để Python có thể chọn tương ứng dù ID khác.
-- A, B, C là nhãn minh họa trong ma trận, không phải nhãn bệnh.
;WITH Chosen AS (
    SELECT TOP(3) MaHoSo,age,creatinine_phosphokinase,ejection_fraction,
        platelets,serum_creatinine,serum_sodium
    FROM dbo.heart_after ORDER BY age,creatinine_phosphokinase,ejection_fraction,
        platelets,serum_creatinine,serum_sodium,MaHoSo
)
SELECT ROW_NUMBER() OVER(ORDER BY age,creatinine_phosphokinase,ejection_fraction,
    platelets,serum_creatinine,serum_sodium,MaHoSo) AS STT,*
INTO #MatrixThree FROM Chosen;

-- Z_ik = (x_ik - mean_k) / std_k; giữ nguyên độ chính xác khi tính.
SELECT t.STT,v.ThuTu,(v.GiaTri-s.Mean)/s.StdMau AS Z
INTO #MatrixZ FROM #MatrixThree t JOIN #MatrixValues v ON v.MaHoSo=t.MaHoSo
JOIN #MatrixScale s ON s.ThuTu=v.ThuTu;

-- Pearson GIỮA HAI HỒ SƠ, mỗi hồ sơ là vector 6 giá trị Z theo cùng thứ tự.
-- r_ij = SUM((Z_ik-mean_i)*(Z_jk-mean_j)) / SQRT(SS_i*SS_j).
-- Khác biệt: khoảng cách Euclidean d_ij = SQRT(SUM((Z_ik-Z_jk)^2)).
-- Đây là tương quan hình dạng hồ sơ chuẩn hóa, không phải tương quan giữa
-- các thuộc tính trên 299 bệnh nhân, không dùng để suy luận nhân quả/nguy cơ.
;WITH Sums AS (
    SELECT a.STT AS Dong,b.STT AS Cot,COUNT(*) AS N,
        SUM(a.Z) AS SumA,SUM(b.Z) AS SumB,
        SUM(a.Z*a.Z) AS SumAA,SUM(b.Z*b.Z) AS SumBB,
        SUM(a.Z*b.Z) AS SumAB,SUM(POWER(a.Z-b.Z,2)) AS KhoangCachBinhPhuong
    FROM #MatrixZ a JOIN #MatrixZ b ON b.ThuTu=a.ThuTu GROUP BY a.STT,b.STT
), Centered AS (
    SELECT *,SumAA-SumA*SumA/N AS SSA,SumBB-SumB*SumB/N AS SSB,
        SumAB-SumA*SumB/N AS TichCheo FROM Sums
)
SELECT Dong,Cot,
    CASE WHEN SSA>1e-12 AND SSB>1e-12 THEN TichCheo/SQRT(SSA*SSB) END AS Pearson,
    SQRT(KhoangCachBinhPhuong) AS Euclidean
INTO #MatrixPairs FROM Centered;
IF EXISTS(SELECT 1 FROM #MatrixPairs WHERE Pearson IS NULL)
    THROW 51004,N'Có vector hồ sơ gần như hằng; không tính được Pearson.',1;

-- BẢNG 1: ba hồ sơ được chọn, trước chuẩn hóa.
SELECT CHAR(64+CONVERT(int,STT)) AS HoSo,MaHoSo,
    CAST(age AS decimal(18,2)) AS age,
    CAST(creatinine_phosphokinase AS decimal(18,2)) AS CPK,
    CAST(ejection_fraction AS decimal(18,2)) AS EF,
    CAST(platelets AS decimal(18,2)) AS platelets,
    CAST(serum_creatinine AS decimal(18,2)) AS creatinine,
    CAST(serum_sodium AS decimal(18,2)) AS sodium
FROM #MatrixThree ORDER BY STT;

-- BẢNG 2: tham số chuẩn hóa từ toàn bộ bảng after.
SELECT ThuocTinh,SoMau,CAST(Mean AS decimal(18,6)) AS Mean,
    CAST(StdMau AS decimal(18,6)) AS StdMau
FROM #MatrixScale ORDER BY ThuTu;

-- BẢNG 3: ba vector Z-score, chỉ làm tròn 6 số khi hiển thị.
SELECT CHAR(64+CONVERT(int,STT)) AS HoSo,
    CAST(MAX(CASE WHEN ThuTu=1 THEN Z END) AS decimal(18,6)) AS age,
    CAST(MAX(CASE WHEN ThuTu=2 THEN Z END) AS decimal(18,6)) AS CPK,
    CAST(MAX(CASE WHEN ThuTu=3 THEN Z END) AS decimal(18,6)) AS EF,
    CAST(MAX(CASE WHEN ThuTu=4 THEN Z END) AS decimal(18,6)) AS platelets,
    CAST(MAX(CASE WHEN ThuTu=5 THEN Z END) AS decimal(18,6)) AS creatinine,
    CAST(MAX(CASE WHEN ThuTu=6 THEN Z END) AS decimal(18,6)) AS sodium
FROM #MatrixZ GROUP BY STT ORDER BY STT;

-- BẢNG 4: ma trận tương quan Pearson 3 x 3; đường chéo bằng 1.
SELECT CHAR(64+CONVERT(int,Dong)) AS HoSo,
    CAST(MAX(CASE WHEN Cot=1 THEN Pearson END) AS decimal(18,6)) AS A,
    CAST(MAX(CASE WHEN Cot=2 THEN Pearson END) AS decimal(18,6)) AS B,
    CAST(MAX(CASE WHEN Cot=3 THEN Pearson END) AS decimal(18,6)) AS C
FROM #MatrixPairs GROUP BY Dong ORDER BY Dong;

-- BẢNG 5: ma trận khác biệt Euclidean 3 x 3; đường chéo bằng 0.
-- Khoảng cách càng nhỏ, hai hồ sơ càng gần nhau trên sáu chỉ số đã chuẩn hóa.
SELECT CHAR(64+CONVERT(int,Dong)) AS HoSo,
    CAST(MAX(CASE WHEN Cot=1 THEN Euclidean END) AS decimal(18,6)) AS A,
    CAST(MAX(CASE WHEN Cot=2 THEN Euclidean END) AS decimal(18,6)) AS B,
    CAST(MAX(CASE WHEN Cot=3 THEN Euclidean END) AS decimal(18,6)) AS C
FROM #MatrixPairs GROUP BY Dong ORDER BY Dong;

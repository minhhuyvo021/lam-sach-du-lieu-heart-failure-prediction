-- MỤC 3d: trường hợp 1, giảm số chiều theo mục tiêu thống kê định lượng.
-- Chạy trong CÙNG tab có #LabelWork sau xử lý nhãn.
-- Tạo bảng con; không thay thế dữ liệu chính hoặc kết luận các biến khác vô ích.
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#LabelWork') IS NULL
    THROW 51000,N'Cần #LabelWork; chạy 07b_xu_ly_death_event.sql trong tab này trước.',1;
DROP TABLE IF EXISTS #ReducedClinical6;

-- Giữ 6 biến: tuổi, CPK, EF, tiểu cầu, creatinine và natri.
-- Không đưa 5 mã danh mục và thời gian theo dõi vào bảng chỉ số định lượng này.
-- Nhãn DEATH_EVENT giữ ở #LabelWork, không tính là thuộc tính đầu vào.
-- MaHoSo chỉ là khóa liên kết, không tính vào 6 chiều.
SELECT MaHoSo,age,creatinine_phosphokinase,ejection_fraction,
    platelets,serum_creatinine,serum_sodium
INTO #ReducedClinical6 FROM #LabelWork;

-- CHỤP BẢNG 1: quy mô trước/sau, so 12 đầu vào với 6 thuộc tính giữ lại.
DECLARE @SoCotGoc int=(
    SELECT COUNT(*) FROM tempdb.sys.columns
    WHERE object_id=OBJECT_ID('tempdb..#LabelWork')
      AND name NOT IN(N'MaHoSo',N'age_group'));
DECLARE @SoCotSau int=(
    SELECT COUNT(*) FROM tempdb.sys.columns
    WHERE object_id=OBJECT_ID('tempdb..#ReducedClinical6') AND name<>N'MaHoSo');
SELECT (SELECT COUNT(*) FROM #LabelWork) AS SoHoSoTruoc,
    (SELECT COUNT(*) FROM #ReducedClinical6) AS SoHoSoSau,
    @SoCotGoc AS SoCotGocGomNhan,
    @SoCotGoc-1 AS SoThuocTinhDauVao,
    @SoCotSau AS SoThuocTinhGiuLai,
    CAST(100.0*(@SoCotGoc-1-@SoCotSau)/NULLIF(@SoCotGoc-1,0)
         AS decimal(6,2)) AS TyLeGiamPhanTram;

-- CHỤP BẢNG 2: danh sách 6 chiều thực tế của bảng kết quả.
SELECT ROW_NUMBER() OVER(ORDER BY column_id) AS STT,name AS ThuocTinhGiuLai
FROM tempdb.sys.columns
WHERE object_id=OBJECT_ID('tempdb..#ReducedClinical6') AND name<>N'MaHoSo'
ORDER BY column_id;

-- CHỤP BẢNG 3: năm hồ sơ minh họa, giá trị giữ nguyên từ #LabelWork.
SELECT TOP(5) MaHoSo,
    CAST(age AS decimal(18,1)) AS age,
    CAST(creatinine_phosphokinase AS decimal(18,0)) AS CPK,
    CAST(ejection_fraction AS decimal(18,0)) AS EF,
    CAST(platelets AS decimal(18,2)) AS platelets,
    CAST(serum_creatinine AS decimal(18,2)) AS serum_creatinine,
    CAST(serum_sodium AS decimal(18,0)) AS serum_sodium
FROM #ReducedClinical6 ORDER BY MaHoSo;
-- Chỉ định dạng bảng minh họa; dữ liệu trong #ReducedClinical6 không làm tròn lại.
-- Bảng con phục vụ thống kê 6 biến; không dùng thay tập đầy đủ khi cần giới tính,
-- tiền sử, hút thuốc, thời gian hoặc nhãn kết quả. Có thể nối lại bằng MaHoSo.
-- Trường hợp 2 (tổng hợp nhóm để giảm số dòng) sẽ thực hiện riêng.

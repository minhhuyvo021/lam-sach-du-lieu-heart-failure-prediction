          -- N04: điền platelets bằng mean, nối tiếp N03 CPK.
          -- Chạy trong CÙNG tab đã chạy 03a, 03b, 03c, 03d.
          -- Cấp 1: sex,anaemia -> cấp 2: sex -> cấp 3: toàn cột.
          -- Nhóm cần ít nhất 5 mẫu; chỉ giá trị mới điền được làm tròn 2 chữ số.
          SET NOCOUNT ON;
          IF OBJECT_ID('tempdb..#CPKWork') IS NULL
           OR OBJECT_ID('tempdb..#SexWork') IS NULL
           OR OBJECT_ID('tempdb..#SexDonors') IS NULL
              THROW 51000, N'Chạy các bước chuẩn bị, sex, age và CPK trong tab này trước.', 1;
          IF EXISTS(SELECT 1 FROM #CPKWork WHERE creatinine_phosphokinase IS NULL OR sex IS NULL)
              THROW 51001, N'Kiểm tra các bước trước: vẫn còn CPK hoặc sex thiếu.', 1;
          DROP TABLE IF EXISTS #PlateletsWork,#PlateletsDonors,#PlateletsTargets,#PlateletsLog;

          SELECT * INTO #PlateletsWork FROM #CPKWork;
          SELECT MaHoSo,platelets AS PlateletsTruoc,sex,anaemia
          INTO #PlateletsTargets FROM #PlateletsWork WHERE platelets IS NULL;

          -- Cố định mẫu cho từ platelets và sex QUAN SÁT trước mọi bước điền.
          -- Hồ sơ thiếu sex quan sát vẫn cho platelets ở cấp toàn cột.
          SELECT w.platelets,original.sex,w.anaemia
          INTO #PlateletsDonors FROM #SexWork w
          LEFT JOIN #SexDonors original ON original.MaHoSo=w.MaHoSo
          WHERE w.platelets IS NOT NULL;

          -- Mean = tổng platelets / số mẫu. Giữ 10 số lẻ trước làm tròn cuối.
          ;WITH Means AS (
              SELECT r.MaHoSo,level.CapNhom,COUNT(*) AS SoMauCho,
                  CAST(CAST(SUM(d.platelets) AS decimal(22,6))
                       / CAST(COUNT(*) AS decimal(10,0)) AS decimal(28,10)) AS MeanNhom
              FROM #PlateletsTargets r CROSS JOIN (VALUES(1),(2),(3)) level(CapNhom)
              JOIN #PlateletsDonors d ON
                  (level.CapNhom=1 AND d.sex=r.sex AND d.anaemia=r.anaemia)
                  OR (level.CapNhom=2 AND d.sex=r.sex) OR level.CapNhom=3
              GROUP BY r.MaHoSo,level.CapNhom HAVING COUNT(*)>=5
          ), Preferred AS (
              SELECT *,ROW_NUMBER() OVER(PARTITION BY MaHoSo ORDER BY CapNhom) AS uu_tien
              FROM Means
          )
          SELECT r.*,p.CapNhom,p.SoMauCho,p.MeanNhom,
              CAST(ROUND(p.MeanNhom,2) AS decimal(18,2)) AS PlateletsDien
          INTO #PlateletsLog FROM #PlateletsTargets r
          LEFT JOIN Preferred p ON p.MaHoSo=r.MaHoSo AND p.uu_tien=1;

          UPDATE w SET platelets=l.PlateletsDien
          FROM #PlateletsWork w JOIN #PlateletsLog l ON l.MaHoSo=w.MaHoSo
          WHERE w.platelets IS NULL AND l.PlateletsDien IS NOT NULL;

          -- CHỤP BẢNG 1: tổng kết số ô trước/sau điền.
          SELECT (SELECT COUNT(*) FROM #PlateletsWork) AS SoHoSo,
              COUNT(*) AS SoPlateletsThieuTruocDien,COUNT(PlateletsDien) AS SoODaDien,
              (SELECT COUNT(*) FROM #PlateletsWork WHERE platelets IS NULL) AS SoPlateletsThieuSauDien
          FROM #PlateletsLog;

          -- CHỤP BẢNG 2: khóa nhóm, cấp nhóm, số mẫu cho, mean và giá trị điền.
          SELECT * FROM #PlateletsLog ORDER BY MaHoSo;
          -- Bản làm việc nối tiếp là #PlateletsWork; chưa phải bảng after cuối.

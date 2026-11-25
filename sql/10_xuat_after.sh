#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/VoMinhHuy_Heart Failure Prediction_after_SQL.csv"
SA_PASS="${MSSQL_SA_PASSWORD:-MatKhau@12345}"

SQLCMD_BIN=$(docker exec sql_doan sh -c '
  if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then
    echo /opt/mssql-tools18/bin/sqlcmd
  else
    echo /opt/mssql-tools/bin/sqlcmd
  fi
')

QUERY="SET NOCOUNT ON;
SELECT
  CAST(MaHoSo AS INT) AS MaHoSo,
  CAST(age AS DECIMAL(18,6)) AS age,
  CAST(anaemia AS INT) AS anaemia,
  CAST(creatinine_phosphokinase AS DECIMAL(18,6)) AS creatinine_phosphokinase,
  CAST(diabetes AS INT) AS diabetes,
  CAST(ejection_fraction AS DECIMAL(18,6)) AS ejection_fraction,
  CAST(high_blood_pressure AS INT) AS high_blood_pressure,
  CAST(platelets AS DECIMAL(18,6)) AS platelets,
  CAST(serum_creatinine AS DECIMAL(18,6)) AS serum_creatinine,
  CAST(serum_sodium AS DECIMAL(18,6)) AS serum_sodium,
  CAST(sex AS INT) AS sex,
  CAST(smoking AS INT) AS smoking,
  CAST([time] AS DECIMAL(18,6)) AS [time],
  CAST(DEATH_EVENT AS INT) AS DEATH_EVENT,
  CAST(MaNhomTuoi AS INT) AS MaNhomTuoi,
  CAST(MaBoolean AS INT) AS MaBoolean,
  CAST(platelets_mean_5_nhom AS DECIMAL(18,2)) AS platelets_mean_5_nhom,
  CAST(platelets_dieu_chinh_10pct AS DECIMAL(18,6)) AS platelets_dieu_chinh_10pct
FROM dbo.heart_after
ORDER BY CAST(MaHoSo AS INT);"

docker exec sql_doan "$SQLCMD_BIN" \
  -S localhost -U sa -P "$SA_PASS" -d HeartFailure_DoAn -C \
  -s"," -W \
  -Q "$QUERY" \
  | awk -F, -v OFS=, 'NR!=2 && NF>0 {for(i=1;i<=NF;i++) if($i=="NULL") $i=""; print}' \
  > "$OUTPUT_FILE"

echo "Da xuat xong: $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE" | tr -d ' ') dong)"

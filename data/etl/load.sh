#!/usr/bin/env bash
# data/etl/load.sh — load the downloaded datasets into PostGIS, clipped to the pilot regions
# What: runs data/schema.sql, loads CAOP nationally, derives the pilot-region clip polygon from
#       data/regioes.json, loads the other layers clipped to it, fills open.dataset_meta, builds indexes.
# Depends on: GDAL/OGR (ogr2ogr ≥ 3.6), psql, jq; env PG_DSN (e.g. "postgresql://territorio_rw@10.8.0.1:5434/territorio",
#       password via PGPASSWORD or ~/.pgpass — never on the command line); files from download.sh.
# Used by: one-off data preparation (pre-existing component, declared in PRE-EXISTING.md).
# When changing: table/column names are read by open.facts_at() in schema.sql and by data/views.sql.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; RAW="$ROOT/data/raw"
: "${PG_DSN:?set PG_DSN=postgresql://user@host:port/db (password via PGPASSWORD/.pgpass)}"
OGR_PG="PG:$PG_DSN"

echo "== schema"; psql "$PG_DSN" -v ON_ERROR_STOP=1 -f "$ROOT/data/schema.sql"

echo "== CAOP 2025 (national)"
# Layer names inside the GPKG are confirmed at first run: ogrinfo caop2025_continente.gpkg
CAOP_GPKG=$(unzip -Z1 "$RAW/caop2025_continente_gpkg.zip" | grep -i "\.gpkg$" | head -1)
unzip -o -q "$RAW/caop2025_continente_gpkg.zip" "$CAOP_GPKG" -d "$RAW"
ogrinfo -ro -so "$RAW/$CAOP_GPKG" | sed -n "1,20p"   # layer names — pick the freguesias layer below
CAOP_LAYER=${CAOP_LAYER:-$(ogrinfo -ro -so "$RAW/$CAOP_GPKG" | grep -ioE "[a-z_]*freguesia[a-z_]*" | head -1)}
ogr2ogr -f PostgreSQL "$OGR_PG" "$RAW/$CAOP_GPKG" "$CAOP_LAYER" -nln open.caop_freguesias \
  -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -overwrite \
  --config PG_USE_COPY YES
# TODO after first run: rename columns to (dico, freguesia, concelho, distrito) if the source differs.

echo "== pilot-region clip polygon from CAOP + data/regioes.json"
MUNS=$(jq -r '.regions[].municipalities[]' "$ROOT/data/regioes.json" | sed "s/'/''/g" | awk '{printf "%s'\''%s'\''", (NR>1?",":""), $0}')
psql "$PG_DSN" -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS open.pilot_regions;
CREATE TABLE open.pilot_regions AS
  SELECT concelho, ST_Union(geom)::geometry(MultiPolygon, 3763) AS geom
  FROM open.caop_freguesias WHERE concelho IN ($MUNS) GROUP BY concelho;
CREATE INDEX ON open.pilot_regions USING GIST (geom);
SELECT count(*) AS municipalities_found FROM open.pilot_regions;
SQL
# Export the clip as a file for ogr2ogr -clipsrc
ogr2ogr -f GPKG "$RAW/pilot_clip.gpkg" "$OGR_PG" -sql "SELECT ST_Union(geom) AS geom FROM open.pilot_regions" -nln clip

load_clipped() { # id  source  target_table  [extra ogr args]
  local id="$1" src="$2" tbl="$3"; shift 3
  echo "== $id → open.$tbl (clipped)"
  ogr2ogr -f PostgreSQL "$OGR_PG" "$src" -nln "open.$tbl" -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 \
    -clipsrc "$RAW/pilot_clip.gpkg" -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -overwrite \
    --config PG_USE_COPY YES "$@"
}
[ -f "$RAW/cos2023.zip" ]            && load_clipped cos2023 "/vsizip/$RAW/cos2023.zip" cos2023

echo "== ICNF fire hazard via WFS (6 feature types, one per class; bbox of pilot regions, EPSG:3763)"
BBOX3763=$(psql "$PG_DSN" -tAc "SELECT ST_XMin(e)||','||ST_YMin(e)||','||ST_XMax(e)||','||ST_YMax(e) FROM (SELECT ST_Extent(geom) e FROM open.pilot_regions) s")
IFS=',' read -r X1 Y1 X2 Y2 <<< "$BBOX3763"
WFS="WFS:https://servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1/WFService.aspx?service=WFS&VERSION=2.0.0"
# Feature types confirmed 2026-09-26 with ogrinfo: gmgml:Classe_de_Perigosidade_{Nula,Muito_Baixa,Baixa,Média,Alta,Muito_Alta}
first=1
for cls in Nula Muito_Baixa Baixa Média Alta Muito_Alta; do
  if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
  ogr2ogr -f PostgreSQL "$OGR_PG" "$WFS" "gmgml:Classe_de_Perigosidade_$cls" -spat "$X1" "$Y1" "$X2" "$Y2" \
    -nln open.icnf_perigosidade_raw -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 -clipsrc "$RAW/pilot_clip.gpkg" \
    -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST $mode \
    -sql "SELECT *, '$cls' AS classe_src FROM \"gmgml:Classe_de_Perigosidade_$cls\"" -dialect OGRSQL \
    --config OGR_WFS_PAGING_ALLOWED ON --config OGR_WFS_PAGE_SIZE 1000 \
    || echo "WARN: WFS class $cls failed (retry later; service may throttle)"
done
psql "$PG_DSN" -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE IF EXISTS open.icnf_perigosidade;
CREATE TABLE open.icnf_perigosidade AS
  SELECT replace(lower(classe_src), '_', ' ') AS classe,
         CASE classe_src WHEN 'Nula' THEN 0 WHEN 'Muito_Baixa' THEN 1 WHEN 'Baixa' THEN 2 WHEN 'Média' THEN 3 WHEN 'Alta' THEN 4 WHEN 'Muito_Alta' THEN 5 END AS classe_ord,
         geom
  FROM open.icnf_perigosidade_raw;
CREATE INDEX ON open.icnf_perigosidade USING GIST (geom);
DROP TABLE open.icnf_perigosidade_raw;
SQL

echo "== INE BGRI 2021 (per-municipality GeoPackages)"
first=1
for z in "$RAW"/bgri2021/BGRI2021_*.zip; do
  if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
  ogr2ogr -f PostgreSQL "$OGR_PG" "/vsizip/$z" -nln open.ine_bgri2021 -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 \
    -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST $mode --config PG_USE_COPY YES
done
# TODO after first run: map INE field names to (bgri2021, n_individuos, n_edificios) used by facts_at().

echo "== APA flood layers via ArcGIS REST (GeoJSON, bbox of pilot regions)"
BBOX=$(psql "$PG_DSN" -tAc "SELECT string_agg(v::text, ',') FROM (SELECT unnest(ARRAY[ST_XMin(e),ST_YMin(e),ST_XMax(e),ST_YMax(e)]) v FROM (SELECT ST_Extent(ST_Transform(geom,4326)) e FROM open.pilot_regions) s) t")
APA="https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/parh/MapServer"
for L in 28 27; do
  ogr2ogr -f PostgreSQL "$OGR_PG" "$APA/$L/query?where=1%3D1&geometry=$BBOX&geometryType=esriGeometryEnvelope&inSR=4326&outFields=*&f=geojson" \
    -nln "open.apa_cheias_l$L" -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 -clipsrc "$RAW/pilot_clip.gpkg" \
    -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -overwrite || echo "WARN layer $L failed (paging? maxRecordCount 100000)"
done
psql "$PG_DSN" -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE IF EXISTS open.apa_cheias;
CREATE TABLE open.apa_cheias AS
  SELECT 'inundacoes_2007_60_CE'::text AS tipo, geom FROM open.apa_cheias_l28
  UNION ALL SELECT 'zona_adjacente', geom FROM open.apa_cheias_l27;
CREATE INDEX ON open.apa_cheias USING GIST (geom);
SQL

echo "== provenance rows (from manifest) — edit reference dates in data/sources.md if they change"
psql "$PG_DSN" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid) VALUES
 ('caop2025','Carta Administrativa Oficial de Portugal 2025 (Continente)','Direção-Geral do Território','CC BY 4.0','https://www.dgterritorio.gov.pt/dados-abertos','2025',3763),
 ('cos2023','Carta de Uso e Ocupação do Solo 2023','Direção-Geral do Território','CC BY 4.0','https://smos.dgterritorio.gov.pt/','2023',3763),
 ('icnf_perigosidade','Carta de Perigosidade de Incêndio Rural (SRUP)','ICNF / DGT','CC BY 4.0','https://dados.gov.pt/pt/datasets/srup-carta-de-perigosidade-de-incendio-rural/','2022-03-28',3763),
 ('apa_cheias','Zonas inundáveis (Diretiva 2007/60/CE) e zonas adjacentes','Agência Portuguesa do Ambiente (SNIAmb)','open data (APA)','https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/parh/MapServer','PGRI 2022-2027',3857),
 ('ine_bgri2021','BGRI 2021 e Censos 2021','Instituto Nacional de Estatística','open data (INE)','https://mapas.ine.pt/download/index2021.phtml','2021',3763)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now();
UPDATE open.dataset_meta m SET row_count = c.n FROM (
  SELECT 'caop2025' id, count(*) n FROM open.caop_freguesias UNION ALL
  SELECT 'cos2023', count(*) FROM open.cos2023 UNION ALL
  SELECT 'icnf_perigosidade', count(*) FROM open.icnf_perigosidade UNION ALL
  SELECT 'apa_cheias', count(*) FROM open.apa_cheias UNION ALL
  SELECT 'ine_bgri2021', count(*) FROM open.ine_bgri2021) c WHERE c.id = m.id;
SELECT id, row_count FROM open.dataset_meta ORDER BY id;
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
SQL
psql "$PG_DSN" -v ON_ERROR_STOP=1 -f "$ROOT/data/views.sql"
echo "done"

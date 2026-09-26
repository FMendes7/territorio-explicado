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

echo "== CAOP 2025 (national) — layers cont_freguesias + cont_municipios (confirmed 2026-09-26)"
CAOP_GPKG=$(unzip -Z1 "$RAW/caop2025_continente_gpkg.zip" | grep -i "\.gpkg$" | head -1)
[ -f "$RAW/$CAOP_GPKG" ] || unzip -o -q "$RAW/caop2025_continente_gpkg.zip" "$CAOP_GPKG" -d "$RAW"
ogr2ogr -f PostgreSQL "$OGR_PG" "$RAW/$CAOP_GPKG" -nln open.caop_freguesias -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 \
  -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -overwrite --config PG_USE_COPY YES -dialect OGRSQL \
  -sql "SELECT dtmnfr AS dico, freguesia, municipio AS concelho, distrito_ilha AS distrito, nuts3_cod, nuts3, area_ha FROM cont_freguesias"
ogr2ogr -f PostgreSQL "$OGR_PG" "$RAW/$CAOP_GPKG" -nln open.caop_municipios -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 \
  -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -overwrite --config PG_USE_COPY YES -dialect OGRSQL \
  -sql "SELECT dtmn AS dico, municipio AS concelho, distrito_ilha AS distrito, nuts3_cod, nuts3, area_ha, n_freguesias FROM cont_municipios"

echo "== pilot regions from CAOP municipios × data/regioes.json (dico_hint cross-checked by name)"
DICOS=$(jq -r '.regions[].municipalities[].dico_hint' "$ROOT/data/regioes.json" | awk '{printf "%s'\''%s'\''", (NR>1?",":""), $0}')
jq -r '.regions[] as $r | $r.municipalities[] | [$r.id, .dico_hint, .name] | @tsv' "$ROOT/data/regioes.json" > "$RAW/regioes.tsv"
psql "$PG_DSN" -v ON_ERROR_STOP=1 <<SQL
DROP TABLE IF EXISTS open.pilot_regions;
CREATE TABLE open.pilot_regions (region text, dico text, name_expected text);
\copy open.pilot_regions FROM '$RAW/regioes.tsv' WITH (FORMAT csv, DELIMITER E'\t')
ALTER TABLE open.pilot_regions ADD COLUMN concelho text, ADD COLUMN geom geometry(MultiPolygon, 3763);
UPDATE open.pilot_regions p SET concelho = m.concelho, geom = m.geom FROM open.caop_municipios m WHERE m.dico = p.dico;
CREATE INDEX ON open.pilot_regions USING GIST (geom);
-- fail loudly if a dico_hint does not match the expected municipality name in CAOP
DO \$\$ DECLARE bad text; BEGIN
  SELECT string_agg(dico||':'||coalesce(concelho,'<none>')||'≠'||name_expected, ', ') INTO bad
  FROM open.pilot_regions WHERE concelho IS DISTINCT FROM name_expected;
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'dico_hint mismatch vs CAOP: %', bad; END IF;
END \$\$;
SELECT region, count(*) AS municipalities, round(sum(ST_Area(geom))/1e6) AS km2 FROM open.pilot_regions GROUP BY region ORDER BY region;
SQL
ogr2ogr -f GPKG "$RAW/pilot_clip.gpkg" "$OGR_PG" -sql "SELECT ST_Union(geom) AS geom FROM open.pilot_regions" -nln clip -overwrite

load_clipped() { # id  source  target_table  [extra ogr args]
  local id="$1" src="$2" tbl="$3"; shift 3
  echo "== $id → open.$tbl (clipped)"
  ogr2ogr -f PostgreSQL "$OGR_PG" "$src" -nln "open.$tbl" -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 \
    -clipsrc "$RAW/pilot_clip.gpkg" -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -overwrite \
    --config PG_USE_COPY YES "$@"
}
if [ -f "$RAW/cos2023.zip" ] && unzip -Z1 "$RAW/cos2023.zip" >/dev/null 2>&1; then   # partial download → zip test fails → skip
  COS_GPKG=$(unzip -Z1 "$RAW/cos2023.zip" | grep -i "\.gpkg$" | head -1)
  COS_LAYER=$(ogrinfo -ro -so "/vsizip/$RAW/cos2023.zip/$COS_GPKG" | sed -n 's/^1: \([^ ]*\).*/\1/p')
  load_clipped cos2023 "/vsizip/$RAW/cos2023.zip/$COS_GPKG" cos2023 "$COS_LAYER"
  # normalise the level-4 label column name to cos_label (COS naming varies by edition)
  psql "$PG_DSN" -v ON_ERROR_STOP=1 <<'SQL'
DO $$ DECLARE c text; BEGIN
  SELECT column_name INTO c FROM information_schema.columns
   WHERE table_schema='open' AND table_name='cos2023' AND column_name ~* '(n4|nivel4|lvl4).*(_l|label|leg|desig)|^cos.*_l$|legenda|designacao'
   ORDER BY column_name LIMIT 1;
  IF c IS NULL THEN RAISE NOTICE 'cos2023: no label column matched — set cos_label manually'; 
  ELSIF c <> 'cos_label' THEN EXECUTE format('ALTER TABLE open.cos2023 RENAME COLUMN %I TO cos_label', c); END IF;
END $$;
SQL
fi

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
  base=$(basename "${z%.zip}")   # BGRI2021_<DICO> = inner gpkg name = layer name (confirmed 2026-09-26)
  ogr2ogr -f PostgreSQL "$OGR_PG" "/vsizip/$z/$base.gpkg" -nln open.ine_bgri2021 -nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 \
    -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST $mode --config PG_USE_COPY YES -dialect OGRSQL \
    -sql "SELECT BGRI2021 AS bgri2021, DTMN21 AS dico, DTMNFR21 AS dtmnfr, N_INDIVIDUOS AS n_individuos, N_EDIFICIOS_CLASSICOS AS n_edificios, N_ALOJAMENTOS_TOTAL AS n_alojamentos, N_INDIVIDUOS_65_OU_MAIS AS n_65mais FROM $base"
done

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

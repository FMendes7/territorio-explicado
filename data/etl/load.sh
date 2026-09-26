#!/usr/bin/env bash
# data/etl/load.sh — load the downloaded datasets into PostGIS, clipped to the pilot regions (per region)
# What: runs data/schema.sql; loads CAOP nationally (freguesias + municípios); builds open.pilot_regions
#       from data/regioes.json (DICO codes cross-checked against CAOP names, fails loudly on mismatch);
#       then, REGION BY REGION (small bboxes → small downloads), loads COS2023, the fire-hazard WFS
#       (6 feature types, one per class), INE BGRI per municipality and APA flood layers; fills
#       open.dataset_meta; applies data/views.sql.
# Depends on: GDAL/OGR ≥ 3.6 (ogr2ogr/ogrinfo), psql, jq, unzip; env PG_DSN (password via PGPASSWORD/.pgpass,
#       never on the command line); files from data/etl/download.sh in data/raw/.
# Used by: one-off data preparation (pre-existing component, declared in PRE-EXISTING.md). Re-runnable.
# When changing: table/column names here are the contract read by open.facts_at() (schema.sql) and by
#       data/views.sql — caop_freguesias(dico,freguesia,concelho,distrito), cos2023(cos_label),
#       icnf_perigosidade(classe,classe_ord), apa_cheias(tipo), ine_bgri2021(bgri2021,n_individuos,n_edificios).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; RAW="$ROOT/data/raw"
: "${PG_DSN:?set PG_DSN=postgresql://user@host:port/db (password via PGPASSWORD/.pgpass)}"
OGR_PG="PG:$PG_DSN"
ONLY="${ONLY:-caop cos icnf ine apa meta}"   # e.g. ONLY="cos meta" to re-run one stage
stage() { case " $ONLY " in *" $1 "*) return 0;; *) return 1;; esac; }
OGR_COMMON=(-nlt PROMOTE_TO_MULTI -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST --config PG_USE_COPY YES)

echo "== schema"; psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -f "$ROOT/data/schema.sql"

if stage caop; then
echo "== CAOP 2025 (national) — cont_freguesias + cont_municipios"
CAOP_GPKG=$(unzip -Z1 "$RAW/caop2025_continente_gpkg.zip" | grep -i "\.gpkg$" | head -1)
[ -f "$RAW/$CAOP_GPKG" ] || unzip -o -q "$RAW/caop2025_continente_gpkg.zip" "$CAOP_GPKG" -d "$RAW"
ogr2ogr -f PostgreSQL "$OGR_PG" "$RAW/$CAOP_GPKG" -nln open.caop_freguesias "${OGR_COMMON[@]}" -overwrite -dialect OGRSQL \
  -sql "SELECT dtmnfr AS dico, freguesia, municipio AS concelho, distrito_ilha AS distrito, nuts3_cod, nuts3, area_ha FROM cont_freguesias"
ogr2ogr -f PostgreSQL "$OGR_PG" "$RAW/$CAOP_GPKG" -nln open.caop_municipios "${OGR_COMMON[@]}" -overwrite -dialect OGRSQL \
  -sql "SELECT dtmn AS dico, municipio AS concelho, distrito_ilha AS distrito, nuts3_cod, nuts3, area_ha, n_freguesias FROM cont_municipios"

echo "== pilot regions (data/regioes.json × CAOP, cross-checked by name)"
jq -r '.regions[] as $r | $r.municipalities[] | [$r.id, .dico_hint, .name] | @tsv' "$ROOT/data/regioes.json" > "$RAW/regioes.tsv"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
DROP TABLE IF EXISTS open.pilot_regions;
CREATE TABLE open.pilot_regions (region text, dico text, name_expected text);
\copy open.pilot_regions FROM '$RAW/regioes.tsv' WITH (FORMAT csv, DELIMITER E'\t')
ALTER TABLE open.pilot_regions ADD COLUMN concelho text, ADD COLUMN geom geometry(MultiPolygon, 3763);
UPDATE open.pilot_regions p SET concelho = m.concelho, geom = m.geom FROM open.caop_municipios m WHERE m.dico = p.dico;
CREATE INDEX ON open.pilot_regions USING GIST (geom);
DO \$\$ DECLARE bad text; BEGIN
  SELECT string_agg(dico||':'||coalesce(concelho,'<none>')||'≠'||name_expected, ', ') INTO bad
  FROM open.pilot_regions WHERE concelho IS DISTINCT FROM name_expected;
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'dico_hint mismatch vs CAOP: %', bad; END IF;
END \$\$;
SQL
psql "$PG_DSN" -c "SELECT region, count(*) AS municipalities, round(sum(ST_Area(geom))/1e6) AS km2 FROM open.pilot_regions GROUP BY region ORDER BY region;"
fi

# per-region clip files + bboxes (3763 and 4326)
REGIONS=$(psql "$PG_DSN" -Atc "SELECT DISTINCT region FROM open.pilot_regions ORDER BY 1")
bbox3763() { psql "$PG_DSN" -Atc "SELECT ST_XMin(e)||' '||ST_YMin(e)||' '||ST_XMax(e)||' '||ST_YMax(e) FROM (SELECT ST_Extent(geom) e FROM open.pilot_regions WHERE region='$1') s"; }
bbox4326() { psql "$PG_DSN" -Atc "SELECT ST_XMin(e)||','||ST_YMin(e)||','||ST_XMax(e)||','||ST_YMax(e) FROM (SELECT ST_Extent(ST_Transform(geom,4326)) e FROM open.pilot_regions WHERE region='$1') s"; }
for R in $REGIONS; do
  ogr2ogr -f GPKG "$RAW/pilot_clip_$R.gpkg" "$OGR_PG" -sql "SELECT ST_Union(geom) AS geom FROM open.pilot_regions WHERE region='$R'" -nln clip -overwrite
done

# load_clipped ID SRC TABLE [LAYER] — loops the regions: first region -overwrite, then -append
load_clipped() {
  local id="$1" src="$2" tbl="$3" layer="${4:-}" first=1 mode
  for R in $REGIONS; do
    if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
    echo "   $id → open.$tbl [$R]"
    # shellcheck disable=SC2086
    ogr2ogr -f PostgreSQL "$OGR_PG" "$src" $layer -nln "open.$tbl" "${OGR_COMMON[@]}" $mode \
      -spat $(bbox3763 "$R") -clipsrc "$RAW/pilot_clip_$R.gpkg"
  done
}

if stage cos && [ -f "$RAW/cos2023.zip" ] && unzip -Z1 "$RAW/cos2023.zip" >/dev/null 2>&1; then   # partial download → skip
  echo "== COS2023 (clipped per region) — read from the EXTRACTED gpkg: /vsizip forces sequential decompression of 898 MB and defeats the R-tree"
  COS_GPKG=$(unzip -Z1 "$RAW/cos2023.zip" | grep -i "\.gpkg$" | head -1)
  [ -f "$RAW/$COS_GPKG" ] || unzip -o -q "$RAW/cos2023.zip" "$COS_GPKG" -d "$RAW"
  COS_LAYER=$(ogrinfo -ro -so "$RAW/$COS_GPKG" | sed -n 's/^1: \([^ ]*\).*/\1/p')
  load_clipped cos2023 "$RAW/$COS_GPKG" cos2023 "$COS_LAYER"
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$ DECLARE c text; BEGIN   -- normalise the level-4 label column to cos_label (naming varies by edition)
  SELECT column_name INTO c FROM information_schema.columns
   WHERE table_schema='open' AND table_name='cos2023'
     AND column_name ~* '(n4|nivel4|lvl4).*(_l|label|leg|desig)|^cos.*_l$|legenda|designacao' ORDER BY column_name LIMIT 1;
  IF c IS NULL THEN RAISE NOTICE 'cos2023: no label column matched — set cos_label manually';
  ELSIF c <> 'cos_label' THEN EXECUTE format('ALTER TABLE open.cos2023 RENAME COLUMN %I TO cos_label', c); END IF;
END $$;
SQL
else echo "== COS2023: skipped (stage off, zip missing or incomplete)"; fi

if stage icnf; then
echo "== ICNF fire hazard — official SNIT zip (shapefile, 1.75 M polygons, EPSG:3763); the DGT WFS is broken (see docs/lessons.md)"
[ -f "$RAW/icnf/PERIGOSIDADE_INCENDIO_RURAL.shp" ] || unzip -o -q "$RAW/icnf_perigosidade.zip" -d "$RAW/icnf"
[ -f "$RAW/icnf/PERIGOSIDADE_INCENDIO_RURAL.qix" ] || ogrinfo "$RAW/icnf/PERIGOSIDADE_INCENDIO_RURAL.shp" -sql "CREATE SPATIAL INDEX ON PERIGOSIDADE_INCENDIO_RURAL" >/dev/null
load_clipped icnf_perigosidade "$RAW/icnf/PERIGOSIDADE_INCENDIO_RURAL.shp" icnf_raw PERIGOSIDADE_INCENDIO_RURAL
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.icnf_perigosidade;
-- gridcode 1..5 = muito baixa .. muito alta (SRUP legend); anything else kept as its number
CREATE TABLE open.icnf_perigosidade AS
  SELECT CASE gridcode WHEN 1 THEN 'muito baixa' WHEN 2 THEN 'baixa' WHEN 3 THEN 'média' WHEN 4 THEN 'alta' WHEN 5 THEN 'muito alta' ELSE 'classe '||gridcode END AS classe,
         gridcode::int AS classe_ord, geom
  FROM open.icnf_raw;
CREATE INDEX ON open.icnf_perigosidade USING GIST (geom);
DROP TABLE open.icnf_raw;
SQL
fi

if stage ine; then
echo "== INE BGRI 2021 (one GeoPackage per municipality)"
first=1
for z in "$RAW"/bgri2021/BGRI2021_*.zip; do
  if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
  base=$(basename "${z%.zip}")   # inner gpkg name = layer name
  ogr2ogr -f PostgreSQL "$OGR_PG" "/vsizip/$z/$base.gpkg" -nln open.ine_bgri2021 "${OGR_COMMON[@]}" $mode -dialect OGRSQL \
    -sql "SELECT BGRI2021 AS bgri2021, DTMN21 AS dico, DTMNFR21 AS dtmnfr, N_INDIVIDUOS AS n_individuos, N_EDIFICIOS_CLASSICOS AS n_edificios, N_ALOJAMENTOS_TOTAL AS n_alojamentos, N_INDIVIDUOS_65_OU_MAIS AS n_65mais FROM $base"
done
fi

if stage apa; then
echo "== APA flood layers via ArcGIS REST (GeoJSON) — layers 28 (Inundações 2007/60/CE) + 27 (Zonas adjacentes), per region"
APA="https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/parh/MapServer"
for L in 28 27; do
  first=1
  for R in $REGIONS; do
    if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
    ogr2ogr -f PostgreSQL "$OGR_PG" "$APA/$L/query?where=1%3D1&geometry=$(bbox4326 "$R")&geometryType=esriGeometryEnvelope&inSR=4326&outFields=*&outSR=4326&f=geojson" \
      -nln "open.apa_cheias_l$L" "${OGR_COMMON[@]}" $mode -clipsrc "$RAW/pilot_clip_$R.gpkg" \
      || echo "WARN: APA layer $L [$R] failed"
  done
done
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.apa_cheias;
CREATE TABLE open.apa_cheias AS
  SELECT 'inundacoes_2007_60_CE'::text AS tipo, geom FROM open.apa_cheias_l28
  UNION ALL SELECT 'zona_adjacente', geom FROM open.apa_cheias_l27;
CREATE INDEX ON open.apa_cheias USING GIST (geom);
SQL
fi

if stage meta; then
echo "== provenance (open.dataset_meta) + views"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid) VALUES
 ('caop2025','Carta Administrativa Oficial de Portugal 2025 (Continente)','Direção-Geral do Território','CC BY 4.0','https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip','2025 (publ. 2026-02-18)',3763),
 ('cos2023','Carta de Uso e Ocupação do Solo 2023 v1 (Série 2)','Direção-Geral do Território','CC BY 4.0','https://geo2.dgterritorio.gov.pt/cos/S2/COS2023/COS2023v1-S2-gpkg.zip','2023',3763),
 ('icnf_perigosidade','Carta de Perigosidade de Incêndio Rural (SRUP)','ICNF / DGT','CC BY 4.0 (dados.gov.pt); ICNF metadata: consultation-only — see data/sources.md','https://servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1/WFService.aspx','2022-03-28',3763),
 ('apa_cheias','Zonas inundáveis (Diretiva 2007/60/CE) e zonas adjacentes','Agência Portuguesa do Ambiente (SNIAmb)','open data (APA)','https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/parh/MapServer','PGRI 2022-2027',3857),
 ('ine_bgri2021','BGRI 2021 e Censos 2021 (síntese)','Instituto Nacional de Estatística','open data (INE: acesso e uso sem condições)','https://mapas.ine.pt/download/index2021.phtml','2021',3763)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence;
UPDATE open.dataset_meta m SET row_count = c.n FROM (
  SELECT 'caop2025' id, count(*) n FROM open.caop_freguesias UNION ALL
  SELECT 'cos2023', count(*) FROM open.cos2023 WHERE to_regclass('open.cos2023') IS NOT NULL UNION ALL
  SELECT 'icnf_perigosidade', count(*) FROM open.icnf_perigosidade WHERE to_regclass('open.icnf_perigosidade') IS NOT NULL UNION ALL
  SELECT 'apa_cheias', count(*) FROM open.apa_cheias WHERE to_regclass('open.apa_cheias') IS NOT NULL UNION ALL
  SELECT 'ine_bgri2021', count(*) FROM open.ine_bgri2021 WHERE to_regclass('open.ine_bgri2021') IS NOT NULL) c WHERE c.id = m.id;
SQL
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -f "$ROOT/data/views.sql"
psql "$PG_DSN" -c "SELECT id, row_count FROM open.dataset_meta ORDER BY id;" -c "SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;"
fi
echo "done"

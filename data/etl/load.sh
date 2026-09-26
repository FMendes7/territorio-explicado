#!/usr/bin/env bash
# data/etl/load.sh — load the downloaded datasets into PostGIS, clipped to the pilot regions (per region)
# What: runs data/schema.sql; loads CAOP nationally (freguesias + municípios); builds open.pilot_regions
#       from data/regioes.json (DICO codes cross-checked against CAOP names, fails loudly on mismatch);
#       then, REGION BY REGION (small bboxes → small downloads), loads COS2023, the fire-hazard WFS
#       (6 feature types, one per class), INE BGRI per municipality and APA flood layers; then ICNF burned
#       areas 1975–2025 and protected areas (RNAP + Natura 2000 ZEC/ZPE) from the ICNF GeoServer WFS, DGT CRUS
#       (PDM land-use classes) per municipality, INE median €/m² (parish/municipality, joined through BGRI
#       2021 parish codes) and a dated snapshot of IPMA's fire-risk forecast (RCM) per municipality;
#       fills open.dataset_meta; applies data/views.sql.
# Depends on: GDAL/OGR ≥ 3.6 (ogr2ogr/ogrinfo), psql, jq, unzip, curl, sha256sum; env PG_DSN (password via
#       PGPASSWORD/.pgpass, never on the command line); files from data/etl/download.sh in data/raw/;
#       network for the WFS/REST/API stages (apa, ardidas, protegidas, crus, ipma). Stage `precos` needs
#       stage `ine` loaded (parish geometry = union of BGRI subsections). REFRESH=1 re-downloads cached
#       WFS exports (data/raw/icnf_wfs, data/raw/crus, data/raw/dem). Stage `relevo` also needs gdalwarp/gdaldem/
#       gdalbuildvrt, awk and raster2pgsql (or Docker with the postgis/postgis:16-3.4 image) and the postgis_raster
#       extension (created here; the server database needs it BEFORE a dump restore).
# Used by: one-off data preparation (pre-existing component, declared in PRE-EXISTING.md). Re-runnable.
# When changing: table/column names here are the contract read by open.facts_at() (schema.sql) and by
#       data/views.sql — caop_freguesias(dico,freguesia,concelho,distrito), cos2023(cos_label),
#       icnf_perigosidade(classe,classe_ord), apa_*(see schema.sql), ine_bgri2021(bgri2021,dtmnfr,n_individuos,
#       n_edificios), icnf_areas_ardidas(ano,area_ha,dh_inicio,causa_tipo), icnf_areas_protegidas(rede,categoria,
#       nome,codigo,diploma), dgt_crus(classe,categoria,designacao_pdm,escala,data_publicacao_pdm,esquema),
#       ine_precos_habitacao(nivel,codigo,nome,eur_m2,nota,periodo), ipma_rcm_snapshot(dico,data_prev,rcm,rcm_label),
#       cos_serie/v_cos_serie(ano,serie,cod_n4,label_n4,cod_n1), dem_elev/dem_slope(rast: Int16 m / %, 25 m).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; RAW="$ROOT/data/raw"
: "${PG_DSN:?set PG_DSN=postgresql://user@host:port/db (password via PGPASSWORD/.pgpass)}"
OGR_PG="PG:$PG_DSN"
ONLY="${ONLY:-caop cos icnf ine apa ardidas protegidas crus precos ipma cos_serie relevo meta}"   # e.g. ONLY="cos meta" to re-run one stage
stage() { case " $ONLY " in *" $1 "*) return 0;; *) return 1;; esac; }
OGR_COMMON=(-nlt PROMOTE_TO_MULTI -nlt CONVERT_TO_LINEAR -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST --config PG_USE_COPY YES)

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

# load_clipped ID SRC TABLE [LAYER] — per region: BBOX filter at the source (-spat, uses the file's spatial
# index), NO geometric clipping (clipping produced GeometryCollections at region borders → rows lost);
# then trim_to_regions() deletes what does not intersect the pilot regions. Features stay whole.
load_clipped() {
  local id="$1" src="$2" tbl="$3" layer="${4:-}" first=1 mode
  for R in $REGIONS; do
    if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
    echo "   $id → open.$tbl [$R]"
    # shellcheck disable=SC2086
    ogr2ogr -f PostgreSQL "$OGR_PG" "$src" $layer -nln "open.$tbl" "${OGR_COMMON[@]}" $mode -makevalid \
      -spat $(bbox3763 "$R")
  done
  trim_to_regions "$tbl"
}
trim_to_regions() {  # TABLE [poly|point] — keep what intersects a pilot region, dedupe, trim boundary-crossers (polygons), tag region
  local kind="${2:-poly}" TRIM_SQL="" KEEP_M=0
  [ "$kind" = point ] && KEEP_M=2000   # points (flood marks) just outside a municipality are still proximity evidence
  if [ "$(psql "$PG_DSN" -Atc "select to_regclass('open.$1') is not null")" != "t" ]; then echo "   open.$1: (no features loaded)"; return; fi
  [ "$kind" = poly ] && TRIM_SQL="UPDATE open.$1 t SET geom = ST_Multi(ST_CollectionExtract(ST_Intersection(t.geom, u.geom), 3)) FROM open.pilot_union u WHERE ST_Intersects(t.geom, u.boundary);
DELETE FROM open.$1 WHERE geom IS NULL OR ST_IsEmpty(geom);"
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
CREATE TABLE IF NOT EXISTS open.pilot_union AS
  SELECT ST_Union(geom) AS geom, ST_Boundary(ST_Union(geom)) AS boundary FROM open.pilot_regions;
DELETE FROM open.$1 t WHERE NOT EXISTS (SELECT 1 FROM open.pilot_regions p WHERE ST_DWithin(t.geom, p.geom, $KEEP_M));
-- the same source feature can arrive twice when its bbox touches two region bboxes → hash once, keep one copy
ALTER TABLE open.$1 ADD COLUMN _h text;
UPDATE open.$1 SET _h = md5(ST_AsBinary(geom));
DELETE FROM open.$1 a USING (SELECT _h, min(ctid) AS keep FROM open.$1 GROUP BY _h HAVING count(*) > 1) d
  WHERE a._h = d._h AND a.ctid <> d.keep;
ALTER TABLE open.$1 DROP COLUMN _h;
-- only polygons touching the pilot boundary can stick outside → trim those in PostGIS (collections handled)
$TRIM_SQL
ALTER TABLE open.$1 DROP COLUMN IF EXISTS region;
ALTER TABLE open.$1 ADD COLUMN region text;
UPDATE open.$1 t SET region = p.region FROM open.pilot_regions p WHERE ST_Intersects(t.geom, p.geom);
UPDATE open.$1 t SET region = (SELECT p.region FROM open.pilot_regions p ORDER BY t.geom <-> p.geom LIMIT 1) WHERE region IS NULL;
VACUUM ANALYZE open.$1;
SQL
  psql "$PG_DSN" -Atc "SELECT '   open.$1: '||count(*)||' rows, '||pg_size_pretty(pg_total_relation_size('open.$1')) FROM open.$1"
}

# manifest_add ID URL FILE — record a file fetched here (WFS/REST/API export) in data/raw/MANIFEST.tsv, same
# columns as download.sh; the previous row with the same id is replaced, so re-runs do not pile up rows.
# Used by: icnf_wfs, crus_municipio, stages precos/ipma. Changing the columns breaks download.sh's manifest.
manifest_add() {
  local id="$1" url="$2" f="$3" M="$RAW/MANIFEST.tsv"
  [ -f "$M" ] || printf 'id\turl\tfile\tretrieved_at\tbytes\tsha256\n' > "$M"
  awk -F'\t' -v id="$id" '$1 != id' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$url" "${f#"$RAW"/}" "$(date -u +%FT%TZ)" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" >> "$M"
}
cached() { [ -s "$1" ] && [ -z "${REFRESH:-}" ]; }   # FILE — reuse a previous WFS export unless REFRESH=1

# icnf_wfs SERVICE TYPENAME TABLE — ICNF GeoServer WFS (si.icnf.pt/wfs/SERVICE), GeoJSON in EPSG:3763, one
# request per region bbox (no paging needed: CountDefault 1 000 000, ≤ 1 200 features per bbox, checked
# 2026-09-26); appended to open.TABLE with -addfields because the burned-area layers up to 2013 carry only
# Ano + AreaHaSIG. Caller drops TABLE first and runs trim_to_regions after. Used by stages ardidas, protegidas.
icnf_wfs() {
  local svc="$1" typ="$2" tbl="$3" R f url n
  mkdir -p "$RAW/icnf_wfs"
  for R in $REGIONS; do
    f="$RAW/icnf_wfs/${typ}_$R.geojson"
    url="https://si.icnf.pt/wfs/$svc?service=WFS&version=2.0.0&request=GetFeature&typeNames=BDG:$typ&outputFormat=application/json&bbox=$(bbox3763 "$R" | tr ' ' ','),urn:ogc:def:crs:EPSG::3763"
    if ! cached "$f"; then
      curl -sS -m 300 --retry 2 -o "$f" "$url" || { echo "WARN: $typ [$R] download failed"; rm -f "$f"; continue; }
      grep -q '"features"' "$f" || { echo "WARN: $typ [$R] no FeatureCollection: $(head -c 160 "$f")"; rm -f "$f"; continue; }
      manifest_add "icnf_${typ}_$R" "$url" "$f"
    fi
    n=$(jq '.features | length' "$f"); echo "   $typ → open.$tbl [$R] $n features"
    [ "$n" -gt 0 ] || continue   # an empty first file would create the table with a generic geometry type
    ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -oo DATE_AS_STRING=YES -nln "open.$tbl" "${OGR_COMMON[@]}" -addfields -makevalid \
      || echo "WARN: $typ [$R] load failed"
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
-- gridcode 0..5 (counted nationally 2026-09-26: 0=114 550, 1=222 576, 2=596 032, 3=488 022, 4=271 899, 5=61 014); 0 = no hazard class (non-rural/water)
CREATE TABLE open.icnf_perigosidade AS
  SELECT CASE gridcode WHEN 0 THEN 'sem perigosidade' WHEN 1 THEN 'muito baixa' WHEN 2 THEN 'baixa' WHEN 3 THEN 'média' WHEN 4 THEN 'alta' WHEN 5 THEN 'muito alta' ELSE 'classe '||gridcode END AS classe,
         gridcode::int AS classe_ord, region, geom
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
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "ALTER TABLE open.ine_bgri2021 ADD COLUMN IF NOT EXISTS region text;" \
  -c "UPDATE open.ine_bgri2021 b SET region = p.region FROM open.pilot_regions p WHERE p.dico = b.dico;" -c "VACUUM ANALYZE open.ine_bgri2021;"
fi

if stage apa; then
echo "== APA / SNIAmb (ArcGIS REST, GeoJSON) — PGRI 2.º ciclo: perigo, zonas inundáveis (período de retorno + cota), ARPSI, marcas de cheia"
APA="https://sniambgeoogc.apambiente.pt/getogc/rest/services"
apa_layer() {  # ID SERVICE/MapServer/LAYER TABLE [poly|point] — per region bbox; counts are below each layer's maxRecordCount (checked 2026-09-26)
  local id="$1" path="$2" tbl="$3" kind="${4:-poly}" first=1 mode
  for R in $REGIONS; do
    if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
    echo "   $id → open.$tbl [$R]"
    # curl first, ogr2ogr from the file: GDAL's HTTP reader hung >10 min on this ArcGIS server (curl answers in ~1 s)
    local f="$RAW/apa_${tbl}_$R.geojson"
    curl -sS -m 180 --retry 2 -o "$f" "$APA/$path/query?where=1%3D1&geometry=$(bbox4326 "$R")&geometryType=esriGeometryEnvelope&inSR=4326&outFields=*&outSR=4326&f=geojson" \
      || { echo "WARN: $id [$R] download failed"; continue; }
    grep -q '"features"' "$f" || { echo "WARN: $id [$R] no FeatureCollection: $(head -c 160 "$f")"; continue; }
    # DATE_AS_STRING: the GeoJSON driver sniffs "T0100" (return period) as a TIME → keep strings as strings
    ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -oo DATE_AS_STRING=YES -nln "open.$tbl" "${OGR_COMMON[@]}" $mode -makevalid || echo "WARN: $id [$R] load failed"
  done
  trim_to_regions "$tbl" "$kind"
}
apa_layer apa_perigo           "Visualizador/PGRI_2C_Perigo_IGT/MapServer/0" apa_perigo_inundacao
apa_layer apa_zonas_inundaveis "Visualizador/PGRI_2C_Perigo_IGT/MapServer/1" apa_zonas_inundaveis
apa_layer apa_arpsi            "SNIAmb/Risco_Inundacao_Potencialmente_Significativas/MapServer/0" apa_arpsi   # Dashboard/pgri_med2c/2 exports no geometry (checked 2026-09-26)
apa_layer apa_marcas_cheia     "SNIAmb/Marcas_cheias/MapServer/0"            apa_marcas_cheia point
# the first attempt (Visualizador/parh layers 28/27) only had 5 ARPSI blocks and no attributes → replaced
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "DROP TABLE IF EXISTS open.apa_cheias, open.apa_cheias_l28, open.apa_cheias_l27;" -c "DELETE FROM open.dataset_meta WHERE id = 'apa_cheias';"
fi

if stage ardidas; then
echo "== ICNF áreas ardidas 1975–2025 (WFS si.icnf.pt/wfs/areas_ardidas: 3 period layers + one layer per year from 2009)"
ARDIDA_LAYERS="ardida_1975_1989 ardida_1990_1999 ardida_2000_2008 $(seq -f 'ardida_%g' 2009 2025 | tr '\n' ' ')"
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.icnf_ardidas_raw;"
for L in $ARDIDA_LAYERS; do icnf_wfs areas_ardidas "$L" icnf_ardidas_raw; done
trim_to_regions icnf_ardidas_raw
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.icnf_areas_ardidas;
-- one row per burned polygon; `camada` = source WFS layer, derived from the year (GDAL drops the text part of the
-- GeoJSON id "<layer>.<n>"); start/end time, cause and parish of ignition only exist in the yearly layers from 2014 (checked)
CREATE TABLE open.icnf_areas_ardidas AS
  SELECT ano::int AS ano, round(areahasig::numeric, 2) AS area_ha, dh_inicio, dh_fim, causa_tipo, causa_desc,
         pi_freg AS freguesia_inicio, cod_sgif,
         CASE WHEN ano < 1990 THEN 'ardida_1975_1989' WHEN ano < 2000 THEN 'ardida_1990_1999'
              WHEN ano < 2009 THEN 'ardida_2000_2008' ELSE 'ardida_' || ano END AS camada, region, geom
  FROM open.icnf_ardidas_raw;
CREATE INDEX ON open.icnf_areas_ardidas USING GIST (geom);
CREATE INDEX ON open.icnf_areas_ardidas (ano);
DROP TABLE open.icnf_ardidas_raw;
VACUUM ANALYZE open.icnf_areas_ardidas;
SQL
fi

if stage protegidas; then
echo "== ICNF protected areas — RNAP (si.icnf.pt/wfs/rnap) + Rede Natura 2000 ZEC (wfs/zec) and ZPE (wfs/zpe)"
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.icnf_rnap_raw, open.icnf_zec_raw, open.icnf_zpe_raw;"
# each network trimmed on its own: a ZEC and a ZPE can share a boundary, and trim_to_regions dedupes by geometry
icnf_wfs rnap rnap icnf_rnap_raw; trim_to_regions icnf_rnap_raw
icnf_wfs zec  zec  icnf_zec_raw;  trim_to_regions icnf_zec_raw
icnf_wfs zpe  zpe  icnf_zpe_raw;  trim_to_regions icnf_zpe_raw
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.icnf_areas_protegidas;
CREATE TABLE open.icnf_areas_protegidas (rede text, categoria text, nome text, codigo text, diploma text,
  area_ha_total numeric, region text, geom geometry(MultiPolygon, 3763));
DO $$ BEGIN   -- a network with no feature in the pilot regions leaves no raw table
  IF to_regclass('open.icnf_rnap_raw') IS NOT NULL THEN
    INSERT INTO open.icnf_areas_protegidas SELECT 'RNAP', classifica, nome_ap, sigla, nullif(concat_ws('; ', publica1, publica2), ''),
      round(area_ha::numeric, 2), region, geom FROM open.icnf_rnap_raw; END IF;
  IF to_regclass('open.icnf_zec_raw') IS NOT NULL THEN
    INSERT INTO open.icnf_areas_protegidas SELECT 'Rede Natura 2000', 'Zona Especial de Conservação (ZEC)', site_name, site_code, NULL,
      round(area__ha_::numeric, 2), region, geom FROM open.icnf_zec_raw; END IF;
  IF to_regclass('open.icnf_zpe_raw') IS NOT NULL THEN
    INSERT INTO open.icnf_areas_protegidas SELECT 'Rede Natura 2000', 'Zona de Proteção Especial (ZPE)', site_name, site_code, NULL,
      round(area__ha_::numeric, 2), region, geom FROM open.icnf_zpe_raw; END IF;
END $$;
CREATE INDEX ON open.icnf_areas_protegidas USING GIST (geom);
DROP TABLE IF EXISTS open.icnf_rnap_raw, open.icnf_zec_raw, open.icnf_zpe_raw;
VACUUM ANALYZE open.icnf_areas_protegidas;
SQL
fi

if stage crus; then
echo "== DGT CRUS — Carta do Regime de Uso do Solo (PDM classes, DR 15/2015), one WFS per municipality"
# crus_municipio DICO — GeoMedia WFS SDISNITWFSCRUS_<DICO>_1: feature type name varies (CRUS_<Name>_V) → read it
# from GetCapabilities; GML 3.1.1 in EPSG:3763, whole municipality in one response (Barcelos 3 070 features,
# 11 MB, 12 s on 2026-09-26). Cached in data/raw/crus/ (slow server; REFRESH=1 to re-fetch).
crus_municipio() {
  local d="$1" W="https://servicos.dgterritorio.pt/SDISNITWFSCRUS_${1}_1/WFService.aspx" typ f url
  f="$RAW/crus/CRUS_$d.gml"
  if ! cached "$f"; then
    # `|| true`: under set -e -o pipefail a failed curl/grep inside $(…) would abort the whole ETL before the WARN
    typ=$(curl -sS -m 180 --retry 2 "$W?service=WFS&request=GetCapabilities&version=2.0.0" | grep -o '<wfs:Name>[^<]*' | head -1 | sed 's/<wfs:Name>//' || true)
    [ -n "$typ" ] || { echo "WARN: CRUS $d — no feature type in GetCapabilities"; return; }
    url="$W?service=WFS&version=2.0.0&request=GetFeature&typeNames=$typ"
    curl -sS -m 900 --retry 2 -o "$f" "$url" || { echo "WARN: CRUS $d download failed"; rm -f "$f"; return; }
    grep -q 'numberOfFeatures="[1-9]' "$f" || { echo "WARN: CRUS $d — no features: $(head -c 200 "$f")"; rm -f "$f"; return; }
    manifest_add "dgt_crus_$d" "$url" "$f"
  fi
  echo "   CRUS $d → open.dgt_crus_raw ($(grep -o 'numberOfFeatures="[0-9]*"' "$f" | head -1))"
  ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -nln open.dgt_crus_raw "${OGR_COMMON[@]}" -addfields -makevalid || echo "WARN: CRUS $d load failed"
}
mkdir -p "$RAW/crus"
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.dgt_crus_raw;"
for d in $(psql "$PG_DSN" -Atc "SELECT dico FROM open.pilot_regions ORDER BY dico"); do crus_municipio "$d"; done
trim_to_regions dgt_crus_raw
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.dgt_crus;
-- two CRUS schemas coexist (checked 2026-09-26): PDMs already re-coded to DR 15/2015 carry Classe/Categoria/
-- Designacao_PlantaOrdenamento/Escala_PlantaOrdenamento/Data_PublicacaoPDM; older PDMs (Barcelos, Esposende, Terras de
-- Bouro, Vila Verde, Miranda do Corvo, Penela) only Designacao_no_plano/Escala_origem/Data_Pub_Origem → classe stays
-- NULL there (never inferred) and `esquema` says which one; -addfields created the union of both column sets
ALTER TABLE open.dgt_crus_raw ADD COLUMN IF NOT EXISTS classe text, ADD COLUMN IF NOT EXISTS categoria text,
  ADD COLUMN IF NOT EXISTS designacao_plantaordenamento text, ADD COLUMN IF NOT EXISTS escala_plantaordenamento text,
  ADD COLUMN IF NOT EXISTS data_publicacaopdm text, ADD COLUMN IF NOT EXISTS designacao_no_plano text,
  ADD COLUMN IF NOT EXISTS escala_origem text, ADD COLUMN IF NOT EXISTS data_pub_origem text,
  ADD COLUMN IF NOT EXISTS data_pulicacaopdm text;   -- sic: Cantanhede's export misspells the field (Data_PulicacaoPDM)
CREATE TABLE open.dgt_crus AS
  -- lpad: GML type sniffing may read DTCC as an integer (0601 → 601)
  SELECT lpad(dtcc::text, 4, '0') AS dico, municipio, classe, categoria,
         coalesce(designacao_plantaordenamento, designacao_no_plano) AS designacao_pdm,
         coalesce(escala_plantaordenamento, escala_origem) AS escala,
         left(coalesce(data_publicacaopdm::text, data_pulicacaopdm::text, data_pub_origem::text), 10) AS data_publicacao_pdm,
         CASE WHEN designacao_plantaordenamento IS NOT NULL OR classe IS NOT NULL THEN 'DR 15/2015'
              ELSE 'anterior ao DR 15/2015 (designação original do PDM)' END AS esquema,
         fonte, round(area_ha::numeric, 2) AS area_ha, region, geom
  FROM open.dgt_crus_raw;
CREATE INDEX ON open.dgt_crus USING GIST (geom);
DROP TABLE open.dgt_crus_raw;
VACUUM ANALYZE open.dgt_crus;
SQL
psql "$PG_DSN" -c "SELECT region, esquema, count(DISTINCT dico) AS municipalities, count(*) AS polygons, count(*) FILTER (WHERE designacao_pdm IS NULL) AS no_designation FROM open.dgt_crus GROUP BY 1, 2 ORDER BY 1, 2;"
fi

if stage precos; then
echo "== INE median €/m² of family-dwelling sales, last 12 months (indicator 0012234, NUTS 2024: municipality + parish)"
PRECOS_JSON="$RAW/ine_precos_0012234_S5A20261.json"   # fetched by download.sh (quarter pinned for reproducibility)
[ -s "$PRECOS_JSON" ] || { echo "ERROR: $PRECOS_JSON missing — run data/etl/download.sh"; exit 1; }
# geocod = NUTS III prefix (3 chars) + DICO (4) or DICOFRE (6, 2013-reform parish codes, some with letters: 0302FG);
# keep category H1 (Total); empty valor = not published (sinal_conv '-')
jq -r '.[0] as $r | $r.Dados | to_entries[] | .key as $p | .value[] | select(.dim_3 == "H1") | select((.geocod | length) == 7 or (.geocod | length) == 9)
       | [.geocod, .geodsg, (.valor // ""), (.sinal_conv_desc // ""), $p, $r.DataUltimoAtualizacao] | @tsv' "$PRECOS_JSON" > "$RAW/ine_precos.tsv"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
DROP TABLE IF EXISTS open.ine_precos_habitacao;
CREATE TEMP TABLE s (geocod text, nome text, valor text, nota text, periodo text, atualizado text);
\copy s FROM '$RAW/ine_precos.tsv' WITH (FORMAT text)
CREATE TABLE open.ine_precos_habitacao AS
  SELECT substr(s.geocod, 4) AS codigo, CASE length(s.geocod) WHEN 7 THEN 'municipio' ELSE 'freguesia' END AS nivel, s.nome,
         nullif(s.valor, '')::int AS eur_m2, nullif(s.nota, '') AS nota, s.periodo, s.atualizado AS ine_atualizado,
         '0012234'::text AS indicador, p.region, NULL::geometry(MultiPolygon, 3763) AS geom
  FROM s JOIN open.pilot_regions p ON p.dico = substr(s.geocod, 4, 4);
-- parish codes follow the 2013 map (as BGRI 2021 DTMNFR21: 140/140 match) — CAOP 2025 split some parishes (138/140)
-- → parish geometry = union of the BGRI 2021 subsections of that parish; municipality geometry = CAOP 2025
UPDATE open.ine_precos_habitacao i SET geom = m.geom FROM open.caop_municipios m WHERE i.nivel = 'municipio' AND m.dico = i.codigo;
UPDATE open.ine_precos_habitacao i SET geom = g.geom
  FROM (SELECT dtmnfr, ST_Multi(ST_CollectionExtract(ST_Union(geom), 3)) AS geom FROM open.ine_bgri2021 GROUP BY dtmnfr) g
  WHERE i.nivel = 'freguesia' AND g.dtmnfr = i.codigo;
CREATE INDEX ON open.ine_precos_habitacao USING GIST (geom);
VACUUM ANALYZE open.ine_precos_habitacao;
SQL
psql "$PG_DSN" -c "SELECT region, nivel, count(*) AS rows, count(eur_m2) AS with_value, count(*) FILTER (WHERE geom IS NULL) AS no_geom FROM open.ine_precos_habitacao GROUP BY 1,2 ORDER BY 1,2;"
fi

if stage ipma; then
echo "== IPMA fire-risk forecast (RCM) per municipality — dated SNAPSHOT (the agent reads the live API; this is the fallback)"
mkdir -p "$RAW/ipma"; : > "$RAW/ipma/rcm.tsv"
for d in 0 1 2; do   # 0 = today, 1 = tomorrow, 2 = day after (api.ipma.pt)
  url="https://api.ipma.pt/open-data/forecast/meteorology/rcm/rcm-d$d.json"; f="$RAW/ipma/rcm-d$d.json"
  curl -sS -m 60 --retry 2 -o "$f" "$url" && jq -e '.local' "$f" >/dev/null || { echo "WARN: IPMA rcm-d$d unavailable"; continue; }
  manifest_add "ipma_rcm_d$d" "$url" "$f"
  jq -r '. as $r | .local | to_entries[] | [.value.dico, $r.dataPrev, .value.data.rcm, $r.dataRun, $r.fileDate] | @tsv' "$f" >> "$RAW/ipma/rcm.tsv"
done
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
CREATE TABLE IF NOT EXISTS open.ipma_rcm_snapshot (dico text, data_prev date, rcm int, rcm_label text, data_run date,
  file_date timestamp, retrieved_at timestamptz NOT NULL DEFAULT now(), region text, PRIMARY KEY (dico, data_prev));
CREATE TEMP TABLE s (dico text, data_prev date, rcm int, data_run date, file_date timestamp);
\copy s FROM '$RAW/ipma/rcm.tsv' WITH (FORMAT text)
-- history accumulates (one row per municipality per forecast day); a re-run the same day refreshes the row
INSERT INTO open.ipma_rcm_snapshot (dico, data_prev, rcm, rcm_label, data_run, file_date, region)
  SELECT s.dico, s.data_prev, s.rcm,
         CASE s.rcm WHEN 1 THEN 'reduzido' WHEN 2 THEN 'moderado' WHEN 3 THEN 'elevado' WHEN 4 THEN 'muito elevado' WHEN 5 THEN 'máximo' END,
         s.data_run, s.file_date, p.region
  FROM s JOIN open.pilot_regions p ON p.dico = s.dico
ON CONFLICT (dico, data_prev) DO UPDATE SET rcm = EXCLUDED.rcm, rcm_label = EXCLUDED.rcm_label, data_run = EXCLUDED.data_run,
  file_date = EXCLUDED.file_date, retrieved_at = now();
SQL
psql "$PG_DSN" -c "SELECT data_prev, count(*) AS municipalities, round(avg(rcm), 1) AS avg_rcm FROM open.ipma_rcm_snapshot GROUP BY 1 ORDER BY 1 DESC LIMIT 3;"
fi

if stage cos_serie; then
echo "== COS time series — Série 2 2018v4 · 2025v1 (same nomenclature as COS2023) + Série 1 1995v2 (older nomenclature)"
# One table for the other editions (COS2023 stays in open.cos2023 — the facts_at contract); view open.v_cos_serie unites
# all. Level 1 = first segment of the n4 code in both series (checked on COS2023: 1 artificial … 9 water); Série 1 and 2
# differ below level 1, so change across series is only asserted at level 1 (docs/failure-modes.md).
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS open.cos_serie (ano int NOT NULL, serie text NOT NULL, cod_n4 text, label_n4 text, cod_n1 text,
  region text, geom geometry(MultiPolygon, 3763));
CREATE INDEX IF NOT EXISTS cos_serie_geom_idx ON open.cos_serie USING GIST (geom);
CREATE INDEX IF NOT EXISTS cos_serie_ano_idx ON open.cos_serie (ano);
SQL
COS_ANOS="${COS_ANOS:-2018 2025 1995}"   # e.g. COS_ANOS=1995 to (re)load one edition only — each takes ~15–20 min
for spec in "2018|S2|cos2018.zip" "2025|S2|cos2025.zip" "1995|S1|cos1995.zip"; do
  IFS='|' read -r ANO SERIE ZIP <<< "$spec"
  case " $COS_ANOS " in *" $ANO "*) ;; *) continue ;; esac
  unzip -Z1 "$RAW/$ZIP" >/dev/null 2>&1 || { echo "WARN: $ZIP missing or incomplete — run download.sh"; continue; }
  G=$(unzip -Z1 "$RAW/$ZIP" | grep -i "\.gpkg$" | head -1)
  [ -f "$RAW/$G" ] || unzip -o -q "$RAW/$ZIP" "$G" -d "$RAW"   # extracted: /vsizip defeats the R-tree (docs/lessons.md)
  L=$(ogrinfo -ro -so "$RAW/$G" | sed -n 's/^1: \([^ ]*\).*/\1/p')
  psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.cos_raw_$ANO;"
  load_clipped "cos$ANO" "$RAW/$G" "cos_raw_$ANO" "$L"
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$ DECLARE c text; l text; BEGIN   -- code/label column names vary by edition (cos23_n4_c, COS95_n4_L, …)
  SELECT column_name INTO c FROM information_schema.columns WHERE table_schema='open' AND table_name='cos_raw_$ANO'
   AND column_name ~* 'n4_c(od)?\$' ORDER BY 1 LIMIT 1;
  SELECT column_name INTO l FROM information_schema.columns WHERE table_schema='open' AND table_name='cos_raw_$ANO'
   AND column_name ~* 'n4_l(eg)?\$' ORDER BY 1 LIMIT 1;
  IF c IS NULL OR l IS NULL THEN RAISE EXCEPTION 'cos_raw_$ANO: n4 code/label columns not found'; END IF;
  DELETE FROM open.cos_serie WHERE ano = $ANO;
  EXECUTE format('INSERT INTO open.cos_serie (ano, serie, cod_n4, label_n4, cod_n1, region, geom)
                  SELECT $ANO, %L, %I::text, %I::text, split_part(%I::text, ''.'', 1), region, geom FROM open.cos_raw_$ANO', '$SERIE', c, l, c);
END \$\$;
DROP TABLE open.cos_raw_$ANO;
SQL
done
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
VACUUM ANALYZE open.cos_serie;
CREATE OR REPLACE VIEW open.v_cos_serie AS
  SELECT 2023 AS ano, 'S2'::text AS serie, cos23_n4_c::text AS cod_n4, cos_label::text AS label_n4,
         split_part(cos23_n4_c::text, '.', 1) AS cod_n1, region, geom FROM open.cos2023
  UNION ALL SELECT ano, serie, cod_n4, label_n4, cod_n1, region, geom FROM open.cos_serie;
SQL
psql "$PG_DSN" -c "SELECT ano, serie, count(*) AS polygons, count(DISTINCT cod_n4) AS classes FROM open.v_cos_serie GROUP BY 1, 2 ORDER BY 1;" \
  -c "SELECT pg_size_pretty(pg_total_relation_size('open.cos_serie')) AS cos_serie_size;"
fi

if stage relevo; then
echo "== Relief — Copernicus DEM GLO-30 (public COGs, no login) → elevation + slope (%) at 25 m, EPSG:3763, as PostGIS rasters"
# GLO-30 is a SURFACE model (X-band radar): canopy and buildings bias slope in forests and towns → labelled in every
# fact; the true-terrain upgrade is DGT's LiDAR 2024 MDT-2m (Centro de Dados, needs a free account — not scripted yet).
# raster2pgsql: the local binary if installed, else the same postgis/postgis image the database runs (no install).
mkdir -p "$RAW/dem"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "CREATE EXTENSION IF NOT EXISTS postgis_raster;"
for t in N38_00_W010 N39_00_W009 N39_00_W008 N40_00_W009 N40_00_W008 N41_00_W009; do   # 1°×1° tiles covering the 3 regions
  f="$RAW/dem/cop30_$t.tif"; u="https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_${t}_00_DEM/Copernicus_DSM_COG_10_${t}_00_DEM.tif"
  if ! cached "$f"; then curl -fsS -m 600 --retry 2 -o "$f" "$u" && manifest_add "cop_dem30_$t" "$u" "$f" || { echo "WARN: DEM tile $t failed"; rm -f "$f"; }; fi
done
gdalbuildvrt -q -overwrite "$RAW/dem/cop30.vrt" "$RAW"/dem/cop30_*.tif
for R in $REGIONS; do
  read -r X0 Y0 X1 Y1 <<< "$(bbox3763 "$R")"
  # 1 km margin so slope at the region edge sees its neighbours; tiles outside the pilot union are dropped after loading
  gdalwarp -q -overwrite -t_srs EPSG:3763 -tr 25 25 -tap -r bilinear -te $(awk -v a="$X0" -v b="$Y0" -v c="$X1" -v d="$Y1" 'BEGIN{print a-1000, b-1000, c+1000, d+1000}') \
    -ot Float32 "$RAW/dem/cop30.vrt" "$RAW/dem/elev_$R.tif"
  gdaldem slope -q -p -compute_edges "$RAW/dem/elev_$R.tif" "$RAW/dem/slope_$R.tif"
  gdal_translate -q -ot Int16 -a_nodata -32768 "$RAW/dem/elev_$R.tif" "$RAW/dem/elev_${R}_i16.tif"
  gdal_translate -q -ot Int16 -a_nodata -32768 "$RAW/dem/slope_$R.tif" "$RAW/dem/slope_${R}_i16.tif"
done
R2P() { if command -v raster2pgsql >/dev/null; then (cd "$RAW/dem" && raster2pgsql "$@"); else docker run --rm -v "$RAW/dem:/d" -w /d postgis/postgis:16-3.4 raster2pgsql "$@"; fi; }
for V in elev slope; do
  psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.dem_$V;"
  first=1
  for R in $REGIONS; do
    if [ $first -eq 1 ]; then mode=-c; first=0; else mode=-a; fi
    R2P $mode -s 3763 -t 100x100 -N -32768 "${V}_${R}_i16.tif" "open.dem_$V" | psql "$PG_DSN" -q -v ON_ERROR_STOP=1 >/dev/null
  done
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
DELETE FROM open.dem_$V d WHERE NOT EXISTS (SELECT 1 FROM open.pilot_regions p WHERE ST_Intersects(p.geom, ST_Envelope(d.rast)));
CREATE INDEX ON open.dem_$V USING GIST (ST_ConvexHull(rast));
VACUUM ANALYZE open.dem_$V;
SQL
done
psql "$PG_DSN" -c "SELECT 'dem_elev' t, count(*) tiles, pg_size_pretty(pg_total_relation_size('open.dem_elev')) FROM open.dem_elev UNION ALL SELECT 'dem_slope', count(*), pg_size_pretty(pg_total_relation_size('open.dem_slope')) FROM open.dem_slope;"
fi

if stage meta; then
echo "== provenance (open.dataset_meta) + views"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid) VALUES
 ('caop2025','Carta Administrativa Oficial de Portugal 2025 (Continente)','Direção-Geral do Território','CC BY 4.0','https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip','2025 (publ. 2026-02-18)',3763),
 ('cos2023','Carta de Uso e Ocupação do Solo 2023 v1 (Série 2)','Direção-Geral do Território','CC BY 4.0','https://geo2.dgterritorio.gov.pt/cos/S2/COS2023/COS2023v1-S2-gpkg.zip','2023',3763),
 ('icnf_perigosidade','Carta de Perigosidade de Incêndio Rural (SRUP)','ICNF / DGT','CC BY 4.0 (dados.gov.pt); ICNF metadata: consultation-only — see data/sources.md','https://servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1/WFService.aspx','2022-03-28',3763),
 ('apa_perigo','Perigo de inundação para IGT (PGRI 2.º ciclo) — costeiras e fluviais','Agência Portuguesa do Ambiente (SNIAmb)','open data (APA)','https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/PGRI_2C_Perigo_IGT/MapServer/0','PGRI 2022-2027',3763),
 ('apa_zonas_inundaveis','Zonas inundáveis por período de retorno (T20/T100/T1000) com cota máxima (PGRI 2.º ciclo)','Agência Portuguesa do Ambiente (SNIAmb)','open data (APA)','https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/PGRI_2C_Perigo_IGT/MapServer/1','PGRI 2022-2027',3763),
 ('apa_arpsi','Zonas com risco potencial significativo de inundação (ARPSI)','Agência Portuguesa do Ambiente (SNIAmb)','open data (APA)','https://sniambgeoogc.apambiente.pt/getogc/rest/services/SNIAmb/Risco_Inundacao_Potencialmente_Significativas/MapServer/0','Diretiva 2007/60/CE',3763),
 ('apa_marcas_cheia','Marcas de cheia históricas (SNIRH)','Agência Portuguesa do Ambiente (SNIAmb/SNIRH)','open data (APA)','https://sniambgeoogc.apambiente.pt/getogc/rest/services/SNIAmb/Marcas_cheias/MapServer/0','histórico (várias datas)',3763),
 ('ine_bgri2021','BGRI 2021 e Censos 2021 (síntese)','Instituto Nacional de Estatística','open data (INE: acesso e uso sem condições)','https://mapas.ine.pt/download/index2021.phtml','2021',3763),
 ('icnf_areas_ardidas','Áreas ardidas 1975–2025 (cartografia nacional, uma camada por período/ano)','ICNF','CC BY 4.0 (dados.gov.pt areas-ardidas-desde-1975)','https://si.icnf.pt/wfs/areas_ardidas','1975–2025 (camada 2025 incluída; retrieved 2026-09-26)',3763),
 ('icnf_areas_protegidas','Áreas protegidas: RNAP (DL 142/2008) + Rede Natura 2000 (ZEC e ZPE)','ICNF','CC BY 4.0 (dados.gov.pt rede-nacional-de-areas-protegidas-rnap, zonas-especiais-de-conservacao-…, zonas-de-protecao-especial-…)','https://si.icnf.pt/wfs/rnap ; https://si.icnf.pt/wfs/zec ; https://si.icnf.pt/wfs/zpe','limites em vigor (retrieved 2026-09-26)',3763),
 ('dgt_crus','Carta do Regime de Uso do Solo (classificação e qualificação do solo dos PDM, DR 15/2015)','Direção-Geral do Território (a partir das Plantas de Ordenamento municipais)','CC BY 4.0 (dados.gov.pt carta-do-regime-de-uso-do-solo-<município>)','https://servicos.dgterritorio.pt/SDISNITWFSCRUS_<DICO>_1/WFService.aspx','per municipality: PDM publication date in data_publicacao_pdm',3763),
 ('ine_precos_habitacao','Valor mediano das vendas de alojamentos familiares nos últimos 12 meses (Metodologia 2022, €/m²), NUTS 2024 — município e freguesia','Instituto Nacional de Estatística','CC BY 4.0 (dados.gov.pt; INE)','https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2&varcd=0012234&Dim1=S5A20261&lang=PT','12 meses até ao 1.º Trimestre de 2026 (INE, atualizado 2026-07-17)',3763),
 ('ipma_rcm','Risco de incêndio rural (RCM) — previsão diária por concelho (snapshot datado; o agente lê a API ao vivo)','IPMA','open data (IPMA API, attribution)','https://api.ipma.pt/open-data/forecast/meteorology/rcm/rcm-d{0,1,2}.json','daily; snapshot date in data_prev',3763),
 ('cos2025','Carta de Uso e Ocupação do Solo 2025 v1 (Série 2)','Direção-Geral do Território','CC BY 4.0','https://geo2.dgterritorio.gov.pt/cos/S2/COS2025/COS2025v1-S2-gpkg.zip','2025 (publ. 2026-07)',3763),
 ('cos2018','Carta de Uso e Ocupação do Solo 2018 v4 (Série 2, nomenclatura da COS2023)','Direção-Geral do Território','CC BY 4.0','https://geo2.dgterritorio.gov.pt/cos/S2/COS2018/COS2018v4-S2-gpkg.zip','2018',3763),
 ('cos1995','Carta de Uso e Ocupação do Solo 1995 v2 (Série 1 — outra nomenclatura; comparar só ao nível 1)','Direção-Geral do Território','CC BY 4.0','https://geo2.dgterritorio.gov.pt/cos/S1/COS1995/COS1995v2-S1-gpkg.zip','1995',3763),
 ('cop_dem30','Copernicus DEM GLO-30 — altitude e declive (%) reamostrados a 25 m; modelo de SUPERFÍCIE (copa e edifícios enviesam o declive)','ESA / Copernicus (Airbus)','Copernicus DEM licence: free use with attribution (GLO-30 public)','https://copernicus-dem-30m.s3.amazonaws.com/','2011–2015 (TanDEM-X acquisitions)',3763)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date;
-- row counts: id → table; a table that is not loaded is skipped (a plain UNION over missing tables fails to parse)
DO $$ DECLARE r record; n bigint; BEGIN
  FOR r IN SELECT * FROM (VALUES ('caop2025','caop_freguesias'), ('cos2023','cos2023'), ('icnf_perigosidade','icnf_perigosidade'),
      ('apa_perigo','apa_perigo_inundacao'), ('apa_zonas_inundaveis','apa_zonas_inundaveis'), ('apa_arpsi','apa_arpsi'),
      ('apa_marcas_cheia','apa_marcas_cheia'), ('ine_bgri2021','ine_bgri2021'), ('icnf_areas_ardidas','icnf_areas_ardidas'),
      ('icnf_areas_protegidas','icnf_areas_protegidas'), ('dgt_crus','dgt_crus'), ('ine_precos_habitacao','ine_precos_habitacao'),
      ('ipma_rcm','ipma_rcm_snapshot'), ('cop_dem30','dem_slope')) v(id, tbl) LOOP
    IF to_regclass('open.' || r.tbl) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM open.%I', r.tbl) INTO n;
      UPDATE open.dataset_meta SET row_count = n WHERE id = r.id;
    END IF;
  END LOOP;
END $$;
DO $$ BEGIN IF to_regclass('open.cos_serie') IS NOT NULL THEN
  UPDATE open.dataset_meta m SET row_count = c.n FROM (SELECT 'cos' || ano AS id, count(*) AS n FROM open.cos_serie GROUP BY ano) c WHERE c.id = m.id;
END IF; END $$;
SQL
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -f "$ROOT/data/views.sql"
psql "$PG_DSN" -c "SELECT id, row_count FROM open.dataset_meta ORDER BY id;" -c "SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;"
fi
echo "done"

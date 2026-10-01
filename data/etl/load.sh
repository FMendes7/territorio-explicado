#!/usr/bin/env bash
# data/etl/load.sh — load the downloaded datasets into PostGIS, clipped to the pilot regions (per region)
# What: runs data/schema.sql; loads CAOP nationally (freguesias + municípios); builds open.pilot_regions
#       from data/regioes.json (DICO codes cross-checked against CAOP names, fails loudly on mismatch);
#       then, REGION BY REGION (small bboxes → small downloads), loads COS2023, the fire-hazard WFS
#       (6 feature types, one per class), INE BGRI per municipality and APA flood layers; then ICNF burned
#       areas 1975–2025 and protected areas (RNAP + Natura 2000 ZEC/ZPE) from the ICNF GeoServer WFS, DGT CRUS
#       (PDM land-use classes) per municipality, INE median €/m² (parish/municipality, joined through BGRI
#       2021 parish codes) and a dated snapshot of IPMA's fire-risk forecast (RCM) per municipality; COS 1995/2018/
#       2025 (cos_serie); relief rasters (elevation, slope, aspect) from Copernicus GLO-30 (fallback) and from the DGT
#       LiDAR 2024 terrain model at 10 m (relevo_mdt, primary); DGT LiDAR 2024 building footprints; REN and RAN
#       (DGT SRUP WFS); the SRUP pack of easements for the Lisbon study area (stage srup, Tier 2); Tier 2 for the same area: IP rail and
#       national roads (stage ip), OpenStreetMap roads/rail, power lines, substations, schools/health/stations (stage osm, needs
#       data/etl/osmconf.ini), E-REDES substation hosting capacity/load and secondary substations (stage eredes, after osm),
#       APA drinking-water abstraction perimeters + groundwater bodies (stage apa_agua), TML schools and health centres of the
#       AML (stage equipamentos), Oeiras strategic noise map (stage ruido), LNEG areas of lower sensitivity for solar/wind
#       (stage lneg), Carris Metropolitana stops/route patterns and Metro de Lisboa stations/lines (stage transportes),
#       LNEG geological map 1:500 000 (stage geologia), DGEG solar plants (stage dgeg) and the EEA noise contours of the
#       END 2022 round (stage ruido_end); subdivided grid helpers;
#       a spatial QA; fills open.dataset_meta; applies data/views.sql.
#       Every vector layer goes through trim_to_regions(): features spanning several regions are split per region.
# Depends on: GDAL/OGR ≥ 3.6 (ogr2ogr/ogrinfo), psql, jq, unzip, curl, sha256sum; env PG_DSN (password via
#       PGPASSWORD/.pgpass, never on the command line); files from data/etl/download.sh in data/raw/;
#       network for the WFS/REST/API stages (apa, ardidas, protegidas, crus, ipma, ren_ran). Stage `precos` needs
#       stage `ine` loaded (parish geometry = union of BGRI subsections). REFRESH=1 re-downloads cached
#       WFS exports (data/raw/icnf_wfs, data/raw/crus, data/raw/srup, data/raw/dem) and the Tier-2 files (data/raw/ip, osm, eredes). Stage `relevo` also needs
#       gdalwarp/gdaldem/gdalbuildvrt, awk, the postgis_raster extension (created here; the server database needs it
#       BEFORE a dump restore) and either raster2pgsql or a superuser session (client-side load, see raster_load); stage
#       `relevo_mdt` needs data/raw/mdt2m/ from data/etl/download_mdt.sh (DGT data-centre account) and gdal_calc.py.
# Used by: one-off data preparation (pre-existing component, declared in PRE-EXISTING.md). Re-runnable.
# When changing: table/column names here are the contract read by open.facts_at() (schema.sql) and by
#       data/views.sql — caop_freguesias(dico,freguesia,concelho,distrito), cos2023(cos_label),
#       icnf_perigosidade(classe,classe_ord), apa_*(see schema.sql), ine_bgri2021(bgri2021,dtmnfr,n_individuos,
#       n_edificios), icnf_areas_ardidas(ano,area_ha,dh_inicio,causa_tipo), icnf_areas_protegidas(rede,categoria,
#       nome,codigo,diploma), dgt_crus(classe,categoria,designacao_pdm,escala,data_publicacao_pdm,esquema),
#       ine_precos_habitacao(nivel,codigo,nome,eur_m2,nota,periodo), ipma_rcm_snapshot(dico,data_prev,rcm,rcm_label),
#       cos_serie/v_cos_serie(ano,serie,cod_n4,label_n4,cod_n1), dem_elev/dem_slope/dem_aspect(rast: Int16 m / % / °
#       with -9999 = flat, 25 m), dem_mdt_elev/dem_mdt_slope/dem_mdt_aspect (same encoding, 10 m, DGT MDT),
#       dgt_construcoes(id,area_m2), dgt_ren(tipologia,diploma,dr,diploma_url,…), dgt_ren_linhas, dgt_ran;
#       grid_* (subdivided helpers read by constraints_grid — same columns as their sources). Tier-2 tables (dgt_srup*, ip_*,
#       osm_*, eredes_*, apa_perimetros_captacao, apa_massas_subterraneas, equip_*, ruido_mapas, lneg_*, tp_*,
#       dgeg_centrais_solares) are read by no function yet
#       (the site engine is window work): their columns are described in data/sources.md. Stage `qa` checks that
#       every trimmed geometry lies inside its tagged region (WARN only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; RAW="$ROOT/data/raw"
: "${PG_DSN:?set PG_DSN=postgresql://user@host:port/db (password via PGPASSWORD/.pgpass)}"
OGR_PG="PG:$PG_DSN"
ONLY="${ONLY:-caop cos icnf ine apa ardidas protegidas crus precos ipma cos_serie relevo relevo_mdt construcoes ren_ran srup ip osm eredes apa_agua equipamentos ruido lneg transportes geologia dgeg ruido_end grelha qa meta}"   # e.g. ONLY="cos meta" to re-run one stage
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
DROP TABLE IF EXISTS open.pilot_regions, open.pilot_union, open.pilot_region_union;   -- helpers are rebuilt from it by trim_to_regions
CREATE TABLE open.pilot_regions (region text, dico text, name_expected text);
\copy open.pilot_regions FROM '$RAW/regioes.tsv' WITH (FORMAT csv, DELIMITER E'\t')
ALTER TABLE open.pilot_regions ADD COLUMN concelho text, ADD COLUMN geom geometry(MultiPolygon, 3763);
UPDATE open.pilot_regions p SET concelho = m.concelho, geom = m.geom FROM open.caop_municipios m WHERE m.dico = p.dico;
CREATE INDEX ON open.pilot_regions USING GIST (geom);
CREATE TABLE open.pilot_union AS SELECT ST_Union(geom) AS geom, ST_Boundary(ST_Union(geom)) AS boundary FROM open.pilot_regions;
CREATE TABLE open.pilot_region_union AS SELECT region, ST_Union(geom) AS geom FROM open.pilot_regions GROUP BY region;
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
trim_to_regions() {  # TABLE [poly|line|point] [nodedupe] — keep what intersects a pilot region, dedupe, split multi-region features, trim, tag region
  # nodedupe (stage transportes, 2026-09-30): two transit patterns on the same street are two rows — skip the geometry-hash dedupe
  local kind="${2:-poly}" SPLIT_SQL="" TRIM_SQL="" KEEP="ST_Intersects(t.geom, p.geom)" CT=3 DEDUPE_SQL=""
  [ "$kind" = line ] && CT=2   # geometry type kept by ST_CollectionExtract after cutting: 3 polygons, 2 lines
  # points (flood marks) just outside a municipality are still proximity evidence → 2 km margin. Polygons use
  # ST_Intersects, NOT ST_DWithin(…, 0): same answer, but DWithin's distance code on the 409 706-vertex COS1995
  # polygon ran > 120 s per municipality vs 0.8 s for all 9 (measured 2026-09-27, docs/lessons.md)
  [ "$kind" = point ] && KEEP="ST_DWithin(t.geom, p.geom, 2000)"
  [ "${3:-}" = nodedupe ] || DEDUPE_SQL="ALTER TABLE open.$1 ADD COLUMN _h text;
UPDATE open.$1 SET _h = md5(ST_AsBinary(geom));
DELETE FROM open.$1 a USING (SELECT _h, min(ctid) AS keep FROM open.$1 GROUP BY _h HAVING count(*) > 1) d
  WHERE a._h = d._h AND a.ctid <> d.keep;
ALTER TABLE open.$1 DROP COLUMN _h;"
  if [ "$(psql "$PG_DSN" -Atc "select to_regclass('open.$1') is not null")" != "t" ]; then echo "   open.$1: (no features loaded)"; return; fi
  # Some sources store ONE multipolygon per class for a whole sheet or the country (COS 1995 level-1 "Territórios
  # artificializados", 22 parts from Lisbon to Braga; the COS road network; ICNF "sem perigosidade") → such a feature
  # touches several regions and a single region tag is wrong for most of it (central Lisbon's 1995 cover was tagged
  # Coimbra, 2026-09-27) → replace it by one copy per region, cut to that region. Columns are copied by name; the
  # primary key (fid from a GeoPackage, ogc_fid otherwise — ogr2ogr writes source FIDs WITHOUT advancing the sequence,
  # so nextval() collides) gets max(pk) + n.
  [ "$kind" != point ] && SPLIT_SQL="DO \$\$ DECLARE c text; pk text; BEGIN
  SELECT a.attname INTO pk FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
   WHERE i.indrelid = 'open.$1'::regclass AND i.indisprimary LIMIT 1;
  SELECT coalesce(string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) || ', ', '') INTO c
    FROM information_schema.columns WHERE table_schema = 'open' AND table_name = '$1'
     AND column_name NOT IN ('geom', 'region') AND column_name IS DISTINCT FROM pk;
  CREATE TEMP TABLE mr ON COMMIT DROP AS SELECT t.ctid AS tid FROM open.$1 t
    JOIN open.pilot_region_union r ON ST_Intersects(t.geom, r.geom) GROUP BY t.ctid HAVING count(*) > 1;
  IF pk IS NULL THEN
    EXECUTE format('INSERT INTO open.%I (%s region, geom) SELECT %s r.region, ST_Multi(ST_CollectionExtract(ST_Intersection(t.geom, r.geom), $CT))
      FROM open.%I t JOIN mr ON t.ctid = mr.tid JOIN open.pilot_region_union r ON ST_Intersects(t.geom, r.geom)', '$1', c, c, '$1');
  ELSE
    EXECUTE format('INSERT INTO open.%I (%I, %s region, geom) SELECT (SELECT max(%I) FROM open.%I) + row_number() OVER (), %s r.region,
        ST_Multi(ST_CollectionExtract(ST_Intersection(t.geom, r.geom), $CT))
      FROM open.%I t JOIN mr ON t.ctid = mr.tid JOIN open.pilot_region_union r ON ST_Intersects(t.geom, r.geom)', '$1', pk, c, pk, '$1', c, '$1');
  END IF;
  DELETE FROM open.$1 t USING mr WHERE t.ctid = mr.tid;
  RAISE NOTICE 'open.$1: % feature(s) spanning several regions split into one copy per region', (SELECT count(*) FROM mr);
END \$\$;"
  # Trim every feature NOT covered by its region (not only those touching the boundary: a multipolygon with a whole
  # island outside never touches it), cut by the union of ONLY the municipalities it touches (cheaper than the whole
  # pilot union); stage `qa` verifies the result. ST_Covers(region, feature), NOT ST_CoveredBy(feature, region): same
  # answer, but only ST_Covers uses PostGIS's prepared-geometry cache — on the 46 944-vertex lisboa_tejo region
  # ST_CoveredBy took 7.6 ms per building vs 0.02 ms (4 424-building sample, 0 differences; docs/lessons.md, 2026-09-30).
  [ "$kind" != point ] && TRIM_SQL="UPDATE open.$1 t SET geom = ST_Multi(ST_CollectionExtract(ST_Intersection(t.geom,
      (SELECT ST_Union(p.geom) FROM open.pilot_regions p WHERE ST_Intersects(p.geom, t.geom))), $CT))
  FROM open.pilot_region_union r WHERE ST_Intersects(t.geom, r.geom) AND NOT ST_Covers(r.geom, t.geom);
DELETE FROM open.$1 WHERE geom IS NULL OR ST_IsEmpty(geom);"
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
CREATE TABLE IF NOT EXISTS open.pilot_union AS
  SELECT ST_Union(geom) AS geom, ST_Boundary(ST_Union(geom)) AS boundary FROM open.pilot_regions;
CREATE TABLE IF NOT EXISTS open.pilot_region_union AS   -- one row per region: the prepared geometry for ST_Covers
  SELECT region, ST_Union(geom) AS geom FROM open.pilot_regions GROUP BY region;
DELETE FROM open.$1 t WHERE NOT EXISTS (SELECT 1 FROM open.pilot_regions p WHERE $KEEP);
-- the same source feature can arrive twice when its bbox touches two region bboxes → hash once, keep one copy
$DEDUPE_SQL
ALTER TABLE open.$1 DROP COLUMN IF EXISTS region;
ALTER TABLE open.$1 ADD COLUMN region text;
$SPLIT_SQL
$TRIM_SQL
UPDATE open.$1 t SET region = p.region FROM open.pilot_regions p WHERE t.region IS NULL AND ST_Intersects(t.geom, p.geom);
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
echo "== ICNF fire hazard — official SNIT zip (shapefile, 1.75 M polygons, EPSG:3763); complete and reproducible (the DGT WFS needs WFS 1.1.0, docs/lessons.md)"
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
  # -oo DOWNLOAD_SCHEMA=NO: the GML names its XSD (DescribeFeatureType on the DGT server); on 2026-09-30 that request hung
  # (0 bytes in 25 s) and GDAL waited ~2 min per municipality before falling back to reading the types from the data —
  # the fallback is now the rule (same trap as the SRUP pack, docs/lessons.md)
  # -lco PRECISION=NO: without the XSD, GDAL sizes each text field from the FIRST file read (Mealhada) and silently cut the
  # later ones on append (municipio varchar(8): "ESPOSENDE" → "ESPOSEND", 2026-09-30) → unsized text columns
  ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -nln open.dgt_crus_raw "${OGR_COMMON[@]}" -addfields -makevalid -oo DOWNLOAD_SCHEMA=NO \
    --config GDAL_HTTP_TIMEOUT 60 -lco PRECISION=NO || echo "WARN: CRUS $d load failed"
}
mkdir -p "$RAW/crus"
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.dgt_crus_raw;"
for d in $(psql "$PG_DSN" -Atc "SELECT dico FROM open.pilot_regions ORDER BY dico"); do crus_municipio "$d"; done
# Each plan stays inside ITS OWN municipality (CAOP 2025), before trimming: older PDMs were drawn on earlier boundaries and
# overlap the neighbour, so a point there got two PDM classes (measured 2026-09-30 before this fix: ≈ 2 050 ha in 26
# municipality-region pairs — Palmela 340 ha, Azambuja 233, Rio Maior 208, Chamusca 202, Alpiarça 201, Barreiro 179 …,
# Amadora 5.5 ha inside Lisboa). Same idea as the DICO filter of REN/RAN, done geometrically. A gap where CAOP 2025 reaches
# beyond the old plan stays a gap ("no PDM class"). area_ha stays the source attribute (area of the plan's polygon).
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
UPDATE open.dgt_crus_raw r SET geom = ST_Multi(ST_CollectionExtract(ST_Intersection(r.geom, m.geom), 3))
  FROM open.caop_municipios m WHERE m.dico = lpad(r.dtcc::text, 4, '0') AND NOT ST_Covers(m.geom, r.geom);
DELETE FROM open.dgt_crus_raw WHERE geom IS NULL OR ST_IsEmpty(geom);
SQL
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

# raster_load FILE TABLE — append 100×100 tiles to an existing (rid serial, rast raster) table: raster2pgsql when installed,
# else client-side through a large object (\lo_import → ST_FromGDALRaster → ST_Tile, padded with nodata), which needs no
# file access on the server and no extra binary — the postgis/postgis:16-3.4 image has NO raster2pgsql (checked
# 2026-09-27; the earlier `docker run … raster2pgsql` fallback never worked). Values checked equal to gdallocationinfo.
# Needs the session setting postgis.gdal_enabled_drivers (superuser on the local database; the server gets a dump).
# Used by: stages relevo (Copernicus) and relevo_mdt (DGT LiDAR MDT) — defined outside both so either runs alone.
raster_load() {
  if command -v raster2pgsql >/dev/null; then
    raster2pgsql -a -s 3763 -t 100x100 -N -32768 "$1" "$2" | psql "$PG_DSN" -q -v ON_ERROR_STOP=1 >/dev/null
  else
    psql "$PG_DSN" -q -v ON_ERROR_STOP=1 >/dev/null <<SQL
SET postgis.gdal_enabled_drivers = 'GTiff';
\lo_import '$1'
SELECT :LASTOID AS oid \gset
INSERT INTO $2 (rast) SELECT ST_Tile(ST_FromGDALRaster(lo_get(:oid), 3763), 100, 100, true, -32768);
SELECT lo_unlink(:oid);
SQL
  fi
}

if stage relevo; then
echo "== Relief — Copernicus DEM GLO-30 (public COGs, no login) → elevation + slope (%) at 25 m, EPSG:3763, as PostGIS rasters"
# GLO-30 is a SURFACE model (X-band radar): canopy and buildings bias slope in forests and towns → labelled in every
# fact. Since 2026-09-27 the DGT LiDAR 2024 terrain model (stage relevo_mdt) is the primary relief source; these tables stay
# as the fallback where the MDT has no value, so keep loading them.
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
  # 1 km margin so slope at the region edge sees its neighbours; tiles outside the pilot union are dropped after loading.
  # LC_ALL=C: under a pt_PT locale awk prints a decimal COMMA (-57552,1) and gdalwarp -te breaks (docs/lessons.md)
  gdalwarp -q -overwrite -t_srs EPSG:3763 -tr 25 25 -tap -r bilinear -te $(LC_ALL=C awk -v a="$X0" -v b="$Y0" -v c="$X1" -v d="$Y1" 'BEGIN{print a-1000, b-1000, c+1000, d+1000}') \
    -ot Float32 "$RAW/dem/cop30.vrt" "$RAW/dem/elev_$R.tif"
  gdaldem slope -q -p -compute_edges "$RAW/dem/elev_$R.tif" "$RAW/dem/slope_$R.tif"
  # aspect: degrees clockwise from north (0–360); gdaldem writes -9999 where the slope is exactly 0 (flat, no aspect) —
  # kept as a value (-9999 = flat), while -32768 stays nodata. Solar PV and farming read it (docs/lessons.md)
  gdaldem aspect -q -compute_edges "$RAW/dem/elev_$R.tif" "$RAW/dem/aspect_$R.tif"
  for V in elev slope aspect; do gdal_translate -q -ot Int16 -a_nodata -32768 "$RAW/dem/${V}_$R.tif" "$RAW/dem/${V}_${R}_i16.tif"; done
done
for V in elev slope aspect; do
  psql "$PG_DSN" -q -v ON_ERROR_STOP=1 -c "DROP TABLE IF EXISTS open.dem_$V;" -c "CREATE TABLE open.dem_$V (rid serial PRIMARY KEY, rast raster);"
  for R in $REGIONS; do raster_load "$RAW/dem/${V}_${R}_i16.tif" "open.dem_$V"; done
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
DELETE FROM open.dem_$V d WHERE NOT EXISTS (SELECT 1 FROM open.pilot_regions p WHERE ST_Intersects(p.geom, ST_Envelope(d.rast)));
CREATE INDEX ON open.dem_$V USING GIST (ST_ConvexHull(rast));
VACUUM ANALYZE open.dem_$V;
SQL
done
psql "$PG_DSN" -c "SELECT 'dem_' || v AS t, (xpath('/row/n/text()', query_to_xml('select count(*) n from open.dem_' || v, false, true, '')))[1]::text AS tiles,
  pg_size_pretty(pg_total_relation_size(('open.dem_' || v)::regclass)) AS size FROM unnest(ARRAY['elev','slope','aspect']) v;"
fi

if stage relevo_mdt; then
echo "== Relief — DGT LiDAR 2024 terrain model (MDT 2 m, data/etl/download_mdt.sh) → elevation / slope (%) / aspect at 10 m"
# TERRAIN model: buildings and canopy removed, so slope and aspect are the ground's (the Copernicus surface model is
# biased under forest and in towns). 2 m → 10 m by AVERAGING the elevation (-r average skips the −999 nodata), then
# slope and aspect on the 10 m model: the general slope of the ground, not the micro-relief of walls and terraces
# (docs/decisions.md, 2026-09-27: 2 m does not fit the 2.5 GB server budget). The 2 m tiles stay on the laptop
# (data/raw/mdt2m, 6.5 GB, never in the database). Copernicus (stage relevo) stays loaded as the fallback where the MDT
# has no value (sea, Spain, gaps) — the SQL functions read dem_mdt_* first. gdaldem writes −9999 both for "no data"
# and, in aspect, for "flat", so the nodata mask comes from the 10 m elevation (gdal_calc), never from −9999.
MDT="$RAW/mdt2m"
if [ ! -s "$MDT/tiles.tsv" ] || ! compgen -G "$MDT/*.tif" >/dev/null; then
  echo "WARN: no MDT tiles in $MDT — run data/etl/download_mdt.sh; Copernicus stays the only relief source"
else
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "CREATE EXTENSION IF NOT EXISTS postgis_raster;"
for R in $REGIONS; do
  while IFS=$'\t' read -r id _ _ r; do [ "$r" = "$R" ] && [ -s "$MDT/$id.tif" ] && echo "$MDT/$id.tif"; done < "$MDT/tiles.tsv" > "$MDT/files_$R.txt"
  echo "   $R: $(wc -l < "$MDT/files_$R.txt") of $(awk -F'\t' -v r="$R" '$4 == r' "$MDT/tiles.tsv" | wc -l) tiles on disk"
  [ -s "$MDT/files_$R.txt" ] || continue
  gdalbuildvrt -q -overwrite -input_file_list "$MDT/files_$R.txt" "$MDT/mdt2m_$R.vrt"
  read -r X0 Y0 X1 Y1 <<< "$(bbox3763 "$R")"
  # LC_ALL=C: a pt_PT awk prints decimal commas and breaks -te (docs/lessons.md); 200 m margin (tiles reach ≥ 100 m out)
  gdalwarp -q -overwrite -tr 10 10 -tap -r average -srcnodata -999 -dstnodata -32768 -ot Float32 -multi -wo NUM_THREADS=ALL_CPUS \
    -te $(LC_ALL=C awk -v a="$X0" -v b="$Y0" -v c="$X1" -v d="$Y1" 'BEGIN{print a-200, b-200, c+200, d+200}') \
    -co COMPRESS=DEFLATE -co TILED=YES "$MDT/mdt2m_$R.vrt" "$MDT/elev10_$R.tif"
  gdaldem slope -q -p -compute_edges -co COMPRESS=DEFLATE "$MDT/elev10_$R.tif" "$MDT/slope10_$R.tif"
  gdaldem aspect -q -compute_edges -co COMPRESS=DEFLATE "$MDT/elev10_$R.tif" "$MDT/aspect10_$R.tif"
  # TILED=YES on the Int16 files: gdal_calc works block by block of A (256×256 tiles) and, into a striped DEFLATE GeoTIFF,
  # rewrote each strip once per block column, appending a new compressed copy each time — aspect for lisboa_tejo came
  # out at 1.66 GB (286 MB raw) and broke raster_load's lo_get (1 GB limit), 2026-09-30 (docs/lessons.md)
  gdal_translate -q -ot Int16 -a_nodata -32768 -co COMPRESS=DEFLATE -co TILED=YES "$MDT/elev10_$R.tif" "$MDT/elev_${R}_i16.tif"
  for V in slope aspect; do
    LC_ALL=C gdal_calc.py --quiet --hideNoData -A "$MDT/elev10_$R.tif" -B "$MDT/${V}10_$R.tif" --type=Int16 --NoDataValue=-32768 \
      --calc="numpy.where(A == -32768, -32768, numpy.rint(B))" --co COMPRESS=DEFLATE --co TILED=YES --overwrite --outfile "$MDT/${V}_${R}_i16.tif"
  done
done
for V in elev slope aspect; do
  psql "$PG_DSN" -q -v ON_ERROR_STOP=1 -c "DROP TABLE IF EXISTS open.dem_mdt_$V;" -c "CREATE TABLE open.dem_mdt_$V (rid serial PRIMARY KEY, rast raster);"
  for R in $REGIONS; do [ -s "$MDT/${V}_${R}_i16.tif" ] && raster_load "$MDT/${V}_${R}_i16.tif" "open.dem_mdt_$V"; done
  # tiles that are all nodata (sea, Spain, outside the downloaded tiles) or away from the pilot union carry nothing
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<SQL
DELETE FROM open.dem_mdt_$V WHERE ST_BandIsNoData(rast, 1, true);
DELETE FROM open.dem_mdt_$V d WHERE NOT EXISTS (SELECT 1 FROM open.pilot_regions p WHERE ST_Intersects(p.geom, ST_Envelope(d.rast)));
CREATE INDEX ON open.dem_mdt_$V USING GIST (ST_ConvexHull(rast));
VACUUM ANALYZE open.dem_mdt_$V;
SQL
done
psql "$PG_DSN" -c "SELECT 'dem_mdt_' || v AS t, (xpath('/row/n/text()', query_to_xml('select count(*) n from open.dem_mdt_' || v, false, true, '')))[1]::text AS tiles,
  pg_size_pretty(pg_total_relation_size(('open.dem_mdt_' || v)::regclass)) AS size FROM unnest(ARRAY['elev','slope','aspect']) v;"
fi
fi

if stage construcoes && [ -f "$RAW/mconst_lidar2024.zip" ] && unzip -Z1 "$RAW/mconst_lidar2024.zip" >/dev/null 2>&1; then
echo "== DGT Mapa de Construções LiDAR 2024 — building footprints (4.17 M nationally; fields id, area_m2), per region"
# From the 2024 national LiDAR flight: footprints only (no height, no use, no date per building). Read from the EXTRACTED
# gpkg (1.76 GB, R-tree) — same reason as COS2023. The zip's second gpkg (…_secciona) is the sheet index, not buildings.
MC_GPKG=$(unzip -Z1 "$RAW/mconst_lidar2024.zip" | grep -i "\.gpkg$" | grep -vi secciona | head -1)
[ -f "$RAW/$MC_GPKG" ] || unzip -o -q "$RAW/mconst_lidar2024.zip" "$MC_GPKG" -d "$RAW"
MC_LAYER=$(ogrinfo -ro -so "$RAW/$MC_GPKG" | sed -n 's/^1: \([^ ]*\).*/\1/p')
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.dgt_construcoes_raw;"
load_clipped mconst_lidar2024 "$RAW/$MC_GPKG" dgt_construcoes_raw "$MC_LAYER"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.dgt_construcoes;
-- area_m2 = the footprint as published (a footprint cut at the pilot boundary keeps its published area)
CREATE TABLE open.dgt_construcoes AS SELECT id::text AS id, round(area_m2::numeric, 1) AS area_m2, region, geom FROM open.dgt_construcoes_raw;
CREATE INDEX ON open.dgt_construcoes USING GIST (geom);
DROP TABLE open.dgt_construcoes_raw;
VACUUM ANALYZE open.dgt_construcoes;
SQL
psql "$PG_DSN" -c "SELECT region, count(*) AS buildings, round((sum(ST_Area(geom)) / 1e6)::numeric, 2) AS footprint_km2 FROM open.dgt_construcoes GROUP BY 1 ORDER BY 1;" \
  -c "SELECT pg_size_pretty(pg_total_relation_size('open.dgt_construcoes')) AS dgt_construcoes_size;"
fi

# SRUP WFS helpers — defined outside the stages: used by stages ren_ran and srup.
# srup_wfs SERVICE TYPENAME TABLE — DGT GeoMedia WFS: use WFS **1.1.0** with bbox=…,EPSG:3763. The same servers reject the
# WFS 2.0.0 CRS form urn:ogc:def:crs:EPSG::3763 with "GetCSFForEPSG: Invalid inputs" (2026-09-27) — which is also what
# made the SRUP fire-hazard WFS look broken (docs/lessons.md). One feature = a municipality's whole REN (or its
# exclusions) / RAN → large multipolygons; GML cached in data/raw/srup (REFRESH=1 re-fetches). Caller drops TABLE first.
# srup_wfs SERVICE TYPENAME TABLE [REGIONS] — REGIONS defaults to all pilot regions (stage srup passes the study area).
# -forceNullable: some SRUP features have no gml:id and a NOT NULL gml_id column made the COPY fail (radio-beam zones, 2026-09-30).
# SRUP_OGR_OPTS: extra ogr2ogr options (stage srup: do not download the XSD — the GML reader fetched it from the server,
# which answered 502, and GDAL waited with no HTTP timeout; 2026-09-30).
# srup_fetch URL FILE LABEL MANIFEST_ID — one GetFeature response on disk (cached, or fetched now and recorded in the
# manifest); returns 1 with a WARN when the server answers anything but a FeatureCollection (HTML error pages, 503).
# Depends on: cached, manifest_add, curl. Used by: srup_wfs (REN, REN lines, RAN). Changing the return code changes
# when srup_wfs falls back to one request per municipality.
srup_fetch() {
  local url="$1" f="$2" label="$3"
  cached "$f" && return 0
  curl -sS -m 1800 --retry 2 -o "$f" "$url" || { echo "WARN: $label download failed"; rm -f "$f"; return 1; }
  grep -q 'FeatureCollection' "$f" || { echo "WARN: $label no FeatureCollection: $(head -c 200 "$f")"; rm -f "$f"; return 1; }
  manifest_add "$4" "$url" "$f"
}
srup_wfs() {
  local svc="$1" typ="$2" tbl="$3" regs="${4:-$REGIONS}" R f n d base files
  mkdir -p "$RAW/srup"
  # SRUP type names carry accents ("Áreas_Abrangidas_pela_Servidão") → URL-encoded
  base="https://servicos.dgterritorio.pt/SDISNITWFS$svc/WFService.aspx?service=WFS&version=1.1.0&request=GetFeature&typeName=gmgml:$(jq -rn --arg s "$typ" '$s|@uri')&bbox="
  for R in $regs; do
    # A whole-region request can fail on a large region: REN_LVT over lisboa_tejo (120 × 119 km) returned an HTML error
    # page after ~10 min (2026-09-30) → then one request per municipality bbox (files <typ>_<region>__m<DICO>.gml, cached;
    # once one exists the region request is not tried again, and a municipality that failed is retried on the next run);
    # a neighbour fetched twice is removed by the hash dedupe in trim_to_regions and by the DICO filter.
    files=()
    if ! compgen -G "$RAW/srup/${typ}_${R}__m*.gml" >/dev/null \
       && srup_fetch "$base$(bbox3763 "$R" | tr ' ' ','),EPSG:3763" "$RAW/srup/${typ}_$R.gml" "$typ [$R]" "dgt_${typ}_$R"; then
      files=("$RAW/srup/${typ}_$R.gml")
    else
      echo "   $typ [$R]: one request per municipality"
      for d in $(psql "$PG_DSN" -Atc "SELECT dico FROM open.pilot_regions WHERE region = '$R' ORDER BY 1"); do
        f="$RAW/srup/${typ}_${R}__m$d.gml"
        srup_fetch "$base$(psql "$PG_DSN" -Atc "SELECT ST_XMin(e)||','||ST_YMin(e)||','||ST_XMax(e)||','||ST_YMax(e) FROM (SELECT ST_Extent(geom) e FROM open.pilot_regions WHERE dico = '$d') s"),EPSG:3763" \
          "$f" "$typ [$R/$d]" "dgt_${typ}_${R}_$d" && files+=("$f")
      done
    fi
    for f in "${files[@]}"; do
      # `|| true`: a failed grep inside $(…) would trip set -e -o pipefail (docs/lessons.md, Mortágua)
      n=$(grep -o 'numberOfFeatures="[0-9]*"' "$f" | head -1 | tr -dc '0-9' || true); echo "   $typ → open.$tbl [$(basename "$f" .gml | sed "s/^${typ}_//")] ${n:-?} features"
      [ "${n:-0}" -gt 0 ] || continue
      # -lco PRECISION=NO: text fields unsized — with the types read from the data (no XSD) the first file's widths cut the
      # next file on append (SRUP lisboa_tejo: DESIGNACAO 149 → 126 chars, SERV_HIPERLINK 67 → 65 = broken diploma links, 2026-09-30)
      ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -nln "open.$tbl" "${OGR_COMMON[@]}" -addfields -makevalid -forceNullable -lco PRECISION=NO ${SRUP_OGR_OPTS:-} \
        || echo "WARN: $typ [$R] load failed"
    done
  done
}

# Tier-2 helpers (Lisbon study area; OK 2026-09-30) — defined outside the stages: used by stages srup, ip, osm, eredes.
# T2_REGIONS: the regions Tier 2 was agreed for. t2_bbox SRID → "xmin ymin xmax ymax" of their union's extent in that SRID
# (for ogr2ogr -spat … -spat_srs EPSG:<SRID>). keep_study_area TABLE [REGIONS] deletes rows tagged with another region:
# trim_to_regions keeps whatever touches ANY pilot region, so a long source feature (a river, a national road) reaching
# a pilot region outside the study area would otherwise stay there (the Tejo "rio de 1.ª ordem" SRUP polygon left 17 ha
# tagged coimbra in Pampilhosa da Serra, 2026-09-30).
# fetch_file URL FILE MANIFEST_ID — one file on disk: reused when cached (REFRESH=1 re-fetches), else downloaded now
# (IPv4: download.geofabrik.de's IPv6 address did not answer from the laptop, 2026-09-30); the manifest row is written when
# the file is fetched, or when a cached file has none yet (files fetched by hand before the stage existed). Returns 1 with a
# WARN on a failed or empty download.
# Depends on: cached, manifest_add, curl, open.pilot_regions. Ao mexer: T2_REGIONS also scopes the dataset_meta wording
# ("Lisbon study area") in sources.md — change both together.
T2_REGIONS="${T2_REGIONS:-lisboa lisboa_tejo}"
t2_sql() { printf "'%s'," ${1:-$T2_REGIONS} | sed 's/,$//'; }
t2_bbox() {
  psql "$PG_DSN" -Atc "SELECT ST_XMin(e)||' '||ST_YMin(e)||' '||ST_XMax(e)||' '||ST_YMax(e) FROM (SELECT ST_Extent(ST_Transform(geom, $1)) e FROM open.pilot_regions WHERE region IN ($(t2_sql))) s"
}
keep_study_area() {
  local n
  n=$(psql "$PG_DSN" -v ON_ERROR_STOP=1 -Atc "WITH d AS (DELETE FROM open.$1 WHERE region IS NULL OR region NOT IN ($(t2_sql "${2:-}")) RETURNING 1) SELECT count(*) FROM d")
  echo "   open.$1: $n row(s) outside the study area removed"
}
# tag_points TABLE — point layers that must NOT go through trim_to_regions' geometry-hash dedupe (two installations or two
# schools at the same coordinates are two rows): keeps points within 2 km of the study area (proximity evidence, like the
# flood marks), region by containment, else the nearest study-area region. Used by: stages eredes (PTD), equipamentos.
tag_points() {
  psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -v t2="$(t2_sql)" <<SQL
DELETE FROM open.$1 t WHERE NOT EXISTS (SELECT 1 FROM open.pilot_regions p WHERE p.region IN (:t2) AND ST_DWithin(t.geom, p.geom, 2000));
ALTER TABLE open.$1 DROP COLUMN IF EXISTS region;
ALTER TABLE open.$1 ADD COLUMN region text;
UPDATE open.$1 t SET region = p.region FROM open.pilot_regions p WHERE p.region IN (:t2) AND ST_Intersects(t.geom, p.geom);
UPDATE open.$1 t SET region = (SELECT p.region FROM open.pilot_regions p WHERE p.region IN (:t2) ORDER BY t.geom <-> p.geom LIMIT 1)
  WHERE region IS NULL;
VACUUM ANALYZE open.$1;
SQL
  psql "$PG_DSN" -Atc "SELECT '   open.$1: ' || count(*) || ' points, ' || pg_size_pretty(pg_total_relation_size('open.$1')) FROM open.$1"
}
fetch_file() {
  local url="$1" f="$2" id="$3"
  if ! cached "$f"; then
    { curl -4 -sS -L -m 3600 --retry 2 -o "$f.part" "$url" && [ -s "$f.part" ]; } || { echo "WARN: $id download failed"; rm -f "$f.part"; return 1; }
    mv "$f.part" "$f"; manifest_add "$id" "$url" "$f"
  elif ! awk -F'\t' -v id="$id" '$1 == id { found = 1 } END { exit !found }' "$RAW/MANIFEST.tsv" 2>/dev/null; then
    manifest_add "$id" "$url" "$f"
  fi
}

if stage ren_ran; then
echo "== DGT SRUP — Reserva Ecológica Nacional (one WFS per CCDR) + Reserva Agrícola Nacional (national WFS)"
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.dgt_ren_raw, open.dgt_ran_raw, open.dgt_ren_linhas_raw;"
# one service per CCDR: Vendas Novas (0712, study area lisboa_tejo) is CCDR Alentejo, not LVT (2026-09-30)
for s in "SRUP_REN_NORTE|Norte" "SRUP_REN_CENTRO|Centro" "SRUP_REN_LVT|LVT" "SRUP_REN_ALENTEJO|Alentejo"; do IFS='|' read -r S C <<< "$s"
  srup_wfs "$S" "REN_$C" dgt_ren_raw
  # REN watercourse lines ("Linhas de Água"): one multiline per municipality, published only where the delimitation
  # already separates them (2026-09-27: Soure yes, Montemor-o-Velho no) → "not published" must stay distinguishable
  srup_wfs "$S" "Linhas_de_Agua_$C" dgt_ren_linhas_raw
done
srup_wfs SRUP_RAN_PT1 RAN dgt_ran_raw
# Keep only the pilot municipalities' OWN REN/RAN before trimming: a neighbour's REN touches the shared border and would
# leave slivers labelled with the wrong municipality. REN has the DICO (DTCC); RAN only the name, in capitals.
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$ BEGIN
  IF to_regclass('open.dgt_ren_raw') IS NOT NULL THEN
    DELETE FROM open.dgt_ren_raw WHERE lpad(dtcc::text, 4, '0') NOT IN (SELECT dico FROM open.pilot_regions);
  END IF;
  IF to_regclass('open.dgt_ren_linhas_raw') IS NOT NULL THEN
    DELETE FROM open.dgt_ren_linhas_raw WHERE lpad(dtcc::text, 4, '0') NOT IN (SELECT dico FROM open.pilot_regions);
  END IF;
  IF to_regclass('open.dgt_ran_raw') IS NOT NULL THEN
    DELETE FROM open.dgt_ran_raw r WHERE NOT EXISTS (SELECT 1 FROM open.pilot_regions p
      WHERE translate(upper(p.concelho), 'ÁÀÂÃÉÊÍÓÔÕÚÇ', 'AAAAEEIOOOUC') = translate(upper(r.concelho), 'ÁÀÂÃÉÊÍÓÔÕÚÇ', 'AAAAEEIOOOUC'));
  END IF;
END $$;
SQL
trim_to_regions dgt_ren_raw; trim_to_regions dgt_ran_raw; trim_to_regions dgt_ren_linhas_raw line
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.dgt_ren, open.dgt_ran, open.dgt_ren_linhas;
CREATE TABLE open.dgt_ren_linhas (dico text, concelho text, tipologia text, dinamica text, estado text, region text,
  geom geometry(MultiLineString, 3763));
CREATE TABLE open.dgt_ren (dico text, concelho text, tipologia text, dinamica text, designacao text, diploma text, dr text,
  diploma_url text, tutela text, escala text, data_geometria text, deposito text, area_ha_total numeric, region text,
  geom geometry(MultiPolygon, 3763));
CREATE TABLE open.dgt_ran (dico text, concelho text, dinamica text, escala text, data_geometria text, region text,
  geom geometry(MultiPolygon, 3763));
DO $$ DECLARE din text; BEGIN
  IF to_regclass('open.dgt_ren_raw') IS NOT NULL THEN
    -- tipologia 'Exclusões' = areas taken OUT of the REN by the municipal delimitation (not a constraint — say so);
    -- the diploma PDF link has spaces in its path → %20 (checked: HTTP 200, application/pdf)
    INSERT INTO open.dgt_ren SELECT lpad(dtcc::text, 4, '0'), concelho, tipologia, dinamica, designacao, serv_lei, serv_dr,
      replace(serv_hiperlink, ' ', '%20'), tutela, geometria_rigor, left(geometria_data::text, 10), deposito,
      round(area_ha::numeric, 2), region, geom FROM open.dgt_ren_raw;
  END IF;
  IF to_regclass('open.dgt_ren_linhas_raw') IS NOT NULL THEN
    INSERT INTO open.dgt_ren_linhas SELECT lpad(dtcc::text, 4, '0'), concelho, tipologia, dinamica, estado, region, geom
      FROM open.dgt_ren_linhas_raw;
  END IF;
  IF to_regclass('open.dgt_ran_raw') IS NOT NULL THEN
    -- GML field DINÂMICA keeps its accent after laundering → look the column up instead of spelling it
    SELECT column_name INTO din FROM information_schema.columns
     WHERE table_schema = 'open' AND table_name = 'dgt_ran_raw' AND column_name ~ '^din' LIMIT 1;
    EXECUTE format($q$INSERT INTO open.dgt_ran SELECT p.dico, r.concelho, r.%I::text, r.rigor, left(r.data::text, 10), r.region, r.geom
      FROM open.dgt_ran_raw r LEFT JOIN open.pilot_regions p
        ON translate(upper(p.concelho), 'ÁÀÂÃÉÊÍÓÔÕÚÇ', 'AAAAEEIOOOUC') = translate(upper(r.concelho), 'ÁÀÂÃÉÊÍÓÔÕÚÇ', 'AAAAEEIOOOUC')$q$, din);
  END IF;
END $$;
CREATE INDEX ON open.dgt_ren USING GIST (geom);
CREATE INDEX ON open.dgt_ran USING GIST (geom);
CREATE INDEX ON open.dgt_ren_linhas USING GIST (geom);
DROP TABLE IF EXISTS open.dgt_ren_raw, open.dgt_ran_raw, open.dgt_ren_linhas_raw;
VACUUM ANALYZE open.dgt_ren_linhas;
VACUUM ANALYZE open.dgt_ren;
VACUUM ANALYZE open.dgt_ran;
SQL
# which pilot municipalities have REN / RAN at all (a missing one must be reported as "not available", never as "none")
psql "$PG_DSN" -c "SELECT p.region, p.concelho, (SELECT string_agg(DISTINCT r.tipologia, ' + ') FROM open.dgt_ren r WHERE r.dico = p.dico) AS ren,
  (SELECT round((sum(ST_Length(l.geom)) / 1000)::numeric) FROM open.dgt_ren_linhas l WHERE l.dico = p.dico) AS ren_lines_km,
  (SELECT count(*) FROM open.dgt_ran a WHERE a.dico = p.dico) AS ran_features FROM open.pilot_regions p ORDER BY 1, 2;"
fi

if stage srup; then
echo "== DGT SRUP pack — servidões e restrições de utilidade pública (Tier 2, Lisbon study area only)"
# One WFS per SRUP family (service codes from the dados.gov.pt records srup-*, all CC BY 4.0, read 2026-09-30); the
# feature types are read from GetCapabilities at run time. Each type goes through srup_wfs (cache, per-municipality
# fallback) into a scratch table, then into open.dgt_srup_raw with its family, type and ALL its attributes as jsonb (the
# fields differ per type; the window's functions read them), split by dimension into polygons / lines / points and
# trimmed like every layer. Left out: Espécies Agrícolas e Florestais (licence "not specified" on dados.gov.pt), Marcos
# Geodésicos (no feature type), and the SRUP REN/RAN/ZPE/ZEC/fire hazard (loaded from their own stages). Scope:
# SRUP_REGIONS (Tier 2 was agreed for the Lisbon study area, 2026-09-30); dataset_meta gets one row per family.
SRUP_REGIONS="${SRUP_REGIONS:-lisboa lisboa_tejo}"
# read by srup_wfs. GML_FIELDTYPES=ALWAYS_STRING + WRITE_GFS=NO: without the XSD, GDAL guessed each field's type from the FIRST
# file of a type and converted the next one with loss (z_desobstrucao_m 34.5 → 34, area_ha 50.0013 → 50, codigo_ccdr "3, 4" → 3;
# 19 + 26 warnings, 2026-09-30) → every attribute is kept as the published text; the .gfs sidecar would pin the guessed types,
# so none is written (and none may sit next to the cached GML).
SRUP_OGR_OPTS="-oo DOWNLOAD_SCHEMA=NO -oo WRITE_GFS=NO --config GDAL_HTTP_TIMEOUT 60 --config GML_FIELDTYPES ALWAYS_STRING"
SRUP_FAMILIES="${SRUP_FAMILIES:-AA DN IC EIP AIP DPH CASAP GO RF OAH TC IPE RG AAPC EPTM IA}"
# Feature types per family: GetCapabilities, cached in data/raw/srup/_capabilities/ (REFRESH=1 re-fetches). When the DGT does
# not answer and there is no cached copy (2026-09-30 evening: 0 bytes in 40 s), the types already in the loaded tables are used
# — the list of the last successful run, minus the types with no feature in the study area (they add no row) — with a WARN.
mkdir -p "$RAW/srup/_capabilities"
SRUP_KNOWN=$(psql "$PG_DSN" -Atc "SELECT CASE WHEN to_regclass('open.dgt_srup') IS NULL THEN '' ELSE
  (SELECT string_agg(DISTINCT familia || '|' || tipo, E'\n') FROM (SELECT familia, tipo FROM open.dgt_srup UNION ALL
   SELECT familia, tipo FROM open.dgt_srup_linhas UNION ALL SELECT familia, tipo FROM open.dgt_srup_pontos) u) END" 2>/dev/null || true)
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "DROP TABLE IF EXISTS open.dgt_srup_raw, open._srup_tmp;" \
  -c "CREATE TABLE open.dgt_srup_raw (familia text, tipo text, attrs jsonb, geom geometry(Geometry, 3763));"
for F in $SRUP_FAMILIES; do
  svc="SRUP_${F}_PT1"
  capf="$RAW/srup/_capabilities/$svc.xml"
  # after one failed request the other families skip the network (SRUP_OFFLINE): 16 × (120 s × 3 tries) of waiting otherwise
  if ! cached "$capf" && [ -z "${SRUP_OFFLINE:-}" ]; then
    { curl -4 -sS -m 120 --retry 2 -o "$capf.part" "https://servicos.dgterritorio.pt/SDISNITWFS$svc/WFService.aspx?service=WFS&version=1.1.0&request=GetCapabilities" \
      && grep -q 'gmgml:' "$capf.part" && mv "$capf.part" "$capf"; } || { rm -f "$capf.part"; SRUP_OFFLINE=1; }
  fi
  types=$( { [ -s "$capf" ] && grep -o -E '<(wfs:)?Name>gmgml:[^<]+</(wfs:)?Name>' "$capf" | sed -E 's/<[^>]+>//g; s/^gmgml://'; } || true)
  if [ -z "$types" ]; then
    types=$(printf '%s\n' "$SRUP_KNOWN" | awk -F'|' -v f="$F" '$1 == f { sub(/^[^|]*\|/, ""); print }')
    [ -n "$types" ] || { echo "WARN: $svc: no feature types (GetCapabilities failed, nothing loaded before)"; continue; }
    echo "WARN: $svc: GetCapabilities failed — using the $(printf '%s\n' "$types" | wc -l) type(s) already loaded for $F"
  fi
  while IFS= read -r typ; do
    psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open._srup_tmp;"
    srup_wfs "$svc" "$typ" _srup_tmp "$SRUP_REGIONS"
    psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -v fam="$F" -v typ="$typ" <<'SQL'
SELECT to_regclass('open._srup_tmp') IS NOT NULL AS has_tmp \gset
\if :has_tmp
-- attributes → jsonb from a LATERAL row of the NON-geometry columns: to_jsonb(whole row) turns the geometry into GeoJSON,
-- which fails on the curved GML geometries of the classified-heritage layer (2026-09-30); geometry linearised apart
SELECT set_config('srup.fam', :'fam', false) AS f, set_config('srup.typ', :'typ', false) AS t \gset
DO $$ DECLARE cols text; BEGIN
  SELECT string_agg(format('t.%I', column_name), ', ' ORDER BY ordinal_position) INTO cols FROM information_schema.columns
   WHERE table_schema = 'open' AND table_name = '_srup_tmp' AND column_name NOT IN ('geom', 'ogc_fid', 'gml_id');
  EXECUTE format('INSERT INTO open.dgt_srup_raw SELECT %L, %L, %s, ST_CurveToLine(t.geom) FROM open._srup_tmp t%s',
    current_setting('srup.fam'), current_setting('srup.typ'),
    CASE WHEN cols IS NULL THEN '''{}''::jsonb' ELSE 'to_jsonb(r)' END,
    CASE WHEN cols IS NULL THEN '' ELSE ', LATERAL (SELECT ' || cols || ') r' END);
END $$;
DROP TABLE open._srup_tmp;
\endif
SQL
  done <<< "$types"
done
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.dgt_srup_pol, open.dgt_srup_lin, open.dgt_srup_pt;
CREATE TABLE open.dgt_srup_pol AS SELECT familia, tipo, attrs, ST_Multi(ST_CollectionExtract(geom, 3))::geometry(MultiPolygon, 3763) AS geom
  FROM open.dgt_srup_raw WHERE ST_Dimension(geom) = 2;
CREATE TABLE open.dgt_srup_lin AS SELECT familia, tipo, attrs, ST_Multi(ST_CollectionExtract(geom, 2))::geometry(MultiLineString, 3763) AS geom
  FROM open.dgt_srup_raw WHERE ST_Dimension(geom) = 1;
CREATE TABLE open.dgt_srup_pt AS SELECT familia, tipo, attrs, ST_Multi(ST_CollectionExtract(geom, 1))::geometry(MultiPoint, 3763) AS geom
  FROM open.dgt_srup_raw WHERE ST_Dimension(geom) = 0;
CREATE INDEX ON open.dgt_srup_pol USING GIST (geom); CREATE INDEX ON open.dgt_srup_lin USING GIST (geom); CREATE INDEX ON open.dgt_srup_pt USING GIST (geom);
SQL
trim_to_regions dgt_srup_pol; trim_to_regions dgt_srup_lin line; trim_to_regions dgt_srup_pt point
for t in dgt_srup_pol dgt_srup_lin dgt_srup_pt; do keep_study_area "$t" "$SRUP_REGIONS"; done
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.dgt_srup, open.dgt_srup_linhas, open.dgt_srup_pontos;
ALTER TABLE open.dgt_srup_pol RENAME TO dgt_srup;
ALTER TABLE open.dgt_srup_lin RENAME TO dgt_srup_linhas;
ALTER TABLE open.dgt_srup_pt RENAME TO dgt_srup_pontos;
DROP TABLE open.dgt_srup_raw;
-- one provenance row per family (ids as in data/site_profiles.json where the profiles use them)
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid)
SELECT v.id, v.title, 'Direção-Geral do Território (SNIT) — SRUP', 'CC BY 4.0 (dados.gov.pt ' || v.slug || ')',
  'https://servicos.dgterritorio.pt/SDISNITWFSSRUP_' || v.fam || '_PT1/WFService.aspx', 'em vigor (WFS, retrieved ' || current_date || ')', 3763
FROM (VALUES
 ('AA','srup_aeroportos','Servidões aeronáuticas — aeroportos e aeródromos, radiofaróis (SRUP)','srup-aeroportos-e-aerodromos'),
 ('DN','srup_defesa','Servidões militares — defesa nacional (SRUP)','srup-defesa-nacional'),
 ('IC','srup_imoveis_classificados','Imóveis classificados e zonas de proteção (SRUP)','srup-imoveis-classificados'),
 ('EIP','srup_edificios_interesse_publico','Edifícios de interesse público (SRUP)','srup-edificios-de-interesse-publico'),
 ('AIP','srup_arvores_interesse_publico','Árvores e conjuntos arbóreos de interesse público (SRUP)','srup-arvores-de-interesse-publico'),
 ('DPH','srup_dph','Domínio público hídrico — zonas de ocupação condicionada e proibida (SRUP)','srup-dominio-publico-hidrico'),
 ('CASAP','srup_captacoes','Captações de águas subterrâneas para abastecimento público — zonas de proteção (SRUP)','srup-captacoes-de-aguas-subterraneas-para-abastecimento-publ'),
 ('GO','srup_gasodutos','Gasodutos e oleodutos (SRUP)','srup-gasodutos-e-oleodutos'),
 ('RF','srup_regime_florestal','Regime florestal total e parcial (SRUP)','srup-regime-florestal'),
 ('OAH','srup_hidroagricola','Obras de aproveitamento hidroagrícola — perímetros de rega (SRUP)','srup-obras-de-aproveitamento-hidroagricola'),
 ('TC','srup_telecomunicacoes','Servidões radioelétricas — estações, feixes e zonas de libertação (SRUP)','srup-telecomunicacoes'),
 ('IPE','srup_explosivos','Instalações com produtos explosivos — zonas de proteção (SRUP)','srup-instalacoes-com-produtos-explosivos'),
 ('RG','srup_recursos_geologicos','Recursos geológicos — pedreiras, concessões mineiras, águas minerais (SRUP)','srup-recursos-geologicos'),
 ('AAPC','srup_albufeiras','Albufeiras de águas públicas classificadas e rios de 1.ª ordem (SRUP)','srup-albufeiras-de-aguas-publicas-classificadas'),
 ('EPTM','srup_prisionais','Estabelecimentos prisionais e tutelares de menores — zonas de proteção (SRUP)','srup-estabelecimentos-prisionais-e-tutelares-de-menores'),
 ('IA','srup_aduaneiras','Instalações aduaneiras (SRUP)','srup-instalacoes-aduaneiras')) v(fam, id, title, slug)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date;
UPDATE open.dataset_meta m SET row_count = c.n FROM (
  SELECT familia, sum(n) AS n FROM (SELECT familia, count(*) AS n FROM open.dgt_srup GROUP BY 1 UNION ALL
    SELECT familia, count(*) FROM open.dgt_srup_linhas GROUP BY 1 UNION ALL SELECT familia, count(*) FROM open.dgt_srup_pontos GROUP BY 1) u GROUP BY 1) c
WHERE m.source_url LIKE '%SDISNITWFSSRUP_' || c.familia || '_PT1%';
SQL
psql "$PG_DSN" -c "SELECT familia, tipo, count(*) FILTER (WHERE k = 'pol') AS pol, count(*) FILTER (WHERE k = 'lin') AS lin, count(*) FILTER (WHERE k = 'pt') AS pt
  FROM (SELECT familia, tipo, 'pol' k FROM open.dgt_srup UNION ALL SELECT familia, tipo, 'lin' FROM open.dgt_srup_linhas UNION ALL
        SELECT familia, tipo, 'pt' FROM open.dgt_srup_pontos) u GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT pg_size_pretty(sum(pg_total_relation_size(('open.' || t)::regclass))) AS srup_size FROM unnest(ARRAY['dgt_srup','dgt_srup_linhas','dgt_srup_pontos']) t;"
fi

if stage ip; then
echo "== Infraestruturas de Portugal — national rail network + national road network (Tier 2, Lisbon study area)"
# Two national shapefiles in EPSG:3763 from the dados.gov.pt records rede-ferroviaria-nacional and rede-rodoviaria-nacional
# (IP, CC BY 4.0, resources dated 2026-04-15): rail = the lines in operation (designacao, exploracao, segmento; 59 features
# nationally, all "Com Exploração"); roads = the national road plan network (PRN: auto-estradas, IP, IC, EN, ER, ramos de
# ligação = motorway junction ramps, estradas desclassificadas; roadnumber, categoria, estado incl. "Em Projeto", gestao,
# n_vias) — NOT municipal streets (stage osm). The resource URL carries its date: a newer IP release has a new URL.
mkdir -p "$RAW/ip"
fetch_file https://dados.gov.pt/s/resources/rede-ferroviaria-nacional/20260415-171819/rede-ferroviaria.zip "$RAW/ip/rede-ferroviaria.zip" ip_ferrovia
fetch_file https://dados.gov.pt/s/resources/rede-rodoviaria-nacional/20260415-170612/rede-rodoviaria.zip "$RAW/ip/rede-rodoviaria.zip" ip_rede_rodoviaria
# shellcheck disable=SC2046
ogr2ogr -f PostgreSQL "$OGR_PG" "/vsizip/$RAW/ip/rede-ferroviaria.zip" Rede_Ferroviaria -nln open.ip_ferrovia "${OGR_COMMON[@]}" -overwrite -makevalid \
  -spat $(t2_bbox 3763) -spat_srs EPSG:3763
# shellcheck disable=SC2046
ogr2ogr -f PostgreSQL "$OGR_PG" "/vsizip/$RAW/ip/rede-rodoviaria.zip" Rede_Rodoviaria -nln open.ip_rede_rodoviaria "${OGR_COMMON[@]}" -overwrite -makevalid \
  -spat $(t2_bbox 3763) -spat_srs EPSG:3763
for t in ip_ferrovia ip_rede_rodoviaria; do trim_to_regions "$t" line; keep_study_area "$t"; done
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid) VALUES
 ('ip_ferrovia','Rede Ferroviária Nacional — linhas em exploração (troços)','Infraestruturas de Portugal, S.A.','CC BY 4.0 (dados.gov.pt rede-ferroviaria-nacional)','https://dados.gov.pt/s/resources/rede-ferroviaria-nacional/20260415-171819/rede-ferroviaria.zip','2026-04-15 (recurso publicado)',3763),
 ('ip_rede_rodoviaria','Rede Rodoviária Nacional (PRN) — auto-estradas, IP, IC, EN, ER e ramos de ligação, com estado (construído / em construção / em projeto)','Infraestruturas de Portugal, S.A.','CC BY 4.0 (dados.gov.pt rede-rodoviaria-nacional)','https://dados.gov.pt/s/resources/rede-rodoviaria-nacional/20260415-170612/rede-rodoviaria.zip','2026-04-15 (recurso publicado)',3763)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.ip_ferrovia) WHERE id = 'ip_ferrovia';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.ip_rede_rodoviaria) WHERE id = 'ip_rede_rodoviaria';
SQL
psql "$PG_DSN" -c "SELECT categoria, estado, count(*) AS segments, round((sum(ST_Length(geom)) / 1000)::numeric) AS km FROM open.ip_rede_rodoviaria GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT region, count(*) AS rail_segments, round((sum(ST_Length(geom)) / 1000)::numeric) AS km FROM open.ip_ferrovia GROUP BY 1 ORDER BY 1;"
fi

if stage osm; then
echo "== OpenStreetMap (Geofabrik Portugal extract) — road/rail network, power lines, substations/plants, schools/health/stations (Tier 2)"
# Geofabrik's daily Portugal extract, ODbL 1.0: attribution "© OpenStreetMap contributors"; a PUBLISHED database derived from
# it must be offered under ODbL (data/sources.md). The newest data/raw/osm/portugal-*.osm.pbf is used (none → the current one
# is fetched as portugal-latest.osm.pbf). Keys read through data/etl/osmconf.ini. One pass per OSM layer over the PBF (lines
# 20 s, points 5 s, multipolygons 45 s on the laptop, 2026-09-30), study-area bbox + attribute filters, into scratch tables,
# then typed tables, trimmed and scoped like every layer. Left out on purpose: footways/paths/steps/cycleways/bridleways (not
# a vehicle network), service ways that are parking aisles, driveways or drive-throughs, proposed/under-construction ways,
# and healthcare= values other than hospital/clinic/doctor/centre (pharmacies, dentists, labs…). A substation, school or
# station mapped both as a node and as an area appears twice (different points). OSM completeness varies: absence in OSM is
# never evidence of absence.
mkdir -p "$RAW/osm"
OSM_PBF=$(ls -1 "$RAW"/osm/portugal-*.osm.pbf 2>/dev/null | tail -1 || true)
[ -n "$OSM_PBF" ] || OSM_PBF="$RAW/osm/portugal-latest.osm.pbf"
OSM_URL="https://download.geofabrik.de/europe/$(basename "$OSM_PBF")"
fetch_file "$OSM_URL" "$OSM_PBF" osm_portugal
OSM_B=$(basename "$OSM_PBF" .osm.pbf); OSM_B=${OSM_B#portugal-}
if [[ "$OSM_B" =~ ^[0-9]{6}$ ]]; then OSM_REF="extract of 20${OSM_B:0:2}-${OSM_B:2:2}-${OSM_B:4:2} (Geofabrik)"; else OSM_REF="extract retrieved $(date +%F) (Geofabrik)"; fi
# shellcheck disable=SC2046
OSM_OPTS=(--config OSM_CONFIG_FILE "$ROOT/data/etl/osmconf.ini" -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=NONE
  --config PG_USE_COPY YES -overwrite -spat $(t2_bbox 4326) -spat_srs EPSG:4326)
POI_WHERE="amenity IN ('school','kindergarten','college','university','hospital','clinic','doctors') OR healthcare IN ('hospital','clinic','doctor','centre') OR power IN ('substation','plant') OR railway IN ('station','halt') OR public_transport = 'station'"
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open._osm_lin, open._osm_pt, open._osm_pol;"
ogr2ogr -f PostgreSQL "$OGR_PG" "$OSM_PBF" lines "${OSM_OPTS[@]}" -nln open._osm_lin -nlt MULTILINESTRING \
  -where "(highway IS NOT NULL AND highway NOT IN ('footway','path','steps','cycleway','bridleway','corridor','proposed','construction','platform','elevator','via_ferrata','raceway','bus_stop','abandoned','razed','disused','planned','rest_area','services') AND (service IS NULL OR service NOT IN ('parking_aisle','driveway','drive-through'))) OR railway IN ('rail','light_rail','subway','tram','narrow_gauge','funicular') OR power IN ('line','minor_line','cable')"
ogr2ogr -f PostgreSQL "$OGR_PG" "$OSM_PBF" points "${OSM_OPTS[@]}" -nln open._osm_pt -where "$POI_WHERE"
ogr2ogr -f PostgreSQL "$OGR_PG" "$OSM_PBF" multipolygons "${OSM_OPTS[@]}" -nln open._osm_pol -nlt MULTIPOLYGON -where "$POI_WHERE"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.osm_rede, open.osm_energia_linhas, open.osm_energia, open.osm_pois;
CREATE TABLE open.osm_rede AS
  SELECT osm_id::bigint AS osm_id, CASE WHEN highway IS NOT NULL THEN 'estrada' ELSE 'ferrovia' END AS tipo,
         coalesce(highway, railway) AS classe, name AS nome, ref, maxspeed, oneway, service, usage, bridge AS ponte, tunnel AS tunel, geom
  FROM open._osm_lin WHERE highway IS NOT NULL OR railway IS NOT NULL;
CREATE TABLE open.osm_energia_linhas AS
  SELECT osm_id::bigint AS osm_id, power AS tipo, voltage AS tensao_v, operator AS operador, name AS nome, ref, geom
  FROM open._osm_lin WHERE power IN ('line','minor_line','cable');
-- substations/plants: nodes as they are; areas as a point on their surface + their area (m²)
CREATE TABLE open.osm_energia AS
  SELECT osm_id::bigint AS osm_id, 'node'::text AS origem, power AS tipo, substation AS subtipo, voltage AS tensao_v, operator AS operador,
         name AS nome, ref, NULL::numeric AS area_m2, geom::geometry(Point, 3763) AS geom
  FROM open._osm_pt WHERE power IN ('substation','plant')
  UNION ALL
  SELECT coalesce(osm_id, osm_way_id)::bigint, CASE WHEN osm_id IS NOT NULL THEN 'relation' ELSE 'way' END, power, substation, voltage,
         operator, name, ref, round(ST_Area(geom)::numeric), ST_PointOnSurface(geom)::geometry(Point, 3763)
  FROM open._osm_pol WHERE power IN ('substation','plant');
CREATE TABLE open.osm_pois AS
  WITH u AS (
    SELECT osm_id::bigint AS osm_id, 'node'::text AS origem, amenity, healthcare, railway, public_transport, name, operator,
           NULL::numeric AS area_m2, geom::geometry(Point, 3763) AS geom FROM open._osm_pt
    UNION ALL
    SELECT coalesce(osm_id, osm_way_id)::bigint, CASE WHEN osm_id IS NOT NULL THEN 'relation' ELSE 'way' END, amenity, healthcare,
           railway, public_transport, name, operator, round(ST_Area(geom)::numeric), ST_PointOnSurface(geom)::geometry(Point, 3763)
    FROM open._osm_pol)
  SELECT osm_id, origem,
         CASE WHEN amenity IN ('school','kindergarten','college','university') THEN 'ensino'
              WHEN amenity IN ('hospital','clinic','doctors') OR healthcare IN ('hospital','clinic','doctor','centre') THEN 'saude'
              ELSE 'transporte' END AS categoria,
         CASE WHEN amenity IN ('school','kindergarten','college','university','hospital','clinic','doctors') THEN amenity
              WHEN healthcare IN ('hospital','clinic','doctor','centre') THEN healthcare
              ELSE coalesce(railway, amenity, public_transport) END AS classe,
         name AS nome, operator AS operador, area_m2, geom
  FROM u WHERE amenity IN ('school','kindergarten','college','university','hospital','clinic','doctors')
            OR healthcare IN ('hospital','clinic','doctor','centre') OR railway IN ('station','halt') OR public_transport = 'station';
DROP TABLE open._osm_lin, open._osm_pt, open._osm_pol;
CREATE INDEX ON open.osm_rede USING GIST (geom); CREATE INDEX ON open.osm_energia_linhas USING GIST (geom);
CREATE INDEX ON open.osm_energia USING GIST (geom); CREATE INDEX ON open.osm_pois USING GIST (geom);
SQL
trim_to_regions osm_rede line; trim_to_regions osm_energia_linhas line; trim_to_regions osm_energia point; trim_to_regions osm_pois point
for t in osm_rede osm_energia_linhas osm_energia osm_pois; do keep_study_area "$t"; done
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -v url="$OSM_URL" -v ref="$OSM_REF" <<'SQL'
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid) VALUES
 ('osm_rede','OpenStreetMap — rede viária (motorway … residential, living street, pedestrian, track; service sem parques/acessos privados) e ferroviária (rail, light rail, metro, elétrico, funicular)','OpenStreetMap contributors (extract: Geofabrik)','ODbL 1.0 — © OpenStreetMap contributors',:'url',:'ref',3763),
 ('osm_energia','OpenStreetMap — linhas elétricas (line, minor_line, cable) e subestações/centrais (power=substation/plant)','OpenStreetMap contributors (extract: Geofabrik)','ODbL 1.0 — © OpenStreetMap contributors',:'url',:'ref',3763),
 ('osm_pois','OpenStreetMap — escolas (school, kindergarten, college, university), unidades de saúde (hospital, clinic, doctors, healthcare centre) e estações (comboio, metro, autocarro, fluvial)','OpenStreetMap contributors (extract: Geofabrik)','ODbL 1.0 — © OpenStreetMap contributors',:'url',:'ref',3763)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.osm_rede) WHERE id = 'osm_rede';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.osm_energia) + (SELECT count(*) FROM open.osm_energia_linhas) WHERE id = 'osm_energia';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.osm_pois) WHERE id = 'osm_pois';
SQL
psql "$PG_DSN" -c "SELECT tipo, classe, count(*) AS n, round((sum(ST_Length(geom)) / 1000)::numeric) AS km FROM open.osm_rede GROUP BY 1, 2 ORDER BY 1, 3 DESC;" \
  -c "SELECT tipo, count(*) AS n, count(*) FILTER (WHERE tensao_v IS NOT NULL) AS with_voltage, round((sum(ST_Length(geom)) / 1000)::numeric) AS km FROM open.osm_energia_linhas GROUP BY 1 ORDER BY 1;" \
  -c "SELECT tipo, origem, count(*) AS n, count(*) FILTER (WHERE nome IS NOT NULL) AS named FROM open.osm_energia GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT categoria, classe, count(*) AS n FROM open.osm_pois GROUP BY 1, 2 ORDER BY 1, 3 DESC;" \
  -c "SELECT pg_size_pretty(sum(pg_total_relation_size(('open.' || t)::regclass))) AS osm_size FROM unnest(ARRAY['osm_rede','osm_energia_linhas','osm_energia','osm_pois']) t;"
fi

if stage eredes; then
echo "== E-REDES open data — hosting capacity per substation, substation load, secondary substations (PTD) (Tier 2)"
# Opendatasoft API e-redes.opendatasoft.com, CC BY 4.0. capacidade-rececao-rnd (updated 2026-07-11; 469 rows nationally: 407
# HV/MV substations "SE AT" + 62 HV switching posts "PC AT"): hosting capacity for NEW GENERATION (MVA, MV+HV) at three dates
# — RARI (the regulated report), last quarter, forecast — plus power already connected / committed / being confirmed.
# carga-na-subestacao (2025, winter and summer, 397 substations): natural load, installed and guaranteed power and
# availability (MVA) = headroom for LOAD at distribution level, NOT the transmission grid (data centres stay "not assessable"
# above distribution). postos-transformacao-distribuicao (MV/LV secondary substations, points: installed kVA, usage band,
# clients band): study-area bbox only (17 350 points, 2026-09-30), kept within 2 km of the study area.
# The substation tables have no coordinates: the installation code starts with the DICO of its municipality (checked on 6
# codes, 2026-09-30) → dico; rows are kept for the study-area municipalities and their neighbours within 10 km (region NULL =
# neighbour). A point is added ONLY where the OSM substations (stage osm) inside that municipality (1 km margin) whose
# name contains the installation name as whole words all lie within 300 m of each other; `localizacao` says so. Otherwise
# NULL, never guessed. Re-run this stage after stage osm.
mkdir -p "$RAW/eredes"
ODS=https://e-redes.opendatasoft.com/api/explore/v2.1/catalog/datasets
fetch_file "$ODS/capacidade-rececao-rnd/exports/json" "$RAW/eredes/capacidade-rececao-rnd.json" eredes_capacidade_rececao
fetch_file "$ODS/carga-na-subestacao/exports/json" "$RAW/eredes/carga-na-subestacao.json" eredes_carga_subestacao
read -r X0 Y0 X1 Y1 <<< "$(t2_bbox 4326)"
fetch_file "$ODS/postos-transformacao-distribuicao/exports/geojson?where=$(jq -rn --arg s "in_bbox(coordenadas_geo, $Y0, $X0, $Y1, $X1)" '$s|@uri')" \
  "$RAW/eredes/ptd_study_area.geojson" eredes_ptd
for n in capacidade-rececao-rnd carga-na-subestacao; do jq -c '.[]' "$RAW/eredes/$n.json" > "$RAW/eredes/$n.jsonl"; done
# JSON lines through COPY csv with control characters as quote/delimiter: no escaping of the JSON text
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "DROP TABLE IF EXISTS open._er_cap, open._er_carga; CREATE TABLE open._er_cap (j jsonb); CREATE TABLE open._er_carga (j jsonb);" \
  -c "\copy open._er_cap (j) FROM '$RAW/eredes/capacidade-rececao-rnd.jsonl' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')" \
  -c "\copy open._er_carga (j) FROM '$RAW/eredes/carga-na-subestacao.jsonl' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')"
ogr2ogr -f PostgreSQL "$OGR_PG" "$RAW/eredes/ptd_study_area.geojson" -nln open.eredes_ptd -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom \
  -lco SPATIAL_INDEX=GIST --config PG_USE_COPY YES -overwrite \
  -select cod_instalacao,coddistritoconcelho,con_name,potencia_transformacao_kva,nivel_utilizacao,tipo_construtivo,potencia_contratada,num_clientes,potencia_geracao,num_produtores
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "ALTER TABLE open.eredes_ptd RENAME COLUMN coddistritoconcelho TO dico;"
tag_points eredes_ptd
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -v t2="$(t2_sql)" <<'SQL'
DROP TABLE IF EXISTS open.eredes_capacidade, open.eredes_carga_subestacao;
CREATE TEMP TABLE er_scope AS
  SELECT m.dico, (SELECT p.region FROM open.pilot_regions p WHERE p.dico = m.dico AND p.region IN (:t2)) AS region
  FROM open.caop_municipios m
  WHERE EXISTS (SELECT 1 FROM open.pilot_regions p WHERE p.region IN (:t2) AND ST_DWithin(m.geom, p.geom, 10000));
-- values arrive as text ("-" = not applicable) → numeric only when they look like a number
CREATE TABLE open.eredes_capacidade AS
  SELECT j->>'codigo' AS codigo, left(j->>'codigo', 4) AS dico, j->>'instalacao' AS instalacao, j->>'tipo_de_instalacao' AS tipo,
         j->>'concelho' AS concelho, j->>'grupo_de_subestacoes_rari' AS grupo_subestacoes,
         CASE WHEN j->>'capacidade_de_recepcao_mt_at_mva_rari' ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (j->>'capacidade_de_recepcao_mt_at_mva_rari')::numeric END AS cap_rececao_mva_rari,
         CASE WHEN j->>'capacidade_de_recepcao_mt_at_mva_ultimo_trimestre' ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (j->>'capacidade_de_recepcao_mt_at_mva_ultimo_trimestre')::numeric END AS cap_rececao_mva_trimestre,
         CASE WHEN j->>'capacidade_de_recepcao_mt_at_mva_previsao' ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (j->>'capacidade_de_recepcao_mt_at_mva_previsao')::numeric END AS cap_rececao_mva_previsao,
         CASE WHEN j->>'potencia_de_ligacao_ligado_mva_ultimo_trimestre' ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (j->>'potencia_de_ligacao_ligado_mva_ultimo_trimestre')::numeric END AS ligado_mva_trimestre,
         CASE WHEN j->>'potencia_de_ligacao_comprometido_mva_ultimo_trimestre' ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (j->>'potencia_de_ligacao_comprometido_mva_ultimo_trimestre')::numeric END AS comprometido_mva_trimestre,
         CASE WHEN j->>'potencia_de_ligacao_em_confirmacao_mva_ultimo_trimestre' ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (j->>'potencia_de_ligacao_em_confirmacao_mva_ultimo_trimestre')::numeric END AS em_confirmacao_mva_trimestre,
         j->>'data_rari' AS data_rari, j->>'data_ultimo_trimestre' AS data_trimestre, j->>'data_previsao' AS data_previsao,
         j->>'notas' AS notas, j->>'justificacao' AS justificacao, j AS attrs, s.region,
         NULL::text AS localizacao, NULL::geometry(Point, 3763) AS geom
  FROM open._er_cap JOIN er_scope s ON s.dico = left(j->>'codigo', 4);
CREATE TABLE open.eredes_carga_subestacao AS
  SELECT j->>'ano' AS ano, j->>'codigo_da_instalacao' AS codigo, left(j->>'codigo_da_instalacao', 4) AS dico, j->>'nome' AS nome,
         j->>'tensao' AS tensao_kv, j->>'inverno_verao' AS estacao, (j->>'carga_natural')::numeric AS carga_natural_mva,
         (j->>'potencia_instalada')::numeric AS potencia_instalada_mva, (j->>'potencia_garantida')::numeric AS potencia_garantida_mva,
         (j->>'disponibilidade')::numeric AS disponibilidade_mva, (j->>'carga_nao_garantida')::numeric AS carga_nao_garantida_mva,
         s.region, NULL::text AS localizacao, NULL::geometry(Point, 3763) AS geom
  FROM open._er_carga JOIN er_scope s ON s.dico = left(j->>'codigo_da_instalacao', 4);
DROP TABLE open._er_cap, open._er_carga;
-- point from OSM only when unambiguous (see the stage comment); the name without "(…)" and punctuation, whole words
DO $$ DECLARE t text; nm text; BEGIN
  IF to_regclass('open.osm_energia') IS NULL THEN
    RAISE NOTICE 'eredes: open.osm_energia missing (stage osm) — substations stay without a point'; RETURN;
  END IF;
  FOR t, nm IN VALUES ('eredes_capacidade', 'instalacao'), ('eredes_carga_subestacao', 'nome') LOOP
    EXECUTE format($q$
      WITH k AS (SELECT DISTINCT codigo, dico, trim(regexp_replace(translate(upper(regexp_replace(%2$I, '\(.*?\)', '', 'g')),
                   'ÁÀÂÃÉÊÍÓÔÕÚÇ', 'AAAAEEIOOOUC'), '[^A-Z0-9]+', ' ', 'g')) AS key FROM open.%1$I),
      c AS (SELECT k.codigo, ST_MaxDistance(ST_Collect(o.geom), ST_Collect(o.geom)) AS spread, ST_Centroid(ST_Collect(o.geom)) AS g,
                   string_agg(o.osm_id::text, ',' ORDER BY o.osm_id) AS ids
            FROM k JOIN open.caop_municipios m ON m.dico = k.dico
            JOIN open.osm_energia o ON o.tipo = 'substation' AND ST_DWithin(m.geom, o.geom, 1000)
             AND ' ' || trim(regexp_replace(translate(upper(o.nome), 'ÁÀÂÃÉÊÍÓÔÕÚÇ', 'AAAAEEIOOOUC'), '[^A-Z0-9]+', ' ', 'g')) || ' '
                 LIKE '%% ' || k.key || ' %%'
            WHERE length(k.key) >= 3 GROUP BY k.codigo)
      UPDATE open.%1$I x SET geom = c.g, localizacao = 'OSM power=substation com o nome da instalação, no concelho (osm_id ' || c.ids || ')'
      FROM c WHERE c.codigo = x.codigo AND c.spread <= 300$q$, t, nm);
  END LOOP;
END $$;
CREATE INDEX ON open.eredes_capacidade USING GIST (geom); CREATE INDEX ON open.eredes_carga_subestacao USING GIST (geom);
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid) VALUES
 ('eredes_capacidade_rececao','Capacidade de receção da Rede Nacional de Distribuição por subestação AT/MT e posto de corte (MVA, MT+AT: RARI, último trimestre, previsão) e potência ligada / comprometida / em confirmação','E-REDES','CC BY 4.0 (e-redes.opendatasoft.com capacidade-rececao-rnd)','https://e-redes.opendatasoft.com/explore/dataset/capacidade-rececao-rnd/','atualizado 2026-07-11; datas por coluna (data_rari, data_trimestre, data_previsao)',3763),
 ('eredes_carga_subestacao','Carga na subestação AT/MT — carga natural, potência instalada e garantida, disponibilidade (MVA), inverno e verão','E-REDES','CC BY 4.0 (e-redes.opendatasoft.com carga-na-subestacao)','https://e-redes.opendatasoft.com/explore/dataset/carga-na-subestacao/','2025 (atualizado 2026-04-22)',3763),
 ('eredes_ptd','Postos de transformação de distribuição MT/BT (pontos) — potência instalada (kVA), nível de utilização, clientes','E-REDES','CC BY 4.0 (e-redes.opendatasoft.com postos-transformacao-distribuicao)','https://e-redes.opendatasoft.com/explore/dataset/postos-transformacao-distribuicao/','atualizado 2026-07-16',3763)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.eredes_capacidade) WHERE id = 'eredes_capacidade_rececao';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.eredes_carga_subestacao) WHERE id = 'eredes_carga_subestacao';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.eredes_ptd) WHERE id = 'eredes_ptd';
SQL
psql "$PG_DSN" -c "SELECT coalesce(region, '(vizinho)') AS region, tipo, count(*) AS n, count(geom) AS with_point, round(sum(cap_rececao_mva_trimestre)) AS cap_mva_last_quarter FROM open.eredes_capacidade GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT coalesce(region, '(vizinho)') AS region, estacao, count(*) AS n, count(geom) AS with_point, round(sum(disponibilidade_mva)) AS availability_mva FROM open.eredes_carga_subestacao GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT region, count(*) AS ptd, round(sum(potencia_transformacao_kva) / 1000) AS mva_installed FROM open.eredes_ptd GROUP BY 1 ORDER BY 1;"
fi

if stage apa_agua; then
echo "== APA — protection perimeters of drinking-water abstractions + groundwater bodies (Tier 2; licence NOT stated)"
# SNIAmb shapefile zips listed on dados.gov.pt (APA, licence "notspecified" → loaded and marked; never shown in the demo until
# the licence is confirmed). Six perimeter layers, EPSG:3763, with the approving Portaria in `diploma`: immediate /
# intermediate / extended zone of groundwater abstractions, special protection zone (zips of 2026-09-26; the special zone
# 2019-06-08), immediate / extended zone of surface abstractions → apa_perimetros_captacao (zona, origem). The SRUP pack
# (stage srup, family CASAP, CC BY 4.0) holds the DGT copy of the GROUNDWATER perimeters — prefer it where both exist; APA adds
# the surface abstractions. Groundwater bodies of the river-basin plans (WISE view, 93 bodies nationally, EPSG:4326: code,
# name, river-basin region, quantitative / chemical / overall status) → apa_massas_subterraneas.
mkdir -p "$RAW/apa_t2"
APA_Z=https://sniambgeoviewer.apambiente.pt/GeoDocs/shpzips
# ogr2ogr names the primary key and the spatial index after the scratch table, and index names survive a RENAME TABLE →
# renamed with the table below; a copy loaded before that fix (2026-09-30) still carries them → renamed here first
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open._apa_per;" -c "ALTER INDEX IF EXISTS open._apa_per_pkey RENAME TO apa_perimetros_captacao_pkey;" \
  -c "ALTER INDEX IF EXISTS open._apa_per_geom_geom_idx RENAME TO apa_perimetros_captacao_geom_geom_idx;"
first=1
for z in "ProteccaoImediataSubt|imediata|subterrânea" "ProteccaoIntermediaSubt|intermédia|subterrânea" "ProteccaoAlargadaSubt|alargada|subterrânea" \
         "ProteccaoEspecial|especial|subterrânea" "ProteccaoImediataSup|imediata|superficial" "ProteccaoAlargadaSup|alargada|superficial"; do
  IFS='|' read -r Z ZONA ORIG <<< "$z"
  f="$RAW/apa_t2/D311_ZonasProtegidas_$Z.zip"
  fetch_file "$APA_Z/D311_ZonasProtegidas_$Z.zip" "$f" "apa_perimetros_$Z" || continue
  if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
  # -spat in the layer's own SRS (EPSG:3763): ogr2ogr refuses -spat_srs together with -sql
  # shellcheck disable=SC2046,SC2086
  ogr2ogr -f PostgreSQL "$OGR_PG" "/vsizip/$f" -nln open._apa_per "${OGR_COMMON[@]}" $mode -makevalid -spat $(t2_bbox 3763) \
    -sql "SELECT nome, diplegal AS diploma, '$ZONA' AS zona, '$ORIG' AS origem, codhidro, codrh FROM \"D311_ZonasProtegidas_$Z\""
done
trim_to_regions _apa_per; keep_study_area _apa_per
fetch_file https://sniambgeoviewer.apambiente.pt/Geodocs/shpzips/wise_vw_groundwaterbody_ptcont.zip "$RAW/apa_t2/wise_vw_groundwaterbody_ptcont.zip" apa_massas_subterraneas
# shellcheck disable=SC2046
ogr2ogr -f PostgreSQL "$OGR_PG" "/vsizip/$RAW/apa_t2/wise_vw_groundwaterbody_ptcont.zip" -nln open.apa_massas_subterraneas "${OGR_COMMON[@]}" -overwrite \
  -makevalid -spat $(t2_bbox 4326) \
  -sql "SELECT codigo, nome, regiao_hid, estado_qua AS estado_quantitativo, estado_qui AS estado_quimico, estado_tot AS estado_global FROM wise_vw_groundwaterbody_ptcont"
trim_to_regions apa_massas_subterraneas; keep_study_area apa_massas_subterraneas
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.apa_perimetros_captacao;
ALTER TABLE open._apa_per RENAME TO apa_perimetros_captacao;
ALTER INDEX IF EXISTS open._apa_per_pkey RENAME TO apa_perimetros_captacao_pkey;
ALTER INDEX IF EXISTS open._apa_per_geom_geom_idx RENAME TO apa_perimetros_captacao_geom_geom_idx;
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('apa_perimetros_captacao','Perímetros de proteção de captações de água para consumo humano — zonas imediata, intermédia, alargada e especial (subterrâneas) e imediata, alargada (superficiais), com a portaria','Agência Portuguesa do Ambiente (SNIAmb)','não indicada (dados.gov.pt: notspecified) — carregado; NÃO mostrar na demo até confirmar','https://sniambgeoviewer.apambiente.pt/GeoDocs/shpzips/D311_ZonasProtegidas_<Zona>.zip','zips de 2026-09-26 (zona especial: 2019-06-08)',3763,'licence to confirm; the SRUP CASAP family (CC BY 4.0) covers the groundwater perimeters'),
 ('apa_massas_subterraneas','Massas de água subterrâneas de Portugal continental (planos de gestão de região hidrográfica) — estado quantitativo, químico e global','Agência Portuguesa do Ambiente (SNIAmb)','não indicada (dados.gov.pt: notspecified) — carregado; NÃO mostrar na demo até confirmar','https://sniambgeoviewer.apambiente.pt/Geodocs/shpzips/wise_vw_groundwaterbody_ptcont.zip','zip de 2026-09-26 (PGRH em vigor)',3763,'licence to confirm')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.apa_perimetros_captacao) WHERE id = 'apa_perimetros_captacao';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.apa_massas_subterraneas) WHERE id = 'apa_massas_subterraneas';
SQL
psql "$PG_DSN" -c "SELECT origem, zona, count(*) AS n, count(DISTINCT diploma) AS diplomas, round((sum(ST_Area(geom)) / 1e4)::numeric) AS ha FROM open.apa_perimetros_captacao GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT codigo, nome, estado_global, round((sum(ST_Area(geom)) / 1e6)::numeric) AS km2_in_area FROM open.apa_massas_subterraneas GROUP BY 1, 2, 3 ORDER BY 4 DESC;"
fi

if stage equipamentos; then
echo "== Schools and health centres of the AML — Transportes Metropolitanos de Lisboa open datasets (Tier 2)"
# github.com/carrismetropolitana/datasets ("Dados georeferenciados sobre a AML", TML/Carris Metropolitana): repository licence
# ODbL 1.0 (its LICENSE file, read through the GitHub API on 2026-09-30); the dados.gov.pt record escolas-da-area-metropolitana-
# de-lisboa says "not specified" — the repository licence is the one applied (attribution: TML). schools.csv (2 132 rows:
# nature, grouping, one 0/1 flag per level pre-school … university, is_active) → equip_escolas; health_centers.csv (216 rows:
# centros de saúde, USF, UCSP, UCC as published; 53 without municipality name — region comes from the point) → equip_saude.
# The 18 AML municipalities only: the Lezíria and Vendas Novas rely on OSM (osm_pois); hospitals are OSM only (no official
# open point layer found, 2026-09-30; SNS "unidades funcionais" is aggregated per ACES, not per unit).
mkdir -p "$RAW/tml"
TML_URL=https://github.com/carrismetropolitana/datasets/raw/latest/facilities
fetch_file "$TML_URL/schools/schools.csv" "$RAW/tml/schools.csv" tml_escolas
fetch_file "$TML_URL/health_centers/health_centers.csv" "$RAW/tml/health_centers.csv" tml_saude
TML_CSV=(-f PostgreSQL "$OGR_PG" -oo X_POSSIBLE_NAMES=lon -oo Y_POSSIBLE_NAMES=lat -oo KEEP_GEOM_COLUMNS=NO -oo AUTODETECT_TYPE=NO
  -s_srs EPSG:4326 -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -nlt POINT --config PG_USE_COPY YES -overwrite)
ogr2ogr "${TML_CSV[@]}" "$RAW/tml/schools.csv" -nln open.equip_escolas \
  -select id,name,nature,grouping,is_active,pre_school,basic_1,basic_2,basic_3,high_school,professional,special,artistic,university,other,address,locality,municipality_id,municipality_name
ogr2ogr "${TML_CSV[@]}" "$RAW/tml/health_centers.csv" -nln open.equip_saude -select id,name,address,locality,municipality_id,municipality_name
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "ALTER TABLE open.equip_escolas RENAME COLUMN municipality_id TO dico;" \
  -c "ALTER TABLE open.equip_saude RENAME COLUMN municipality_id TO dico;"
tag_points equip_escolas; tag_points equip_saude
# `nature` comes in two spellings (public/Publico, private/Privado) and empty → natureza: público / privado / NULL
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "ALTER TABLE open.equip_escolas ADD COLUMN natureza text;" \
  -c "UPDATE open.equip_escolas SET natureza = CASE WHEN lower(nature) IN ('public','publico','público') THEN 'público'
        WHEN lower(nature) IN ('private','privado') THEN 'privado' END;"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('equip_escolas','Escolas da Área Metropolitana de Lisboa (públicas e privadas, do pré-escolar ao superior; níveis de ensino por escola)','Transportes Metropolitanos de Lisboa (TML / Carris Metropolitana)','ODbL 1.0 (licença do repositório github.com/carrismetropolitana/datasets; dados.gov.pt: não especificada)','https://github.com/carrismetropolitana/datasets/raw/latest/facilities/schools/schools.csv','repositório atualizado 2026-09-07',3763,'AML only (18 municipalities); Lezíria and Vendas Novas: osm_pois'),
 ('equip_saude','Unidades de cuidados de saúde primários da Área Metropolitana de Lisboa (centros de saúde, USF, UCSP, UCC)','Transportes Metropolitanos de Lisboa (TML / Carris Metropolitana)','ODbL 1.0 (licença do repositório github.com/carrismetropolitana/datasets)','https://github.com/carrismetropolitana/datasets/raw/latest/facilities/health_centers/health_centers.csv','repositório atualizado 2026-09-07',3763,'AML only; hospitals: osm_pois')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.equip_escolas) WHERE id = 'equip_escolas';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.equip_saude) WHERE id = 'equip_saude';
SQL
psql "$PG_DSN" -c "SELECT region, natureza, count(*) AS schools FROM open.equip_escolas GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT region, count(*) AS health_units FROM open.equip_saude GROUP BY 1 ORDER BY 1;"
fi

if stage ruido; then
echo "== Strategic noise maps (Tier 2): Oeiras MER 2022 (Lden, Ln) from the municipal WFS"
# CM Oeiras open-data WFS (ArcGIS, WFS 2.0.0, GML 3.2 in EPSG:3763; dados.gov.pt mer-mapa-estrategico-de-ruido, CC BY 4.0):
# one multipolygon per noise class ("< 55 dB(A)", ">= 55 a < 60 dB(A)"…; classeid) for Lden (day-evening-night) and Ln (night)
# → ruido_mapas (dico, concelho, indicador, classe, classe_id, edicao). NOT loaded: CM Lisboa's "Mapa Ruído Global" 2020 (CC BY
# 4.0) is a .7z on dados.cm-lisboa.pt behind a JavaScript challenge (HTTP 403 to any script, 2026-09-30) — noise is known in
# Oeiras only; every other municipality answers "unknown", never "quiet".
mkdir -p "$RAW/ruido"
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open._ruido;" -c "ALTER INDEX IF EXISTS open._ruido_pkey RENAME TO ruido_mapas_pkey;" \
  -c "ALTER INDEX IF EXISTS open._ruido_geom_geom_idx RENAME TO ruido_mapas_geom_geom_idx;"   # index names: see stage apa_agua
first=1
for p in lden ln; do
  case $p in lden) IND=Lden;; ln) IND=Ln;; esac
  f="$RAW/ruido/oeiras_mer_${p}_2022.gml"
  fetch_file "https://oeirasinterativa.oeiras.pt/gis/services/dados_abertos/w_mer_${p}_2022/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=dados_abertos:w_mer_${p}_2022" \
    "$f" "oeiras_mer_${p}_2022" || continue
  grep -q 'FeatureCollection' "$f" || { echo "WARN: Oeiras $IND — no FeatureCollection: $(head -c 200 "$f")"; rm -f "$f"; continue; }
  if [ $first -eq 1 ]; then mode=-overwrite; first=0; else mode=-append; fi
  # shellcheck disable=SC2086
  ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -nln open._ruido "${OGR_COMMON[@]}" $mode -makevalid -forceNullable -oo DOWNLOAD_SCHEMA=NO -lco PRECISION=NO \
    -sql "SELECT '1110' AS dico, 'Oeiras' AS concelho, '$IND' AS indicador, classe, classeid AS classe_id, 'MER 2022' AS edicao FROM w_mer_${p}_2022"
done
# the model area reaches beyond Oeiras (into Lisboa, Amadora, Sintra, Cascais) but only Oeiras's sources are modelled there →
# keep each map inside its own municipality (as the CRUS plans), so a point in Lisbon never reads Oeiras's noise class.
# The Ln layer names only class 7 (">= 70 dB(A)"); classes 1–6 keep classe NULL and their classe_id — never inferred.
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
UPDATE open._ruido r SET geom = ST_Multi(ST_CollectionExtract(ST_Intersection(r.geom, m.geom), 3))
  FROM open.caop_municipios m WHERE m.dico = r.dico AND NOT ST_Covers(m.geom, r.geom);
DELETE FROM open._ruido WHERE geom IS NULL OR ST_IsEmpty(geom);
SQL
trim_to_regions _ruido; keep_study_area _ruido
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.ruido_mapas;
ALTER TABLE open._ruido RENAME TO ruido_mapas;
ALTER INDEX IF EXISTS open._ruido_pkey RENAME TO ruido_mapas_pkey;
ALTER INDEX IF EXISTS open._ruido_geom_geom_idx RENAME TO ruido_mapas_geom_geom_idx;
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('ruido_mapas','Mapa Estratégico de Ruído 2022 de Oeiras — classes Lden e Ln (dB(A))','Câmara Municipal de Oeiras','CC BY 4.0 (dados.gov.pt mer-mapa-estrategico-de-ruido)','https://oeirasinterativa.oeiras.pt/gis/services/dados_abertos/w_mer_{lden,ln}_2022/wfs','MER 2022',3763,'Oeiras only; Lisboa 2020 map not scriptable (403 JS challenge) — noise unknown elsewhere')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.ruido_mapas) WHERE id = 'ruido_mapas';
SQL
psql "$PG_DSN" -c "SELECT indicador, classe_id, classe, count(*) AS n, round((sum(ST_Area(geom)) / 1e4)::numeric) AS ha FROM open.ruido_mapas GROUP BY 1, 2, 3 ORDER BY 1, 2;"
fi

if stage lneg; then
echo "== LNEG — areas of lower environmental and heritage sensitivity for solar and wind, scenarios 1–4 (Tier 2; licence NOT stated)"
# ArcGIS MapServer sig.lneg.pt/server/rest/services/AreasCandidatasRenovaveis, layers 2–5 = scenarios 1–4 (first version
# January 2023; each excludes more than the one before — scenario 4, the most restrictive, also removes the mapped RAN and REN):
# polygons only (OBJECTID, Shape_Area), queried with the study-area envelope in EPSG:3763, ≤ 1 000 features per page (168
# in scenario 1, 2026-09-30) → lneg_menos_sensiveis (cenario 1–4, cenario_descricao = the layer name as published). Licence:
# nothing on the service; CC BY 4.0 on the dataset's dados.gov.pt record (found 2026-10-01); the LNEG geoPortal legal notice
# adds no commercial use → the stricter applies; loaded and marked, off screen until the author decides. NOT loadable: the renewable
# acceleration areas (PAER, service AreasAceleracaoEnergiasRenovaveis, scenarios A–E of the GTAER, Despacho 11912/2023) —
# that service answers queries with attributes (parish, municipality, area) but NO geometry, even with returnGeometry=true
# (2026-09-30): view-only.
mkdir -p "$RAW/lneg"
LNEG_URL=https://sig.lneg.pt/server/rest/services/AreasCandidatasRenovaveis/MapServer
read -r X0 Y0 X1 Y1 <<< "$(t2_bbox 3763)"
LNEG_ENV=$(jq -rn --arg a "$X0" --arg b "$Y0" --arg c "$X1" --arg d "$Y1" \
  '{xmin: ($a|tonumber), ymin: ($b|tonumber), xmax: ($c|tonumber), ymax: ($d|tonumber), spatialReference: {wkid: 3763}} | tojson | @uri')
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -c "DROP TABLE IF EXISTS open._lneg, open._lneg_page;" \
  -c "CREATE TABLE open._lneg (cenario int, cenario_descricao text, objectid bigint, geom geometry(MultiPolygon, 3763));"
for L in 2 3 4 5; do
  C=$((L - 1))
  fetch_file "$LNEG_URL/$L?f=json" "$RAW/lneg/layer_$L.json" "lneg_layer_$L" || continue
  LDESC=$(jq -r '.name // empty' "$RAW/lneg/layer_$L.json")
  off=0
  while :; do
    f="$RAW/lneg/menos_sensiveis_c${C}_$off.json"
    fetch_file "$LNEG_URL/$L/query?where=1%3D1&geometry=$LNEG_ENV&geometryType=esriGeometryEnvelope&inSR=3763&spatialRel=esriSpatialRelIntersects&outFields=OBJECTID&returnGeometry=true&outSR=3763&resultOffset=$off&resultRecordCount=1000&orderByFields=OBJECTID&f=json" \
      "$f" "lneg_menos_sensiveis_c${C}_$off" || break
    # an ArcGIS error is an HTTP 200 with {"error": …}: never cache it
    jq -e '.features' "$f" >/dev/null || { echo "WARN: LNEG scenario $C — no features: $(head -c 200 "$f")"; rm -f "$f"; break; }
    n=$(jq '.features | length' "$f"); echo "   LNEG scenario $C, offset $off: $n polygons"
    [ "$n" -gt 0 ] || break
    ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -nln open._lneg_page "${OGR_COMMON[@]}" -overwrite -makevalid -lco PRECISION=NO
    # psql interpolates :c / :'d' only in stdin, never in -c
    psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -v c="$C" -v d="$LDESC" <<'SQL'
INSERT INTO open._lneg SELECT :c, :'d', objectid, geom FROM open._lneg_page;
DROP TABLE open._lneg_page;
SQL
    [ "$n" -lt 1000 ] && break
    off=$((off + 1000))
  done
done
trim_to_regions _lneg; keep_study_area _lneg
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.lneg_menos_sensiveis;
ALTER TABLE open._lneg RENAME TO lneg_menos_sensiveis;
CREATE INDEX ON open.lneg_menos_sensiveis USING GIST (geom);
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('lneg_menos_sensiveis','Áreas com menor sensibilidade ambiental e patrimonial para a instalação de centros electroprodutores solares e eólicos — cenários 1 a 4 (cada um exclui mais do que o anterior)','LNEG — Laboratório Nacional de Energia e Geologia','CC BY 4.0 (dados.gov.pt areas-menos-sensiveis-com-vista-a-potencial-instalacao-de-unidades-de-geracao-de-eletricidade-solar-e-eolica); nada no serviço; aviso legal do geoPortal LNEG: uso não comercial, citar a fonte — aplica-se a mais restritiva; fora do ecrã até decisão do autor','https://sig.lneg.pt/server/rest/services/AreasCandidatasRenovaveis/MapServer (camadas 2–5)','1.ª versão janeiro 2023 (cenário 1); cenários 2–4 posteriores',3763,'licence conflict (catalogue CC BY vs geoPortal non-commercial) — display is the author''s decision; the PAER acceleration areas are view-only (no geometry in the service)')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.lneg_menos_sensiveis) WHERE id = 'lneg_menos_sensiveis';
SQL
psql "$PG_DSN" -c "SELECT cenario, left(cenario_descricao, 60) AS cenario_descricao, count(*) AS n, round((sum(ST_Area(geom)) / 1e4)::numeric) AS ha FROM open.lneg_menos_sensiveis GROUP BY 1, 2 ORDER BY 1;"
fi

if stage transportes; then
echo "== Public transport (Tier 2): Carris Metropolitana stops and route patterns (TML OGC API) + Metro de Lisboa stations and lines (GTFS)"
# TML geoportal, OGC API Features (geoportal.tmlmobilidade.pt/ogc-api), CC BY 4.0 (dados.gov.pt records `stops` and
# `rede-de-servicos-da-carris-metropolitana`, updated 2026-09-29): gtfs_stops (12 702 stops, 18 AML municipalities) and
# dados_harmonizados_rede_servicos_cm (1 911 route patterns as lines; id ends in <line>_<direction>_<pattern>). Paged by hand
# (limit/offset, GeoJSON in CRS84): GDAL's OAPIF driver asks for the storage CRS as http://…/EPSG/0/3763 and this server only
# lists the https:// spelling (HTTP 400, 2026-09-30). Every attribute read as text (-fieldTypeToString All: one file per page,
# each typed on its own). Metro de Lisboa GTFS (dados.gov.pt gtfs-do-metropolitano-de-lisboa, CC BY 4.0, feed of 2026-01-14,
# 0.3 MB): the 50 stations (stops without a parent) and one line per shape, named through trips → routes. The stops'
# geometry in that API is broken (one point for all), so the point comes from stop_lat / stop_lon. NOT loaded:
# timetables — the Carris Metropolitana GTFS (99 MB) has no licence on its dados.gov.pt record; CP, Fertagus and the ferries
# publish no open GTFS found (data/inventory.md §5).
mkdir -p "$RAW/transportes"
OAPI=https://geoportal.tmlmobilidade.pt/ogc-api/collections
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open._cm_stops, open._cm_rede, open._ml_stops, open._ml_shapes, open._ml_routes, open._ml_trips;"
for spec in "gtfs_stops|cm_stops|_cm_stops" "dados_harmonizados_rede_servicos_cm|cm_rede|_cm_rede"; do
  IFS='|' read -r COLL PRE TBL <<< "$spec"
  off=0; mode=-overwrite
  while :; do
    f="$RAW/transportes/${PRE}_$off.geojson"
    fetch_file "$OAPI/$COLL/items?f=json&limit=1000&offset=$off" "$f" "tml_${PRE}_$off" || break
    jq -e '.features' "$f" >/dev/null || { echo "WARN: $COLL offset $off — not a FeatureCollection: $(head -c 200 "$f")"; rm -f "$f"; break; }
    n=$(jq '.features | length' "$f"); echo "   $COLL offset $off: $n features"
    [ "$n" -gt 0 ] || break
    # shellcheck disable=SC2086
    ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -nln "open.$TBL" "${OGR_COMMON[@]}" $mode -fieldTypeToString All -lco PRECISION=NO \
      -oo FLATTEN_NESTED_ATTRIBUTES=YES -oo NESTED_ATTRIBUTE_SEPARATOR=_
    mode=-append
    [ "$n" -lt 1000 ] && break
    off=$((off + 1000))
  done
done
ML_ZIP="$RAW/transportes/metro_lisboa_gtfs.zip"
if fetch_file https://dados.gov.pt/s/resources/gfts-do-metropolitano-de-lisboa/20260114-115938/gtfs.zip "$ML_ZIP" metro_lisboa_gtfs; then
  for L in stops routes trips; do
    # the GTFS driver declares no CRS: GTFS coordinates are WGS 84 by specification
    ogr2ogr -f PostgreSQL "$OGR_PG" "$ML_ZIP" "$L" -nln "open._ml_$L" -s_srs EPSG:4326 -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom -lco PRECISION=NO -fieldTypeToString All -overwrite
  done
  ogr2ogr -f PostgreSQL "$OGR_PG" "$ML_ZIP" shapes_geom -nln open._ml_shapes -s_srs EPSG:4326 -t_srs EPSG:3763 -lco GEOMETRY_NAME=geom -nlt PROMOTE_TO_MULTI \
    -lco PRECISION=NO -fieldTypeToString All -overwrite
fi
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.tp_paragens, open.tp_percursos;
CREATE TABLE open.tp_paragens (operador text, paragem_id text, nome text, dico text, concelho text, localidade text, estado text,
  acessivel text, url text, geom geometry(Point, 3763));
-- the collection's geometry is the same point for all 12 702 stops (-8.1332, 39.6686 = the origin of PT-TM06, i.e. (0, 0) mis-converted;
-- checked 2026-09-30) while stop_lat / stop_lon are right → the point is built from them
INSERT INTO open.tp_paragens SELECT 'Carris Metropolitana', stop_id, stop_name, lpad(municipality_id, 4, '0'), municipality_name, locality,
  operational_status, wheelchair_boarding, stop_url,
  ST_Transform(ST_SetSRID(ST_MakePoint(stop_lon::float8, stop_lat::float8), 4326), 3763)::geometry(Point, 3763)
  FROM open._cm_stops WHERE stop_lon ~ '^-?[0-9.]+$' AND stop_lat ~ '^-?[0-9.]+$';
CREATE TABLE open.tp_percursos (operador text, linha text, sentido text, percurso_id text, nome text, geom geometry(MultiLineString, 3763));
INSERT INTO open.tp_percursos SELECT 'Carris Metropolitana', substring(id from '_([^_]+)_[0-9]+_[0-9]+$'), substring(id from '_([0-9]+)_[0-9]+$'),
  id, name_value, geom FROM open._cm_rede;
DO $$ BEGIN
  IF to_regclass('open._ml_stops') IS NOT NULL THEN
    -- stations = stops without a parent (44 plain + 6 interchange parents; the 24 platforms point to their parent)
    INSERT INTO open.tp_paragens SELECT 'Metropolitano de Lisboa', stop_id, stop_name, NULL, NULL, NULL, NULL, NULL, stop_url, ST_GeometryN(geom, 1)
      FROM open._ml_stops WHERE coalesce(parent_station, '') = '';
    INSERT INTO open.tp_percursos SELECT 'Metropolitano de Lisboa', r.route_long_name, t.direction_id, s.shape_id, t.trip_headsign, s.geom
      FROM open._ml_shapes s
      LEFT JOIN LATERAL (SELECT route_id, direction_id, trip_headsign FROM open._ml_trips x WHERE x.shape_id = s.shape_id LIMIT 1) t ON true
      LEFT JOIN open._ml_routes r ON r.route_id = t.route_id;
  END IF;
END $$;
DROP TABLE IF EXISTS open._cm_stops, open._cm_rede, open._ml_stops, open._ml_shapes, open._ml_routes, open._ml_trips;
CREATE INDEX ON open.tp_paragens USING GIST (geom); CREATE INDEX ON open.tp_percursos USING GIST (geom);
SQL
tag_points tp_paragens
trim_to_regions tp_percursos line nodedupe; keep_study_area tp_percursos
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('tp_carris_metropolitana','Carris Metropolitana — paragens e percursos (padrões de linha) da rede rodoviária da AML','Transportes Metropolitanos de Lisboa (TML)','CC BY 4.0 (dados.gov.pt stops, rede-de-servicos-da-carris-metropolitana)','https://geoportal.tmlmobilidade.pt/ogc-api/collections/{gtfs_stops,dados_harmonizados_rede_servicos_cm}','dados.gov.pt atualizado 2026-09-29',3763,'no timetables (the full GTFS has no stated licence)'),
 ('tp_metro_lisboa','Metropolitano de Lisboa — estações e linhas (GTFS)','Metropolitano de Lisboa, E.P.E.','CC BY 4.0 (dados.gov.pt gtfs-do-metropolitano-de-lisboa)','https://dados.gov.pt/s/resources/gfts-do-metropolitano-de-lisboa/20260114-115938/gtfs.zip','feed de 2026-01-14',3763,'stations = GTFS stops without a parent')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.tp_paragens WHERE operador = 'Carris Metropolitana')
  + (SELECT count(*) FROM open.tp_percursos WHERE operador = 'Carris Metropolitana') WHERE id = 'tp_carris_metropolitana';
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.tp_paragens WHERE operador = 'Metropolitano de Lisboa')
  + (SELECT count(*) FROM open.tp_percursos WHERE operador = 'Metropolitano de Lisboa') WHERE id = 'tp_metro_lisboa';
SQL
psql "$PG_DSN" -c "SELECT operador, region, count(*) AS stops FROM open.tp_paragens GROUP BY 1, 2 ORDER BY 1, 2;" \
  -c "SELECT operador, count(DISTINCT linha) AS lines, count(*) AS patterns, round((sum(ST_Length(geom)) / 1000)::numeric) AS km FROM open.tp_percursos GROUP BY 1 ORDER BY 1;"
fi

# arcgis_envelope_pages URL FIELDS STEM ID PAGE TABLE — page an ArcGIS MapServer layer's query over the study-area envelope
# (EPSG:3763) into open.TABLE (created by the first page, appended after), one cached ESRI JSON file per page.
# What: the paging loop of stage lneg, shared by stages geologia and dgeg (2026-10-01). Depends on: t2_bbox, fetch_file,
# jq, ogr2ogr; OGR_COMMON. Used by: stages geologia, dgeg. Ao mexer: an ArcGIS error is an HTTP 200 with {"error": …} —
# it must never be cached; every page goes in as unsized text/numbers (-lco PRECISION=NO, docs/lessons.md 2026-09-30).
arcgis_envelope_pages() {
  local url="$1" fields="$2" stem="$3" id="$4" page="$5" tbl="$6" off=0 n f env mode=-overwrite X0 Y0 X1 Y1
  read -r X0 Y0 X1 Y1 <<< "$(t2_bbox 3763)"
  env=$(jq -rn --arg a "$X0" --arg b "$Y0" --arg c "$X1" --arg d "$Y1" \
    '{xmin: ($a|tonumber), ymin: ($b|tonumber), xmax: ($c|tonumber), ymax: ($d|tonumber), spatialReference: {wkid: 3763}} | tojson | @uri')
  psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open.$tbl;"
  while :; do
    f="${stem}_$off.json"
    fetch_file "$url/query?where=1%3D1&geometry=$env&geometryType=esriGeometryEnvelope&inSR=3763&spatialRel=esriSpatialRelIntersects&outFields=$fields&returnGeometry=true&outSR=3763&resultOffset=$off&resultRecordCount=$page&orderByFields=OBJECTID&f=json" \
      "$f" "${id}_$off" || return 1
    jq -e '.features' "$f" >/dev/null || { echo "WARN: $id — no features: $(head -c 200 "$f")"; rm -f "$f"; return 1; }
    n=$(jq '.features | length' "$f"); echo "   $id, offset $off: $n feature(s)"
    [ "$n" -gt 0 ] || break
    jq -e '[.features[].geometry | select(. == null)] | length == 0' "$f" >/dev/null \
      || { echo "WARN: $id — features without geometry (view-only service?)"; return 1; }
    ogr2ogr -f PostgreSQL "$OGR_PG" "$f" -nln "open.$tbl" "${OGR_COMMON[@]}" $mode -makevalid -lco PRECISION=NO
    mode=-append
    [ "$n" -lt "$page" ] && break
    off=$((off + page))
  done
}

if stage geologia; then
echo "== LNEG — Carta Geológica de Portugal 1:500 000 (5.ª ed., 1992), vector, Lisbon study area (Tier 2; CC BY 4.0)"
# ArcGIS MapServer sig.lneg.pt/server/rest/services/CGP500k, layer 2 "Geologia do Continente": ONE multipolygon per
# lithostratigraphic unit for the whole mainland (282 rows; 77 meet the study-area envelope, 2026-10-01) → split per region
# and trimmed like every layer → open.lneg_geologia (codigo, descricao, grupo, zona, intrusao, intrusao_tipo, eonotema,
# eratema, sistema, serie — the published text, trimmed). Why 1:500 000: the AML map at 1:100 000 (2005, CC BY on
# dados.gov.pt) is published as two images (JPG/PDF) only, and the continuous 1:200 000 prototype (GeologiaUnica200k, CC BY)
# covers 1 km² of the 7 512 km² study area (measured 2026-10-01) → a regional reading: 0.5 mm on the map = 250 m on the
# ground; never a site-level foundation fact. Licence: CC BY 4.0 (dados.gov.pt carta-geologica-de-portugal-a-escala-1-500-000);
# the LNEG geoPortal legal notice adds "non-commercial, cite the source" → both in dataset_meta, as for the fire-hazard map.
mkdir -p "$RAW/lneg"
fetch_file "https://sig.lneg.pt/server/rest/services/CGP500k/MapServer/2?f=json" "$RAW/lneg/cgp500k_layer_2.json" lneg_cgp500k_layer_2 || true
if arcgis_envelope_pages https://sig.lneg.pt/server/rest/services/CGP500k/MapServer/2 '*' "$RAW/lneg/cgp500k" lneg_geologia 1000 _geologia_raw; then
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open._geologia;
-- ogr2ogr lower-cases the published field names and keeps their accents ("código", "descrição", …)
CREATE TABLE open._geologia AS SELECT objectid::bigint AS objectid, btrim("código") AS codigo, btrim("descrição") AS descricao,
  btrim("descrição1") AS grupo, btrim(zona) AS zona, btrim("intrusões_plutónicas") AS intrusao,
  btrim("intrusões_plutónicas1") AS intrusao_tipo, btrim(eonotema) AS eonotema, btrim(eratema) AS eratema,
  btrim(sistema) AS sistema, btrim("série") AS serie, geom FROM open._geologia_raw;
DROP TABLE open._geologia_raw;
SQL
trim_to_regions _geologia; keep_study_area _geologia
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.lneg_geologia;
ALTER TABLE open._geologia RENAME TO lneg_geologia;
CREATE INDEX ON open.lneg_geologia USING GIST (geom);
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('lneg_geologia','Carta Geológica de Portugal à escala 1:500 000 (5.ª edição) — unidades litostratigráficas do continente','LNEG — Laboratório Nacional de Energia e Geologia (Serviços Geológicos de Portugal)','CC BY 4.0 (dados.gov.pt carta-geologica-de-portugal-a-escala-1-500-000); aviso legal do geoPortal LNEG: uso não comercial, citar a fonte','https://sig.lneg.pt/server/rest/services/CGP500k/MapServer/2','1992 (5.ª edição)',3763,'1:500 000 — regional reading only (0.5 mm = 250 m); the AML 1:100 000 map is images only and the 1:200 000 continuous prototype does not cover the study area (2026-10-01)')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.lneg_geologia) WHERE id = 'lneg_geologia';
SQL
psql "$PG_DSN" -c "SELECT zona, count(DISTINCT codigo) AS units, count(*) AS n, round((sum(ST_Area(geom)) / 1e6)::numeric) AS km2 FROM open.lneg_geologia GROUP BY 1 ORDER BY 4 DESC;"
fi
fi

if stage dgeg; then
echo "== DGEG — solar power plants licensed or being licensed, Lisbon study area (Tier 2)"
# ArcGIS MapServer servergeo.dgeg.gov.pt/arcgis/rest/services/Visualizadores/CS, layer 0 "Centrais Solares": polygons in
# EPSG:3763, one row per park, sub-park or block (745 on the mainland, 147 meet the study-area envelope, 2026-10-01) →
# open.dgeg_centrais_solares with the published fields EXCEPT the owner (`proprietario`): no rule needs it and a licence
# holder can be a natural person. `lic_exploracao` empty = no operating licence yet (being licensed); `subtipo_instalacao`
# also holds UPAC (self-consumption), storage and the parks' own substations — the site rules filter, the load does not.
# Licence: dados.gov.pt record `centrais-solares` says CC BY 4.0, the service's WFS capabilities say CC BY-NC 4.0 → the
# stricter applies (non-commercial, attribution); both in dataset_meta. Feeds the PV profile's cumulative-effect rule.
mkdir -p "$RAW/dgeg"
DGEG_FIELDS="objectid,processo,nome,subparque,tipo_central,tipo_instalacao,subtipo_instalacao,sobreequipamento,lic_producao,data_lic_producao,lic_exploracao,data_exploracao,potencia_geradorkw,potencia_instaladakva,potencia_ligacaokva,area_bloco,area_total,concelho,distrito"
if arcgis_envelope_pages https://servergeo.dgeg.gov.pt/arcgis/rest/services/Visualizadores/CS/MapServer/0 "$DGEG_FIELDS" \
    "$RAW/dgeg/centrais_solares" dgeg_centrais_solares 2000 _dgeg; then
# a park and its blocks are separate rows that may share edges, never geometry → no geometry-hash dedupe
trim_to_regions _dgeg poly nodedupe; keep_study_area _dgeg
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.dgeg_centrais_solares;
ALTER TABLE open._dgeg RENAME TO dgeg_centrais_solares;
ALTER INDEX IF EXISTS open._dgeg_pkey RENAME TO dgeg_centrais_solares_pkey;
ALTER INDEX IF EXISTS open._dgeg_geom_geom_idx RENAME TO dgeg_centrais_solares_geom_geom_idx;
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('dgeg_centrais_solares','Centrais solares de Portugal continental licenciadas ou em licenciamento pela DGEG (parques, subparques e blocos; sem o titular)','DGEG — Direção-Geral de Energia e Geologia','CC BY 4.0 (dados.gov.pt centrais-solares) vs CC BY-NC 4.0 (WFS do serviço) — aplica-se a mais restritiva: uso não comercial, com atribuição','https://servergeo.dgeg.gov.pt/arcgis/rest/services/Visualizadores/CS/MapServer/0','dados.gov.pt atualizado 2025-01-14; serviço consultado 2026-10-01',3763,'owner field not loaded; empty lic_exploracao = being licensed; includes UPAC, storage and park substations')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.dgeg_centrais_solares) WHERE id = 'dgeg_centrais_solares';
SQL
# park-level fields (installed / connection power, total area) repeat on every block row: count processes, never sum them per row
psql "$PG_DSN" -c "SELECT tipo_central, subtipo_instalacao, coalesce(lic_exploracao, '') <> '' AS licenca_exploracao, count(DISTINCT processo) AS processos, count(*) AS n, round((sum(ST_Area(geom)) / 1e4)::numeric) AS ha FROM open.dgeg_centrais_solares GROUP BY 1, 2, 3 ORDER BY 5 DESC;"
fi
fi

if stage ruido_end; then
echo "== Noise contours reported under the Environmental Noise Directive, round 2022 (EEA, Portugal) — Tier 2"
# What: the EEA's GeoPackage for Portugal (data set 853e72e4-4642-47d1-8556-2cc231bd43e0, "Noise contours data reported
# under END 2022 (vector)", Mar. 2026; 10 layers, 663 features, EPSG:3035): agglomeration maps (roads, railways, industry,
# airports; Lden and Lnight in 5 dB bands, including "< 40 dB" — the whole agglomeration is modelled) and major-road
# corridors (only near the road; outside = not mapped). In the study area (2026-10-01): the agglomerations of Amadora,
# Odivelas and Oeiras (100 % of each; Oeiras is dropped — its municipal map is loaded by stage ruido) and ~156 km² of
# major-road corridors (Lden); geometry simplified at 2 m; NOT Lisboa (absent from the EEA file — the
# country can mark contours restricted). → open.ruido_end (fonte, indicador, classe as published, db_min, db_max, origem =
# reported file id, dico for agglomerations). Each agglomeration is cut to its own municipality (only its sources are
# modelled — as for Oeiras's MER in stage ruido); a corridor carries that road's noise only, never the total.
# Licence: EEA metadata — "available for research and non-profit purposes" → non-commercial; display is the author's call.
# Depends on: fetch_file, trim_to_regions, keep_study_area, caop_municipios. Used by: nothing yet (site engine: window).
# Ao mexer: Oeiras is also in ruido_mapas (CM Oeiras MER 2022) — the municipal map is the primary source there.
mkdir -p "$RAW/ruido_eea"
EEA_URL="https://sdi.eea.europa.eu/datashare/s/sptXqwkQr5g7Bp5/download?path=%2Feea_v_3035_1_k_noise-contours-end2022_p_2026_v01_r00&files=PT.gpkg"
if fetch_file "$EEA_URL" "$RAW/ruido_eea/PT.gpkg" eea_noise_contours_end2022_pt; then
psql "$PG_DSN" -q -c "DROP TABLE IF EXISTS open._ruido_end;" \
  -c "CREATE TABLE open._ruido_end (fonte text, indicador text, classe text, origem text, geom geometry(MultiPolygon, 3763));"
for L in $(ogrinfo -ro -q "$RAW/ruido_eea/PT.gpkg" 2>/dev/null | sed -nE 's/^[0-9]+: (NoiseContours_[A-Za-z]+_L[a-z]+) .*/\1/p'); do
  # the reported file name in sourceIdentifier is the only place that names the agglomeration or road (AG_PT_00_n / RD_PT_…);
  # it is cut out in PostgreSQL below (the OGR SQLite dialect has no regexp_replace)
  ogr2ogr -f PostgreSQL "$OGR_PG" "$RAW/ruido_eea/PT.gpkg" -nln open._ruido_end -append -nlt MULTIPOLYGON -t_srs EPSG:3763 -makevalid \
    -dialect SQLite -sql "SELECT source AS fonte, '${L##*_}' AS indicador, category AS classe, sourceIdentifier AS origem, geom FROM \"$L\"" \
    2>&1 | grep -v '^$' || true
done
psql "$PG_DSN" -Atc "SELECT '   EEA PT: ' || count(*) || ' contours, ' || count(DISTINCT origem) || ' reported files' FROM open._ruido_end"
read -r X0 Y0 X1 Y1 <<< "$(t2_bbox 3763)"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -v x0="$X0" -v y0="$Y0" -v x1="$X1" -v y1="$Y1" <<'SQL'
-- the whole country's corridors through the trim took > 10 min (2026-10-01) → keep only what meets the study-area envelope first
DELETE FROM open._ruido_end WHERE NOT ST_Intersects(geom, ST_MakeEnvelope(:x0, :y0, :x1, :y1, 3763));
UPDATE open._ruido_end SET origem = substring(origem FROM '([A-Z]{2}_PT_[0-9_]+)\.gpkg') WHERE origem LIKE '%.gpkg%';
ALTER TABLE open._ruido_end ADD COLUMN dico text, ADD COLUMN db_min int, ADD COLUMN db_max int;
-- an agglomeration map belongs to the municipality holding most of its area; cut it to that municipality
WITH a AS (SELECT origem, ST_Union(geom) g FROM open._ruido_end WHERE origem LIKE 'AG_%' GROUP BY origem),
     m AS (SELECT DISTINCT ON (a.origem) a.origem, c.dico FROM a JOIN open.caop_municipios c ON ST_Intersects(c.geom, a.g)
           ORDER BY a.origem, ST_Area(ST_Intersection(c.geom, a.g)) DESC)
UPDATE open._ruido_end r SET dico = m.dico FROM m WHERE m.origem = r.origem;
-- Oeiras: the municipal MER 2022 (stage ruido, CC BY) is the primary source → its EEA copy is not kept (−⅓ of the vertices)
DELETE FROM open._ruido_end WHERE dico = '1110';
UPDATE open._ruido_end r SET geom = ST_Multi(ST_CollectionExtract(ST_Intersection(r.geom, c.geom), 3))
  FROM open.caop_municipios c WHERE c.dico = r.dico AND NOT ST_Covers(c.geom, r.geom);
-- 3.66 M vertices / 197 MB / a 90 MB dump as published (2026-10-01): contours computed on a grid of receivers of several
-- metres carry sub-metre vertices → 2 m simplification keeps 43 % of the vertices and changes the band areas by 0.005 %
UPDATE open._ruido_end SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_SimplifyPreserveTopology(geom, 2)), 3));
DELETE FROM open._ruido_end WHERE geom IS NULL OR ST_IsEmpty(geom);
-- bands as published ("Lden5054", "LnightLowerThan40", "LdenGreaterThan75") → numbers, never re-binned
UPDATE open._ruido_end SET
  db_min = CASE WHEN classe ~ 'LowerThan' THEN NULL WHEN classe ~ 'GreaterThan' THEN substring(classe FROM '([0-9]+)$')::int
                ELSE substring(classe FROM '([0-9]{2})[0-9]{2}$')::int END,
  db_max = CASE WHEN classe ~ 'LowerThan' THEN substring(classe FROM '([0-9]+)$')::int - 1 WHEN classe ~ 'GreaterThan' THEN NULL
                ELSE substring(classe FROM '[0-9]{2}([0-9]{2})$')::int END;
SQL
trim_to_regions _ruido_end; keep_study_area _ruido_end
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.ruido_end;
ALTER TABLE open._ruido_end RENAME TO ruido_end;
CREATE INDEX ON open.ruido_end USING GIST (geom);
VACUUM FULL open.ruido_end;
INSERT INTO open.dataset_meta (id, title, publisher, licence, source_url, reference_date, srid, notes) VALUES
 ('ruido_end','Contornos de ruído reportados ao abrigo da Diretiva 2002/49/CE, ronda de 2022 — aglomerações (estradas, ferrovias, indústria, aeroportos) e grandes estradas, Lden e Lnight em bandas de 5 dB (Portugal)','Agência Europeia do Ambiente (EEA), a partir dos reportes de Portugal (APA)','EEA: «available for research and non-profit purposes» (metadados 853e72e4) — uso não comercial; contornos marcados como restritos pelo país excluídos','https://sdi.eea.europa.eu/catalogue/srv/api/records/853e72e4-4642-47d1-8556-2cc231bd43e0','ronda END 2022 (reportes até 2024-11-18; publicado mar. 2026)',3763,'study area: Amadora, Odivelas, Oeiras (whole agglomerations, each cut to its municipality) + major-road corridors (that road only); Lisboa absent')
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date, notes = EXCLUDED.notes;
UPDATE open.dataset_meta SET row_count = (SELECT count(*) FROM open.ruido_end) WHERE id = 'ruido_end';
SQL
psql "$PG_DSN" -c "SELECT fonte, indicador, coalesce(c.concelho, '(major road corridor)') AS onde, count(*) AS n, round((sum(ST_Area(r.geom)) / 1e6)::numeric, 1) AS km2 FROM open.ruido_end r LEFT JOIN open.caop_municipios c USING (dico) GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;"
fi
fi

if stage grelha; then
echo "== subdivided helpers for constraints_grid (ST_Subdivide, 128 vertices) — same attributes, ~80× faster cell queries"
# Derived copies, not datasets (no dataset_meta rows): identical per-cell answers were checked on 349 cells (2026-09-27).
# Re-run after any change to the source layers. grid_cos holds only the newest COS edition (today's land cover).
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q <<'SQL'
DROP TABLE IF EXISTS open.grid_perigosidade, open.grid_zonas_inundaveis, open.grid_perigo_inundacao, open.grid_arpsi,
  open.grid_protegidas, open.grid_crus, open.grid_ardidas, open.grid_cos, open.grid_ren, open.grid_ran, open.grid_ren_linhas, open.grid_srup,
  open.grid_apa_captacao, open.grid_massas_subterraneas, open.grid_ruido, open.grid_lneg, open.grid_geologia, open.grid_ruido_end;
CREATE TABLE open.grid_perigosidade AS SELECT classe_ord, classe, ST_Subdivide(geom, 128) AS geom FROM open.icnf_perigosidade;
CREATE TABLE open.grid_zonas_inundaveis AS SELECT ST_Subdivide(geom, 128) AS geom FROM open.apa_zonas_inundaveis;
CREATE TABLE open.grid_perigo_inundacao AS SELECT perigo, ST_Subdivide(geom, 128) AS geom FROM open.apa_perigo_inundacao;
CREATE TABLE open.grid_arpsi AS SELECT ST_Subdivide(geom, 128) AS geom FROM open.apa_arpsi;
CREATE TABLE open.grid_protegidas AS SELECT nome, rede, ST_Subdivide(geom, 128) AS geom FROM open.icnf_areas_protegidas;
CREATE TABLE open.grid_crus AS SELECT classe, categoria, designacao_pdm, esquema, ST_Subdivide(geom, 128) AS geom FROM open.dgt_crus;
CREATE TABLE open.grid_ardidas AS SELECT ano, ST_Subdivide(geom, 128) AS geom FROM open.icnf_areas_ardidas;
-- REN/RAN: one multipolygon per municipality (thousands of vertices) → subdividing matters most here
DO $$ BEGIN   -- optional layers (stage ren_ran)
  IF to_regclass('open.dgt_ren') IS NOT NULL THEN
    CREATE TABLE open.grid_ren AS SELECT tipologia, diploma, ST_Subdivide(geom, 128) AS geom FROM open.dgt_ren; END IF;
  IF to_regclass('open.dgt_ran') IS NOT NULL THEN
    CREATE TABLE open.grid_ran AS SELECT concelho, ST_Subdivide(geom, 128) AS geom FROM open.dgt_ran; END IF;
  IF to_regclass('open.dgt_ren_linhas') IS NOT NULL THEN
    CREATE TABLE open.grid_ren_linhas AS SELECT concelho, ST_Subdivide(geom, 128) AS geom FROM open.dgt_ren_linhas; END IF;
  IF to_regclass('open.dgt_srup') IS NOT NULL THEN   -- stage srup (Tier 2, Lisbon study area)
    CREATE TABLE open.grid_srup AS SELECT familia, tipo, ST_Subdivide(geom, 128) AS geom FROM open.dgt_srup; END IF;
  IF to_regclass('open.apa_perimetros_captacao') IS NOT NULL THEN   -- stage apa_agua (Tier 2)
    CREATE TABLE open.grid_apa_captacao AS SELECT zona, origem, nome, diploma, ST_Subdivide(geom, 128) AS geom FROM open.apa_perimetros_captacao; END IF;
  IF to_regclass('open.apa_massas_subterraneas') IS NOT NULL THEN
    CREATE TABLE open.grid_massas_subterraneas AS SELECT codigo, nome, estado_global, ST_Subdivide(geom, 128) AS geom FROM open.apa_massas_subterraneas; END IF;
  IF to_regclass('open.ruido_mapas') IS NOT NULL THEN   -- stage ruido (Tier 2)
    CREATE TABLE open.grid_ruido AS SELECT concelho, indicador, classe, classe_id, ST_Subdivide(geom, 128) AS geom FROM open.ruido_mapas; END IF;
  IF to_regclass('open.lneg_menos_sensiveis') IS NOT NULL THEN   -- stage lneg (Tier 2)
    CREATE TABLE open.grid_lneg AS SELECT cenario, ST_Subdivide(geom, 128) AS geom FROM open.lneg_menos_sensiveis; END IF;
  IF to_regclass('open.lneg_geologia') IS NOT NULL THEN   -- stage geologia (Tier 2): national units, large multipolygons
    CREATE TABLE open.grid_geologia AS SELECT codigo, zona, ST_Subdivide(geom, 128) AS geom FROM open.lneg_geologia; END IF;
  IF to_regclass('open.ruido_end') IS NOT NULL THEN   -- stage ruido_end (Tier 2): agglomeration bands are large multipolygons
    CREATE TABLE open.grid_ruido_end AS SELECT fonte, indicador, classe, db_min, db_max, origem, ST_Subdivide(geom, 128) AS geom FROM open.ruido_end; END IF;
END $$;
DO $$ BEGIN
  IF to_regclass('open.cos_serie') IS NOT NULL AND EXISTS (SELECT 1 FROM open.cos_serie WHERE ano = 2025) THEN
    CREATE TABLE open.grid_cos AS SELECT label_n4, ano, ST_Subdivide(geom, 128) AS geom FROM open.cos_serie WHERE ano = 2025;
  ELSE
    CREATE TABLE open.grid_cos AS SELECT cos_label::text AS label_n4, 2023 AS ano, ST_Subdivide(geom, 128) AS geom FROM open.cos2023;
  END IF;
END $$;
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['grid_perigosidade','grid_zonas_inundaveis','grid_perigo_inundacao','grid_arpsi','grid_protegidas',
                           'grid_crus','grid_ardidas','grid_cos','grid_ren','grid_ran','grid_ren_linhas','grid_srup',
                           'grid_apa_captacao','grid_massas_subterraneas','grid_ruido','grid_lneg','grid_geologia','grid_ruido_end'] LOOP
    IF to_regclass('open.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('CREATE INDEX ON open.%I USING GIST (geom)', t);
    EXECUTE format('ANALYZE open.%I', t);
  END LOOP;
END $$;
SQL
psql "$PG_DSN" -c "SELECT c.relname AS helper, pg_size_pretty(pg_total_relation_size(c.oid)) AS size FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'open' AND c.relname LIKE 'grid\_%' AND c.relkind = 'r' ORDER BY 1;"
fi

if stage qa; then
echo "== QA — every trimmed geometry must lie inside its tagged region (1 m tolerance)"
# Catches wrong region tags (features spanning several regions — docs/lessons.md) and islands left outside. Prints a table;
# WARNs, never deletes. QA_TABLES="dgt_ren dgt_ran" limits the check to some tables. One region per query and
# ST_Covers(region, x): the region geometry stays the same row after row, so PostGIS prepares it once (ST_CoveredBy is
# never prepared: ~50 min for 3 regions, hours once lisboa_tejo came in — docs/lessons.md, 2026-09-30).
QA_TABLES="${QA_TABLES:-cos2023 cos_serie icnf_perigosidade apa_perigo_inundacao apa_zonas_inundaveis apa_arpsi icnf_areas_ardidas icnf_areas_protegidas dgt_crus dgt_ren dgt_ran dgt_ren_linhas dgt_construcoes dgt_srup dgt_srup_linhas ip_ferrovia ip_rede_rodoviaria osm_rede osm_energia_linhas apa_perimetros_captacao apa_massas_subterraneas ruido_mapas lneg_menos_sensiveis tp_percursos lneg_geologia dgeg_centrais_solares ruido_end}"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -q -v qa_tables="$QA_TABLES" <<'SQL'
DROP TABLE IF EXISTS pg_temp.qa_r;
CREATE TEMP TABLE qa_r AS SELECT region, ST_Union(geom) AS g, ST_Buffer(ST_Union(geom), 1) AS gb FROM open.pilot_regions GROUP BY region;
CREATE TEMP TABLE qa_part (tbl text, n bigint, bad bigint, m2_outside double precision);
CREATE TEMP TABLE qa_list AS SELECT unnest(string_to_array(:'qa_tables', ' ')) AS t;
DO $$ DECLARE t text; rg text; BEGIN
  FOR t IN SELECT q.t FROM qa_list q LOOP
    IF to_regclass('open.' || t) IS NULL THEN CONTINUE; END IF;
    FOR rg IN SELECT region FROM qa_r ORDER BY 1 LOOP
      EXECUTE format($q$INSERT INTO qa_part SELECT %L, count(*), count(*) FILTER (WHERE NOT ST_Covers(r.gb, x.geom)),
        coalesce(sum(ST_Area(ST_Difference(x.geom, r.g))) FILTER (WHERE NOT ST_Covers(r.gb, x.geom)), 0)
        FROM open.%I x JOIN qa_r r ON r.region = x.region WHERE r.region = %L$q$, t, t, rg);
    END LOOP;
  END LOOP;
END $$;
CREATE TEMP TABLE qa AS SELECT tbl, sum(n)::bigint AS n, sum(bad)::bigint AS bad, round((sum(m2_outside) / 1e6)::numeric, 3) AS km2_outside FROM qa_part GROUP BY tbl;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM qa WHERE bad > 0) THEN RAISE WARNING 'QA: geometries outside their region — see table below'; END IF;
END $$;
SELECT * FROM qa ORDER BY bad DESC, tbl;
SQL
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
 ('cop_dem30','Copernicus DEM GLO-30 — altitude, declive (%) e orientação (°) reamostrados a 25 m; modelo de SUPERFÍCIE (copa e edifícios enviesam declive e orientação)','ESA / Copernicus (Airbus)','Copernicus DEM licence: free use with attribution (GLO-30 public)','https://copernicus-dem-30m.s3.amazonaws.com/','2011–2015 (TanDEM-X acquisitions)',3763),
 ('mdt_lidar2024','LiDAR 2024 — Modelo Digital do Terreno (MDT) 2 m → altitude, declive (%) e orientação (°) a 10 m (média do MDT de 2 m); modelo do TERRENO (sem edifícios nem vegetação); voos 04-2024 a 07-2025','Direção-Geral do Território','CC BY 4.0 (dgterritorio.gov.pt/dados-abertos: dados do Centro de Dados)','https://cdd.dgterritorio.gov.pt/dgt-be/v1/collections/MDT-2m','2024–2025 (LiDAR 2024; tiles publicados 2025)',3763),
 ('mconst_lidar2024','Mapa de Construções LiDAR 2024 — polígonos de edificado (Portugal continental)','Direção-Geral do Território','CC BY 4.0 (dados.gov.pt mapa-de-construcoes-lidar-2024)','https://geo2.dgterritorio.gov.pt/lidar/MConst_LiDAR2024_PTcont-gpkg.zip','voo LiDAR 2024 (publ. 2026-08-25)',3763),
 ('dgt_ren','Reserva Ecológica Nacional (SRUP) — delimitação municipal em vigor, com exclusões e diploma','Direção-Geral do Território (SNIT) / CCDR','CC BY 4.0 (dados.gov.pt srup-reserva-ecologica-nacional)','https://servicos.dgterritorio.pt/SDISNITWFSSRUP_REN_{NORTE,CENTRO,LVT}/WFService.aspx','por município: diploma (diploma, dr) e data da geometria na tabela',3763),
 ('dgt_ren_linhas','Reserva Ecológica Nacional (SRUP) — linhas de água (leitos dos cursos de água), onde a delimitação municipal as publica','Direção-Geral do Território (SNIT) / CCDR','CC BY 4.0 (dados.gov.pt srup-reserva-ecologica-nacional)','https://servicos.dgterritorio.pt/SDISNITWFSSRUP_REN_{NORTE,CENTRO,LVT}/WFService.aspx (Linhas_de_Agua_*)','por município',3763),
 ('dgt_ran','Reserva Agrícola Nacional (SRUP) — delimitação municipal em vigor','Direção-Geral do Território (SNIT)','CC BY 4.0 (dados.gov.pt srup-reserva-agricola-nacional)','https://servicos.dgterritorio.pt/SDISNITWFSSRUP_RAN_PT1/WFService.aspx','por município: data da geometria na tabela',3763)
ON CONFLICT (id) DO UPDATE SET retrieved_at = now(), source_url = EXCLUDED.source_url, licence = EXCLUDED.licence,
  title = EXCLUDED.title, reference_date = EXCLUDED.reference_date;
-- row counts: id → table; a table that is not loaded is skipped (a plain UNION over missing tables fails to parse)
DO $$ DECLARE r record; n bigint; BEGIN
  FOR r IN SELECT * FROM (VALUES ('caop2025','caop_freguesias'), ('cos2023','cos2023'), ('icnf_perigosidade','icnf_perigosidade'),
      ('apa_perigo','apa_perigo_inundacao'), ('apa_zonas_inundaveis','apa_zonas_inundaveis'), ('apa_arpsi','apa_arpsi'),
      ('apa_marcas_cheia','apa_marcas_cheia'), ('ine_bgri2021','ine_bgri2021'), ('icnf_areas_ardidas','icnf_areas_ardidas'),
      ('icnf_areas_protegidas','icnf_areas_protegidas'), ('dgt_crus','dgt_crus'), ('ine_precos_habitacao','ine_precos_habitacao'),
      ('ipma_rcm','ipma_rcm_snapshot'), ('cop_dem30','dem_slope'), ('mdt_lidar2024','dem_mdt_slope'), ('mconst_lidar2024','dgt_construcoes'),
      ('dgt_ren','dgt_ren'), ('dgt_ran','dgt_ran'), ('dgt_ren_linhas','dgt_ren_linhas')) v(id, tbl) LOOP
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

-- data/schema.sql — PostGIS schema for Território Explicado (pre-existing data platform)
-- What: creates schema `open`, the provenance table and the lookup functions used by the agent and by the
--       Zetaris views: facts_at (point), facts_for / facts_in (point or drawn plot, share of the plot per value),
--       constraints_grid (facts per cell around a place, no verdicts), slope_class / aspect_class (shared bands) and
--       their EN twins, hazard_en / fmt_num (label helpers),
--       relief_at (relief value at a point: DGT LiDAR 2024 terrain model first, Copernicus surface model as fallback).
--       Idempotent. REN/RAN and buildings answer "outside"/"none" only where the data is loaded — elsewhere they say
--       "not available — not consulted" (unknown is never reported as free).
-- Depends on: PostGIS (+ postgis_raster for the relief rasters); tables loaded by data/etl/load.sh (open.caop_*,
--       open.cos2023, open.cos_serie, open.icnf_perigosidade, open.apa_*, open.ine_bgri2021, open.icnf_areas_ardidas,
--       open.icnf_areas_protegidas, open.dgt_crus, open.ine_precos_habitacao, open.ipma_rcm_snapshot, open.dem_mdt_elev,
--       open.dem_mdt_slope, open.dem_mdt_aspect (DGT MDT, 10 m), open.dem_elev, open.dem_slope, open.dem_aspect (Copernicus
--       fallback, 25 m), open.dgt_ren, open.dgt_ren_linhas, open.dgt_ran, open.dgt_construcoes, open.pilot_regions /
--       pilot_union; optional subdivided helpers open.grid_*) — every function guards missing tables.
-- Used by: data/etl/load.sh (runs it first), data/views.sql, data/etl/golden_fill.sh, the rehearsal explorer, the
--       agent's pg tool (inside the window).
-- When changing: the output columns are the evidence contract — facts_at (dataset, attribute, value, geom_geojson,
--       meta_id, sql_hint, level, label_pt, label_en, tag_pt, tag_en, caveat); facts_for/facts_in add share_pct and
--       area_ha after sql_hint; constraints_grid's columns are read by the alternatives map (by name). Changing them
--       changes the agent's evidence schema. `value` is the English evidence text (agent, golden files); the status
--       columns are what a UI shows — keep `value` byte-identical when only the labels change (golden diff = 0).

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS open;

CREATE TABLE IF NOT EXISTS open.dataset_meta (
  id             text PRIMARY KEY,          -- e.g. caop2025
  title          text NOT NULL,
  publisher      text NOT NULL,
  licence        text NOT NULL,
  source_url     text NOT NULL,
  reference_date text,                      -- the data's own reference (year/date as published)
  srid           integer NOT NULL DEFAULT 3763,
  retrieved_at   timestamptz NOT NULL DEFAULT now(),
  checksum       text,
  row_count      bigint,
  notes          text
);

-- Read-only role for the agent and for Zetaris. Password is set out of band (never in this file).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'territorio_ro') THEN
    CREATE ROLE territorio_ro LOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA open TO territorio_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA open TO territorio_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA open GRANT SELECT ON TABLES TO territorio_ro;

-- slope_class(pct): slope class label; the bands MUST match data/pretensoes.json `slope_classes_pct` (the agent's rules
-- use the same bands). Used by: facts_at, facts_in, constraints_grid.
CREATE OR REPLACE FUNCTION open.slope_class(pct numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN pct IS NULL THEN NULL WHEN pct < 5 THEN 'plano (0–5 %)' WHEN pct < 10 THEN 'suave (5–10 %)'
              WHEN pct < 15 THEN 'moderado (10–15 %)' WHEN pct < 25 THEN 'acentuado (15–25 %)'
              WHEN pct < 35 THEN 'muito acentuado (25–35 %)' ELSE 'escarpado (≥ 35 %)' END
$$;

-- aspect_class(deg): compass sector of a DEM aspect in degrees clockwise from north (dem_aspect); -9999 (any negative)
-- = flat, no aspect. Sectors of 45° centred on N, NE, … (PT abbreviations: SO = sudoeste, O = oeste, NO = noroeste).
-- Used by: facts_at, facts_in, constraints_grid. When changing: the agent's PV/farming rules read these labels.
CREATE OR REPLACE FUNCTION open.aspect_class(deg numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN deg IS NULL THEN NULL WHEN deg < 0 THEN 'plano (sem orientação)'
              ELSE (ARRAY['N','NE','E','SE','S','SO','O','NO'])[floor(mod(deg + 22.5, 360) / 45)::int + 1] END
$$;

-- slope_class_en(pct) / aspect_class_en(deg): English twins of slope_class / aspect_class for the label_en column
-- (same bands and sectors; the PT functions stay the ones the rules read). Depends on: —. Used by: facts_at, facts_in.
-- When changing: change the band limits together with slope_class (and data/pretensoes.json).
CREATE OR REPLACE FUNCTION open.slope_class_en(pct numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN pct IS NULL THEN NULL WHEN pct < 5 THEN 'flat (0–5 %)' WHEN pct < 10 THEN 'gentle (5–10 %)'
              WHEN pct < 15 THEN 'moderate (10–15 %)' WHEN pct < 25 THEN 'steep (15–25 %)'
              WHEN pct < 35 THEN 'very steep (25–35 %)' ELSE 'extremely steep (≥ 35 %)' END
$$;
CREATE OR REPLACE FUNCTION open.aspect_class_en(deg numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN deg IS NULL THEN NULL WHEN deg < 0 THEN 'flat (no aspect)'
              ELSE (ARRAY['N','NE','E','SE','S','SW','W','NW'])[floor(mod(deg + 22.5, 360) / 45)::int + 1] END
$$;

-- hazard_en(v): English for the Portuguese hazard / risk class words of the sources — ICNF perigosidade (muito alta …
-- sem perigosidade), APA perigo de inundação (Alto - Muito Alto, Médio, Baixo - Muito Baixo), IPMA RCM (reduzido …
-- máximo). Unknown words come back unchanged (a new class shows in Portuguese, never blank). Depends on: —.
-- Used by: facts_at, facts_in (label_en, tag_en). When changing: a source that renames its classes needs a line here.
CREATE OR REPLACE FUNCTION open.hazard_en(v text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE lower(v) WHEN 'muito alta' THEN 'very high' WHEN 'alta' THEN 'high' WHEN 'média' THEN 'medium'
              WHEN 'baixa' THEN 'low' WHEN 'muito baixa' THEN 'very low' WHEN 'sem perigosidade' THEN 'no hazard'
              WHEN 'alto - muito alto' THEN 'high – very high' WHEN 'médio' THEN 'medium' WHEN 'baixo - muito baixo' THEN 'low – very low'
              WHEN 'reduzido' THEN 'low' WHEN 'moderado' THEN 'moderate' WHEN 'elevado' THEN 'high'
              WHEN 'muito elevado' THEN 'very high' WHEN 'máximo' THEN 'maximum' ELSE v END
$$;

-- fmt_num(x, digits, lang): a number for the label columns — PT '1 234,5' (no-break space groups, decimal comma), EN
-- '1,234.5'; at most `digits` decimals, trailing zeros dropped; NULL → '?'. Locale-independent (to_char ',' and '.' are
-- literal, not lc_numeric). Depends on: —. Used by: facts_at, facts_in. When changing: labels only — `value` keeps the
-- raw numbers the agent and the golden files read.
CREATE OR REPLACE FUNCTION open.fmt_num(x numeric, digits integer DEFAULT 0, lang text DEFAULT 'pt') RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN x IS NULL THEN '?' WHEN lang = 'en' THEN s ELSE translate(s, ',.', U&'\00A0,') END
  FROM (SELECT rtrim(to_char(round(x, greatest(digits, 0)), 'FM999,999,999,990' || CASE WHEN digits > 0 THEN '.' || repeat('9', digits) ELSE '' END), '.') AS s) f
$$;

-- relief_at(p, v): value of one relief variable (v = 'elev' | 'slope' | 'aspect') at a point in EPSG:3763, with the
-- source that answered. The DGT LiDAR 2024 terrain model (open.dem_mdt_<v>, 10 m, buildings and canopy removed) wins
-- wherever it has a value; Copernicus GLO-30 (open.dem_<v>, 25 m SURFACE model) answers only where the MDT has none
-- (sea, Spain, missing tiles) and its note says so. Returns no row when neither has a value.
-- Depends on: the dem_mdt_* / dem_* rasters (load.sh stages relevo_mdt / relevo), either may be missing. Used by:
-- facts_at. When changing: meta_id must stay a dataset_meta id ('mdt_lidar2024' / 'cop_dem30'); the note is shown to
-- the user as part of the fact's value.
CREATE OR REPLACE FUNCTION open.relief_at(p geometry, v text)
RETURNS TABLE (val numeric, meta_id text, tbl text, note text) LANGUAGE plpgsql STABLE AS $$
DECLARE x numeric;
BEGIN
  IF to_regclass('open.dem_mdt_' || v) IS NOT NULL THEN
    EXECUTE format('SELECT ST_Value(d.rast, 1, $1)::numeric FROM open.%I d WHERE ST_Intersects(d.rast, $1) LIMIT 1', 'dem_mdt_' || v)
      INTO x USING p;
    IF x IS NOT NULL THEN
      RETURN QUERY SELECT x, 'mdt_lidar2024'::text, ('dem_mdt_' || v)::text, ' (DGT LiDAR 2024 MDT — terrain model, 10 m)'::text;
      RETURN;
    END IF;
  END IF;
  IF to_regclass('open.dem_' || v) IS NOT NULL THEN
    EXECUTE format('SELECT ST_Value(d.rast, 1, $1)::numeric FROM open.%I d WHERE ST_Intersects(d.rast, $1) LIMIT 1', 'dem_' || v)
      INTO x USING p;
    IF x IS NOT NULL THEN
      RETURN QUERY SELECT x, 'cop_dem30'::text, ('dem_' || v)::text,
        (' (Copernicus GLO-30 surface model at 25 m' || CASE WHEN v = 'slope' THEN ': canopy and buildings bias it' ELSE '' END
         || ' — no DGT LiDAR terrain value here)')::text;
    END IF;
  END IF;
END $$;

-- The fact functions changed their return type on 2026-09-28 (status columns): CREATE OR REPLACE cannot do that, so
-- they are dropped first (nothing depends on them in the catalogue — plpgsql callers resolve at run time). On the
-- server the owner must be re-set after this file runs (ALTER FUNCTION … OWNER TO territorio_rw, data/README.md).
DROP FUNCTION IF EXISTS open.facts_for(text);
DROP FUNCTION IF EXISTS open.facts_at(double precision, double precision);
DROP FUNCTION IF EXISTS open.facts_in(geometry);

-- facts_at(lon, lat): every layer that touches the point, one row per fact, with the geometry of the
-- intersected feature (simplified for the map) and the provenance id. Layers are added as they are
-- loaded; a missing table must not break the function, hence the EXISTS guards.
-- Status columns (2026-09-28, at the END so readers by name are unaffected; `value` is unchanged, English, for the agent
-- and the golden files) — written where the raw columns are at hand, so no reader ever parses `value`:
--   level    hi = inside a legal constraint (REN, RAN, protected area), a mapped flood zone or a high hazard class ·
--            md = conditions: medium hazard, burned, ARPSI, near a REN watercourse line · lo = outside a layer that IS
--            loaded for that municipality, low hazard, REN exclusion area · na = layer not available here — not
--            consulted (never "free") · in = context value without a status (census, price, relief, PDM class, COS)
--   label_pt / label_en  one-line reading in PT-PT / EN (PT number format in PT; place and class names stay Portuguese)
--   tag_pt / tag_en      short pill word when it is not the level's own word (hazard class, "Perto", "Exclusão", COS
--                        year, "Ardeu"); NULL = use the level's word
--   caveat   what this row does NOT know, as a code: relief_fallback (Copernicus surface model, no LiDAR value) ·
--            ren_lines_unpublished (REN watercourse lines not published/loaded for the municipality: "outside" covers
--            the polygons only) · census_whole_subsections (not area-weighted) · pilot_edge (the 200 m circle crosses
--            the edge of the loaded area); NULL = nothing to add
CREATE OR REPLACE FUNCTION open.facts_at(lon double precision, lat double precision)
RETURNS TABLE (dataset text, attribute text, value text, geom_geojson jsonb, meta_id text, sql_hint text,
               level text, label_pt text, label_en text, tag_pt text, tag_en text, caveat text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  p geometry := ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 3763);
  ren_note text := ' — REN watercourse lines not loaded';
  ren_lines text := 'unpublished';   -- unpublished | near | none — the same three cases as ren_note, for level/caveat
BEGIN
  IF to_regclass('open.caop_freguesias') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'caop2025'::text, 'freguesia'::text, (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(f.geom, 20), 4326))::jsonb,
             'caop2025'::text, 'ST_Intersects(caop_freguesias.geom, point)'::text,
             'in'::text, (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text,
             (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text, NULL::text, NULL::text, NULL::text
      FROM open.caop_freguesias f WHERE ST_Intersects(f.geom, p);
  END IF;
  IF to_regclass('open.cos2023') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'cos2023'::text, 'land_cover'::text, c.cos_label::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(c.geom, 5), 4326))::jsonb,
             'cos2023'::text, 'ST_Intersects(cos2023.geom, point)'::text,
             'in'::text, c.cos_label::text, c.cos_label::text, '2023'::text, '2023'::text, NULL::text
      FROM open.cos2023 c WHERE ST_Intersects(c.geom, p);
  END IF;
  IF to_regclass('open.icnf_perigosidade') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_perigosidade'::text, 'fire_hazard_class'::text, h.classe::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(h.geom, 5), 4326))::jsonb,
             'icnf_perigosidade'::text, 'ST_Intersects(icnf_perigosidade.geom, point)'::text,
             (CASE WHEN h.classe_ord >= 4 THEN 'hi' WHEN h.classe_ord = 3 THEN 'md' ELSE 'lo' END)::text,
             ('Perigosidade de incêndio: ' || h.classe)::text, ('Fire hazard: ' || open.hazard_en(h.classe))::text,
             h.classe::text, open.hazard_en(h.classe), NULL::text
      FROM open.icnf_perigosidade h WHERE ST_Intersects(h.geom, p);
  END IF;
  IF to_regclass('open.apa_perigo_inundacao') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_perigo'::text, 'flood_hazard_class'::text,
             (z.perigo || ' — ' || coalesce(z.local, '?') || ' (' || coalesce(z.designa, '?') || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 5), 4326))::jsonb,
             'apa_perigo'::text, 'ST_Intersects(apa_perigo_inundacao.geom, point)'::text,
             (CASE WHEN z.perigo ILIKE 'alto%' THEN 'hi' WHEN z.perigo ILIKE 'médio%' THEN 'md' ELSE 'lo' END)::text,
             ('Perigo de inundação: ' || z.perigo)::text, ('Flood hazard: ' || open.hazard_en(z.perigo))::text,
             z.perigo::text, open.hazard_en(z.perigo), NULL::text
      FROM open.apa_perigo_inundacao z WHERE ST_Intersects(z.geom, p);
  END IF;
  IF to_regclass('open.apa_zonas_inundaveis') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_zonas_inundaveis'::text, 'flood_extent'::text,
             ('inside the ' || CASE z.pretorno::text WHEN 'T0020' THEN '20-year' WHEN 'T0100' THEN '100-year' WHEN 'T1000' THEN '1000-year' ELSE z.pretorno::text END
              || ' return-period flood zone; max water level ' || coalesce(z.nivel_max::text, '?') || ' m — ' || coalesce(z.local, '?'))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 2), 4326))::jsonb,
             'apa_zonas_inundaveis'::text, 'ST_Intersects(apa_zonas_inundaveis.geom, point)'::text,
             'hi'::text,
             ('Zona inundável — cheia de ' || coalesce(ltrim(substr(z.pretorno::text, 2), '0'), '?') || ' anos'
              || coalesce(' (água até ' || open.fmt_num(z.nivel_max::numeric, 1, 'pt') || ' m)', ''))::text,
             ('Flood zone — ' || coalesce(ltrim(substr(z.pretorno::text, 2), '0'), '?') || '-year flood'
              || coalesce(' (water up to ' || open.fmt_num(z.nivel_max::numeric, 1, 'en') || ' m)', ''))::text,
             NULL::text, NULL::text, NULL::text
      FROM open.apa_zonas_inundaveis z WHERE ST_Intersects(z.geom, p) ORDER BY z.pretorno;
  END IF;
  IF to_regclass('open.apa_arpsi') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_arpsi'::text, 'designated_flood_risk_area'::text,
             (coalesce(z.name, '?') || ' — ' || coalesce(z.uomname, '?') || ' (' || coalesce(z.local, '?') || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 5), 4326))::jsonb,
             'apa_arpsi'::text, 'ST_Intersects(apa_arpsi.geom, point)'::text,
             'md'::text, ('Dentro de uma ARPSI: ' || coalesce(z.name, '?'))::text, ('Inside an ARPSI: ' || coalesce(z.name, '?'))::text,
             'ARPSI'::text, 'ARPSI'::text, NULL::text
      FROM open.apa_arpsi z WHERE ST_Intersects(z.geom, p);
  END IF;
  IF to_regclass('open.apa_marcas_cheia') IS NOT NULL THEN   -- proximity evidence, not intersection: nearest historical flood marks within 1 km
    RETURN QUERY
      SELECT 'apa_marcas_cheia'::text, 'flood_mark_nearby'::text,
             (coalesce(m.descricao, '?') || ' — level ' || coalesce(m.cota_inundacao::text, '?') || ' m'
              || coalesce(', ' || to_char(to_timestamp(m.data::double precision / 1000), 'YYYY-MM-DD'), '')
              || ' (' || coalesce(m.fonte, '?') || '), ' || round(ST_Distance(m.geom, p)) || ' m away')::text,
             ST_AsGeoJSON(ST_Transform(m.geom, 4326))::jsonb,
             'apa_marcas_cheia'::text, 'ST_DWithin(apa_marcas_cheia.geom, point, 1000) ORDER BY distance LIMIT 3'::text,
             'in'::text,
             ('Marca de cheia a ' || open.fmt_num(round(ST_Distance(m.geom, p))::numeric, 0, 'pt') || ' m: ' || coalesce(m.descricao, '?')
              || ' (' || open.fmt_num(m.cota_inundacao::numeric, 2, 'pt') || ' m)')::text,
             ('Flood mark ' || open.fmt_num(round(ST_Distance(m.geom, p))::numeric, 0, 'en') || ' m away: ' || coalesce(m.descricao, '?')
              || ' (' || open.fmt_num(m.cota_inundacao::numeric, 2, 'en') || ' m)')::text,
             NULL::text, NULL::text, NULL::text
      FROM open.apa_marcas_cheia m WHERE ST_DWithin(m.geom, p, 1000) ORDER BY ST_Distance(m.geom, p) LIMIT 3;
  END IF;
  IF to_regclass('open.ine_bgri2021') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'ine_bgri2021'::text, 'census_subsection'::text,
             ('BGRI ' || b.bgri2021 || ': ' || b.n_individuos::int || ' residents, ' || b.n_edificios::int || ' buildings, ' || b.n_alojamentos::int || ' dwellings')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(b.geom, 5), 4326))::jsonb,
             'ine_bgri2021'::text, 'ST_Intersects(ine_bgri2021.geom, point)'::text,
             'in'::text,
             (open.fmt_num(b.n_individuos::numeric, 0, 'pt') || ' residentes, ' || open.fmt_num(b.n_edificios::numeric, 0, 'pt') || ' edifícios, '
              || open.fmt_num(b.n_alojamentos::numeric, 0, 'pt') || ' alojamentos (subsecção ' || b.bgri2021 || ', Censos 2021)')::text,
             (open.fmt_num(b.n_individuos::numeric, 0, 'en') || ' residents, ' || open.fmt_num(b.n_edificios::numeric, 0, 'en') || ' buildings, '
              || open.fmt_num(b.n_alojamentos::numeric, 0, 'en') || ' dwellings (subsection ' || b.bgri2021 || ', 2021 census)')::text,
             NULL::text, NULL::text, NULL::text
      FROM open.ine_bgri2021 b WHERE ST_Intersects(b.geom, p);
  END IF;
  IF to_regclass('open.icnf_areas_ardidas') IS NOT NULL THEN   -- one row per fire that burned the point + one summary row
    RETURN QUERY
      SELECT 'icnf_areas_ardidas'::text, 'burned_area'::text,
             ('burned in ' || a.ano || coalesce(' (fire started ' || left(a.dh_inicio, 10) || ')', '')
              || ' — ' || coalesce(a.area_ha::text, '?') || ' ha burned in total'
              || coalesce('; cause: ' || lower(a.causa_tipo), ''))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(a.geom, 10), 4326))::jsonb,
             'icnf_areas_ardidas'::text, 'ST_Intersects(icnf_areas_ardidas.geom, point) ORDER BY ano DESC'::text,
             'md'::text,
             ('Ardeu em ' || a.ano || coalesce(' (incêndio de ' || open.fmt_num(a.area_ha::numeric, 1, 'pt') || ' ha)', ''))::text,
             ('Burned in ' || a.ano || coalesce(' (fire of ' || open.fmt_num(a.area_ha::numeric, 1, 'en') || ' ha)', ''))::text,
             'Ardeu'::text, 'Burned'::text, NULL::text
      FROM open.icnf_areas_ardidas a WHERE ST_Intersects(a.geom, p) ORDER BY a.ano DESC;
    RETURN QUERY
      SELECT 'icnf_areas_ardidas'::text, 'burn_history'::text,
             (count(*) || ' burned-area record(s) since 1975 (' || string_agg(DISTINCT a.ano::text, ', ' ORDER BY a.ano::text) || '); '
              || count(*) FILTER (WHERE a.ano >= extract(year FROM now())::int - 10)
              || ' in the last 10 years (since ' || (extract(year FROM now())::int - 10) || '); record 1975–2025')::text,
             NULL::jsonb, 'icnf_areas_ardidas'::text,
             'count(*), count(*) FILTER (WHERE ano >= year(now()) - 10) FROM icnf_areas_ardidas WHERE ST_Intersects(geom, point)'::text,
             'in'::text,
             (count(*) || CASE WHEN count(*) = 1 THEN ' registo' ELSE ' registos' END || ' de área ardida desde 1975'
              || CASE WHEN count(*) FILTER (WHERE a.ano >= extract(year FROM now())::int - 10) > 0
                      THEN ' — ' || count(*) FILTER (WHERE a.ano >= extract(year FROM now())::int - 10) || ' nos últimos 10 anos' ELSE '' END)::text,
             (count(*) || ' burned-area record' || CASE WHEN count(*) = 1 THEN '' ELSE 's' END || ' since 1975'
              || CASE WHEN count(*) FILTER (WHERE a.ano >= extract(year FROM now())::int - 10) > 0
                      THEN ' — ' || count(*) FILTER (WHERE a.ano >= extract(year FROM now())::int - 10) || ' in the last 10 years' ELSE '' END)::text,
             NULL::text, NULL::text, NULL::text
      FROM open.icnf_areas_ardidas a WHERE ST_Intersects(a.geom, p) HAVING count(*) > 0;
  END IF;
  IF to_regclass('open.icnf_areas_protegidas') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_areas_protegidas'::text, 'protected_area'::text,
             (z.nome || ' — ' || z.rede || ', ' || coalesce(z.categoria, '?') || coalesce(' (' || z.codigo || ')', '')
              || coalesce('; diploma: ' || z.diploma, ''))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 20), 4326))::jsonb,
             'icnf_areas_protegidas'::text, 'ST_Intersects(icnf_areas_protegidas.geom, point)'::text,
             'hi'::text, (z.nome || ' — ' || z.rede || ', ' || coalesce(z.categoria, '?') || coalesce(' (' || z.codigo || ')', ''))::text,
             (z.nome || ' — ' || z.rede || ', ' || coalesce(z.categoria, '?') || coalesce(' (' || z.codigo || ')', ''))::text,
             NULL::text, NULL::text, NULL::text
      FROM open.icnf_areas_protegidas z WHERE ST_Intersects(z.geom, p) ORDER BY z.rede DESC, z.categoria;
  END IF;
  IF to_regclass('open.dgt_crus') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'dgt_crus'::text, 'land_use_plan_class'::text,
             (coalesce(c.classe || ' — ' || coalesce(c.categoria, '?'), 'not re-coded to DR 15/2015 classes')
              || ' (PDM ' || coalesce(c.municipio, '?') || ': "' || coalesce(c.designacao_pdm, '?') || '", scale '
              || coalesce(c.escala, '?') || ', PDM published ' || coalesce(c.data_publicacao_pdm, '?') || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(c.geom, 5), 4326))::jsonb,
             'dgt_crus'::text, 'ST_Intersects(dgt_crus.geom, point)'::text,
             'in'::text, coalesce(c.classe || ' — ' || coalesce(c.categoria, '?'), c.designacao_pdm, '?')::text,
             coalesce(c.classe || ' — ' || coalesce(c.categoria, '?'), c.designacao_pdm, '?')::text,
             (CASE WHEN c.classe IS NULL THEN 'Classe original do PDM' ELSE 'Classe do PDM' END)::text,
             (CASE WHEN c.classe IS NULL THEN 'Original PDM class' ELSE 'PDM class' END)::text, NULL::text
      FROM open.dgt_crus c WHERE ST_Intersects(c.geom, p);
  END IF;
  IF to_regclass('open.ine_precos_habitacao') IS NOT NULL THEN   -- parish row (where INE publishes it) + municipality row
    RETURN QUERY
      SELECT 'ine_precos_habitacao'::text, ('median_price_eur_m2_' || i.nivel)::text,
             (coalesce(i.eur_m2 || ' €/m²', 'not published (' || coalesce(i.nota, 'no value') || ')')
              || ' — median of family-dwelling sales, 12 months to ' || i.periodo || ', ' || i.nivel || ' ' || i.nome)::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(i.geom, 20), 4326))::jsonb,
             'ine_precos_habitacao'::text, 'ST_Intersects(ine_precos_habitacao.geom, point)'::text,
             (CASE WHEN i.eur_m2 IS NULL THEN 'na' ELSE 'in' END)::text,
             (coalesce(open.fmt_num(i.eur_m2::numeric, 0, 'pt') || ' €/m² — mediana das vendas (12 meses até ' || i.periodo || ')',
                       'Preço não publicado pelo INE') || ', ' || CASE WHEN i.nivel = 'freguesia' THEN 'freguesia' ELSE 'município' END || ' ' || i.nome)::text,
             (coalesce(open.fmt_num(i.eur_m2::numeric, 0, 'en') || ' €/m² — median sale price (12 months to ' || i.periodo || ')',
                       'Price not published by INE') || ', ' || CASE WHEN i.nivel = 'freguesia' THEN 'parish' ELSE 'municipality' END || ' ' || i.nome)::text,
             NULL::text, NULL::text, NULL::text
      FROM open.ine_precos_habitacao i WHERE ST_Intersects(i.geom, p) ORDER BY i.nivel;
  END IF;
  IF to_regclass('open.ipma_rcm_snapshot') IS NOT NULL THEN   -- latest stored forecast for the municipality; stale by design
    RETURN QUERY
      SELECT 'ipma_rcm'::text, 'fire_risk_forecast_snapshot'::text,
             ('RCM ' || r.rcm || ' — ' || r.rcm_label || ' for ' || r.data_prev || ' (IPMA forecast run ' || r.data_run
              || '; stored snapshot retrieved ' || to_char(r.retrieved_at, 'YYYY-MM-DD') || ' — read the live API for today)')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(m.geom, 50), 4326))::jsonb,
             'ipma_rcm'::text, 'ipma_rcm_snapshot WHERE dico = municipality(point) ORDER BY data_prev DESC LIMIT 1'::text,
             'in'::text, ('Risco de incêndio previsto (IPMA): ' || r.rcm_label || ' — ' || r.data_prev)::text,
             ('Forecast fire risk (IPMA): ' || open.hazard_en(r.rcm_label) || ' — ' || r.data_prev)::text,
             'Instantâneo'::text, 'Snapshot'::text, NULL::text
      FROM open.caop_municipios m
      JOIN LATERAL (SELECT * FROM open.ipma_rcm_snapshot s WHERE s.dico = m.dico
                    ORDER BY (s.data_prev = current_date) DESC, s.data_prev DESC LIMIT 1) r ON true
      WHERE ST_Intersects(m.geom, p);
  END IF;
  IF to_regclass('open.cos_serie') IS NOT NULL THEN   -- other COS editions (2023 is the cos2023 row above): the trajectory
    RETURN QUERY
      SELECT ('cos' || c.ano)::text, 'land_cover'::text,
             (c.label_n4 || ' (' || c.ano || ', COS ' || c.serie || CASE WHEN c.serie = 'S1' THEN ' — older nomenclature, compare at level 1 only' ELSE '' END || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(c.geom, 5), 4326))::jsonb,
             ('cos' || c.ano)::text, 'ST_Intersects(cos_serie.geom, point) WHERE ano = ' || c.ano,
             'in'::text, c.label_n4::text, c.label_n4::text, c.ano::text, c.ano::text, NULL::text
      FROM open.cos_serie c WHERE ST_Intersects(c.geom, p) ORDER BY c.ano;
  END IF;
  -- relief: DGT LiDAR 2024 terrain model first, Copernicus only where it has no value (open.relief_at says which);
  -- the fallback is named in the label and flagged as caveat relief_fallback
  RETURN QUERY
    SELECT r.meta_id, 'slope_pct'::text, ('slope ≈ ' || r.val || ' % — ' || open.slope_class(r.val) || r.note)::text,
           NULL::jsonb, r.meta_id, ('ST_Value(' || r.tbl || '.rast, point)')::text,
           'in'::text,
           ('Declive ≈ ' || open.fmt_num(r.val, 0, 'pt') || ' % — ' || open.slope_class(r.val) || CASE WHEN r.meta_id = 'cop_dem30' THEN ' · modelo de superfície' ELSE '' END)::text,
           ('Slope ≈ ' || open.fmt_num(r.val, 0, 'en') || ' % — ' || open.slope_class_en(r.val) || CASE WHEN r.meta_id = 'cop_dem30' THEN ' · surface model' ELSE '' END)::text,
           NULL::text, NULL::text, (CASE WHEN r.meta_id = 'cop_dem30' THEN 'relief_fallback' END)::text
    FROM open.relief_at(p, 'slope') r;
  RETURN QUERY
    SELECT r.meta_id, 'elevation_m'::text, ('elevation ≈ ' || r.val || ' m' || r.note)::text,
           NULL::jsonb, r.meta_id, ('ST_Value(' || r.tbl || '.rast, point)')::text,
           'in'::text,
           ('Altitude ≈ ' || open.fmt_num(r.val, 0, 'pt') || ' m' || CASE WHEN r.meta_id = 'cop_dem30' THEN ' · modelo de superfície' ELSE '' END)::text,
           ('Elevation ≈ ' || open.fmt_num(r.val, 0, 'en') || ' m' || CASE WHEN r.meta_id = 'cop_dem30' THEN ' · surface model' ELSE '' END)::text,
           NULL::text, NULL::text, (CASE WHEN r.meta_id = 'cop_dem30' THEN 'relief_fallback' END)::text
    FROM open.relief_at(p, 'elev') r;
  RETURN QUERY
    SELECT r.meta_id, 'aspect'::text,
           (CASE WHEN r.val < 0 THEN 'flat — no aspect' ELSE 'aspect ≈ ' || r.val || '° — facing ' || open.aspect_class(r.val) END || r.note)::text,
           NULL::jsonb, r.meta_id, ('ST_Value(' || r.tbl || '.rast, point)')::text,
           'in'::text,
           (CASE WHEN r.val < 0 THEN 'Plano (sem orientação)' ELSE 'Orientação ≈ ' || open.fmt_num(r.val, 0, 'pt') || '° — virado a ' || open.aspect_class(r.val) END
            || CASE WHEN r.meta_id = 'cop_dem30' THEN ' · modelo de superfície' ELSE '' END)::text,
           (CASE WHEN r.val < 0 THEN 'Flat (no aspect)' ELSE 'Aspect ≈ ' || open.fmt_num(r.val, 0, 'en') || '° — facing ' || open.aspect_class_en(r.val) END
            || CASE WHEN r.meta_id = 'cop_dem30' THEN ' · surface model' ELSE '' END)::text,
           NULL::text, NULL::text, (CASE WHEN r.meta_id = 'cop_dem30' THEN 'relief_fallback' END)::text
    FROM open.relief_at(p, 'aspect') r;
  -- REN / RAN (DGT SRUP): inside; or outside — stated ONLY where the municipality's delimitation is loaded; a pilot
  -- municipality without data says "not available — not consulted", never "not in REN". 'Exclusões' = areas taken OUT
  -- of the REN by the municipal delimitation. Map geometry: the part within 300 m of the point (a whole municipality's
  -- REN is one huge multipolygon).
  IF to_regclass('open.dgt_ren') IS NOT NULL THEN
    -- REN watercourse lines (dgt_ren_linhas) are published only for some municipalities → the "outside" row says which case applies
    IF to_regclass('open.dgt_ren_linhas') IS NOT NULL THEN
      SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM open.dgt_ren_linhas l JOIN open.caop_municipios m ON m.dico = l.dico WHERE ST_Intersects(m.geom, p))
                  THEN 'unpublished'
                  WHEN EXISTS (SELECT 1 FROM open.dgt_ren_linhas l WHERE ST_DWithin(l.geom, p, 100))
                  THEN 'near'
                  ELSE 'none' END INTO ren_lines;
      ren_note := CASE ren_lines WHEN 'unpublished' THEN ' — REN watercourse lines are not published for this municipality (a stream bed may still be REN)'
                                 WHEN 'near' THEN ' — but a REN watercourse line runs within 100 m (see ecological_reserve_watercourse)'
                                 ELSE ' — no REN watercourse line within 100 m' END;
      -- a line near the point is "md" (the point is near the bed, not in it; the band width is not in the layer); on it, "hi"
      RETURN QUERY
        SELECT 'dgt_ren'::text, 'ecological_reserve_watercourse'::text,
               ('REN watercourse line (' || coalesce(l.tipologia, '?') || ', ' || coalesce(l.concelho, '?') || ') ' || round(ST_Distance(l.geom, p))
                || ' m from the point — the REN covers the bed and banks; the band width is not in this layer')::text,
               ST_AsGeoJSON(ST_Transform(ST_Intersection(l.geom, ST_Buffer(p, 300)), 4326))::jsonb,
               'dgt_ren_linhas'::text, 'ST_DWithin(dgt_ren_linhas.geom, point, 100) ORDER BY distance LIMIT 1'::text,
               (CASE WHEN round(ST_Distance(l.geom, p)) = 0 THEN 'hi' ELSE 'md' END)::text,
               (CASE WHEN round(ST_Distance(l.geom, p)) = 0 THEN 'Linha de água da REN no local'
                     ELSE 'Linha de água da REN a ' || open.fmt_num(round(ST_Distance(l.geom, p))::numeric, 0, 'pt') || ' m' END)::text,
               (CASE WHEN round(ST_Distance(l.geom, p)) = 0 THEN 'REN watercourse line at the point'
                     ELSE 'REN watercourse line ' || open.fmt_num(round(ST_Distance(l.geom, p))::numeric, 0, 'en') || ' m away' END)::text,
               (CASE WHEN round(ST_Distance(l.geom, p)) > 0 THEN 'Perto' END)::text, (CASE WHEN round(ST_Distance(l.geom, p)) > 0 THEN 'Near' END)::text,
               NULL::text
        FROM open.dgt_ren_linhas l WHERE ST_DWithin(l.geom, p, 100) ORDER BY ST_Distance(l.geom, p) LIMIT 1;
    END IF;
    RETURN QUERY
      SELECT 'dgt_ren'::text, 'ecological_reserve'::text,
             (CASE WHEN r.tipologia ILIKE 'exclus%' THEN 'EXCLUDED from the REN (exclusion area of the municipal delimitation — not a REN constraint)'
                   ELSE 'inside the REN (' || r.tipologia || ')' END
              || ' — ' || r.concelho || ': ' || coalesce(r.designacao, '?') || '; ' || coalesce(r.diploma, '?') || coalesce(', DR ' || r.dr, '')
              || coalesce(' <' || r.diploma_url || '>', '') || '; map ' || coalesce(r.escala, '?') || ' of ' || coalesce(r.data_geometria, '?'))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(ST_Intersection(r.geom, ST_Buffer(p, 300)), 2), 4326))::jsonb,
             'dgt_ren'::text, 'ST_Intersects(dgt_ren.geom, point); map geometry = part within 300 m'::text,
             (CASE WHEN r.tipologia ILIKE 'exclus%' THEN 'lo' ELSE 'hi' END)::text,
             (CASE WHEN r.tipologia ILIKE 'exclus%' THEN 'Área de exclusão da REN (não é REN)' ELSE 'Dentro da REN' END)::text,
             (CASE WHEN r.tipologia ILIKE 'exclus%' THEN 'REN exclusion area (not REN)' ELSE 'Inside the REN' END)::text,
             (CASE WHEN r.tipologia ILIKE 'exclus%' THEN 'Exclusão' END)::text, (CASE WHEN r.tipologia ILIKE 'exclus%' THEN 'Excluded' END)::text,
             NULL::text
      FROM open.dgt_ren r WHERE ST_Intersects(r.geom, p);
    RETURN QUERY
      SELECT 'dgt_ren'::text, 'ecological_reserve'::text,
             (CASE WHEN count(r.dico) > 0
                   THEN 'outside the REN areas of ' || m.concelho || ' (' || string_agg(DISTINCT r.diploma, '; ') || ')' || ren_note
                   ELSE 'REN not available for ' || m.concelho || ' in this database — not consulted' END)::text,
             NULL::jsonb, 'dgt_ren'::text, 'NOT ST_Intersects(dgt_ren.geom, point) — municipal delimitation checked'::text,
             (CASE WHEN count(r.dico) = 0 THEN 'na' WHEN ren_lines = 'near' THEN 'md' ELSE 'lo' END)::text,
             (CASE WHEN count(r.dico) = 0 THEN 'REN não disponível para ' || m.concelho || ' — não consultada'
                   WHEN ren_lines = 'near' THEN 'Fora dos polígonos da REN, mas com linha de água a < 100 m'
                   ELSE 'Fora dos polígonos da REN' END)::text,
             (CASE WHEN count(r.dico) = 0 THEN 'REN not available for ' || m.concelho || ' — not consulted'
                   WHEN ren_lines = 'near' THEN 'Outside the REN polygons, but a watercourse line within 100 m'
                   ELSE 'Outside the REN polygons' END)::text,
             (CASE WHEN count(r.dico) > 0 AND ren_lines = 'near' THEN 'Perto' END)::text,
             (CASE WHEN count(r.dico) > 0 AND ren_lines = 'near' THEN 'Near' END)::text,
             (CASE WHEN count(r.dico) > 0 AND ren_lines = 'unpublished' THEN 'ren_lines_unpublished' END)::text
      FROM open.caop_municipios m JOIN open.pilot_regions pr ON pr.dico = m.dico LEFT JOIN open.dgt_ren r ON r.dico = m.dico
      WHERE ST_Intersects(m.geom, p) AND NOT EXISTS (SELECT 1 FROM open.dgt_ren x WHERE ST_Intersects(x.geom, p))
      GROUP BY m.concelho;
  END IF;
  IF to_regclass('open.dgt_ran') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'dgt_ran'::text, 'agricultural_reserve'::text,
             ('inside the RAN — ' || coalesce(r.concelho, '?') || ' (' || coalesce(r.dinamica, '?') || '; map ' || coalesce(r.escala, '?')
              || ' of ' || coalesce(r.data_geometria, '?') || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(ST_Intersection(r.geom, ST_Buffer(p, 300)), 2), 4326))::jsonb,
             'dgt_ran'::text, 'ST_Intersects(dgt_ran.geom, point); map geometry = part within 300 m'::text,
             'hi'::text, 'Dentro da RAN'::text, 'Inside the RAN'::text, NULL::text, NULL::text, NULL::text
      FROM open.dgt_ran r WHERE ST_Intersects(r.geom, p);
    RETURN QUERY
      SELECT 'dgt_ran'::text, 'agricultural_reserve'::text,
             (CASE WHEN count(r.dico) > 0 THEN 'outside the RAN of ' || m.concelho || ' (municipal delimitation loaded)'
                   ELSE 'RAN not available for ' || m.concelho || ' in this database — not consulted' END)::text,
             NULL::jsonb, 'dgt_ran'::text, 'NOT ST_Intersects(dgt_ran.geom, point) — municipal delimitation checked'::text,
             (CASE WHEN count(r.dico) > 0 THEN 'lo' ELSE 'na' END)::text,
             (CASE WHEN count(r.dico) > 0 THEN 'Fora da RAN' ELSE 'RAN não disponível para ' || m.concelho || ' — não consultada' END)::text,
             (CASE WHEN count(r.dico) > 0 THEN 'Outside the RAN' ELSE 'RAN not available for ' || m.concelho || ' — not consulted' END)::text,
             NULL::text, NULL::text, NULL::text
      FROM open.caop_municipios m JOIN open.pilot_regions pr ON pr.dico = m.dico LEFT JOIN open.dgt_ran r ON r.dico = m.dico
      WHERE ST_Intersects(m.geom, p) AND NOT EXISTS (SELECT 1 FROM open.dgt_ran x WHERE ST_Intersects(x.geom, p))
      GROUP BY m.concelho;
  END IF;
  -- building footprints (LiDAR 2024): the one under the point, and how built-up the surroundings are — only inside the
  -- pilot regions (nothing was loaded elsewhere, so "no building" would be false there)
  IF to_regclass('open.dgt_construcoes') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'mconst_lidar2024'::text, 'building_footprint'::text,
             ('the point falls on a building footprint of ' || b.area_m2 || ' m² (LiDAR 2024)')::text,
             ST_AsGeoJSON(ST_Transform(b.geom, 4326))::jsonb, 'mconst_lidar2024'::text, 'ST_Intersects(dgt_construcoes.geom, point)'::text,
             'in'::text, ('O ponto está sobre um edifício (' || open.fmt_num(b.area_m2::numeric, 0, 'pt') || ' m²)')::text,
             ('The point is on a building (' || open.fmt_num(b.area_m2::numeric, 0, 'en') || ' m²)')::text, NULL::text, NULL::text, NULL::text
      FROM open.dgt_construcoes b WHERE ST_Intersects(b.geom, p);
    RETURN QUERY
      SELECT 'mconst_lidar2024'::text, 'buildings_nearby'::text,
             (CASE WHEN s.n200 = 0 THEN 'no building footprint within 200 m'
                   ELSE s.n50 || ' building footprint(s) within 50 m, ' || s.n200 || ' within 200 m; nearest ' || s.d || ' m away' END
              || ' (LiDAR 2024)' || CASE WHEN ST_DWithin(u.boundary, p, 200) THEN ' — the 200 m circle crosses the edge of the pilot regions; buildings beyond it are not loaded' ELSE '' END)::text,
             NULL::jsonb, 'mconst_lidar2024'::text, 'count(*) FROM dgt_construcoes WHERE ST_DWithin(geom, point, 50 | 200)'::text,
             'in'::text,
             (CASE WHEN s.n200 = 0 THEN 'Nenhum edifício a menos de 200 m'
                   ELSE s.n50 || CASE WHEN s.n50 = 1 THEN ' edifício' ELSE ' edifícios' END || ' a 50 m, ' || s.n200 || ' a 200 m; o mais próximo a '
                        || open.fmt_num(s.d, 0, 'pt') || ' m' END)::text,
             (CASE WHEN s.n200 = 0 THEN 'No building within 200 m'
                   ELSE s.n50 || CASE WHEN s.n50 = 1 THEN ' building' ELSE ' buildings' END || ' within 50 m, ' || s.n200 || ' within 200 m; nearest '
                        || open.fmt_num(s.d, 0, 'en') || ' m away' END)::text,
             NULL::text, NULL::text, (CASE WHEN ST_DWithin(u.boundary, p, 200) THEN 'pilot_edge' END)::text
      FROM (SELECT count(*) AS n200, count(*) FILTER (WHERE ST_DWithin(b.geom, p, 50)) AS n50, round(min(ST_Distance(b.geom, p)))::int AS d
            FROM open.dgt_construcoes b WHERE ST_DWithin(b.geom, p, 200)) s, open.pilot_union u
      WHERE ST_Intersects(u.geom, p);
  END IF;
  RETURN;
END $$;

GRANT EXECUTE ON FUNCTION open.facts_at(double precision, double precision) TO territorio_ro;

-- facts_in(polygon): the area version of facts_at — for a plot the user draws. Per layer, one row per distinct value
-- with the share of the plot it covers (share_pct, 0–100) and its area (area_ha); geom_geojson is the PART OF THE
-- PLOT that value covers (not the whole source feature). Census and flood marks are not area-weighted (whole BGRI
-- subsections / nearest marks ≤ 1 km) and say so. Plots are limited to 1 000 ha (guard against country-sized input).
-- Depends on: the same tables as facts_at (each guarded by to_regclass). Used by: facts_for() → the agent's pg tool
-- (inside the window), the rehearsal explorer. When changing: the extra columns (share_pct, area_ha) are part of the
-- polygon evidence contract; attribute names match facts_at so rules can treat point and plot alike. The status columns
-- (level, label_pt, label_en, tag_pt, tag_en, caveat) mean what facts_at says; a label never repeats the share (the
-- reader shows share_pct next to it).
CREATE OR REPLACE FUNCTION open.facts_in(g geometry)
RETURNS TABLE (dataset text, attribute text, value text, share_pct numeric, area_ha numeric, geom_geojson jsonb, meta_id text, sql_hint text,
               level text, label_pt text, label_en text, tag_pt text, tag_en text, caveat text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  a_total double precision := ST_Area(g);
  pct text := 'round(100 * ST_Area(ST_Intersection(layer.geom, plot)) / ST_Area(plot), 1)';
  rs text[];   -- relief source for this plot: {meta_id, table prefix, pixel m², pixel label, elevation note}
BEGIN
  IF a_total <= 0 THEN RAISE EXCEPTION 'facts_in: empty polygon'; END IF;
  IF a_total > 1e7 THEN RAISE EXCEPTION 'facts_in: polygon of % ha — limit is 1 000 ha', round((a_total / 1e4)::numeric); END IF;
  RETURN QUERY   -- how much of the plot the database covers at all (outside the pilot regions only CAOP answers)
    SELECT 'pilot_regions'::text, 'coverage'::text,
           (round((100 * coalesce(ST_Area(ST_Intersection(u.geom, g)), 0) / a_total)::numeric, 1) || '% of the area lies in the pilot regions'
            || coalesce(' (' || (SELECT string_agg(DISTINCT p.region, ', ') FROM open.pilot_regions p WHERE ST_Intersects(p.geom, g)) || ')', ''))::text,
           round((100 * coalesce(ST_Area(ST_Intersection(u.geom, g)), 0) / a_total)::numeric, 1), round((a_total / 1e4)::numeric, 2),
           NULL::jsonb, 'caop2025'::text, 'ST_Area(ST_Intersection(pilot_union.geom, plot)) / ST_Area(plot)'::text,
           'in'::text,
           (open.fmt_num((100 * coalesce(ST_Area(ST_Intersection(u.geom, g)), 0) / a_total)::numeric, 1, 'pt') || ' % da área nas regiões piloto')::text,
           (open.fmt_num((100 * coalesce(ST_Area(ST_Intersection(u.geom, g)), 0) / a_total)::numeric, 1, 'en') || ' % of the area in the pilot regions')::text,
           NULL::text, NULL::text, NULL::text
    FROM open.pilot_union u;
  IF to_regclass('open.caop_freguesias') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'caop2025'::text, 'freguesia'::text, (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text,
             round((100 * ST_Area(x.gi) / a_total)::numeric, 1), round((ST_Area(x.gi) / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(x.gi, 2), 4326))::jsonb,
             'caop2025'::text, 'ST_Intersection(caop_freguesias.geom, plot)'::text,
             'in'::text, (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text,
             (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text, NULL::text, NULL::text, NULL::text
      FROM open.caop_freguesias f CROSS JOIN LATERAL (SELECT ST_Intersection(f.geom, g) AS gi) x
      WHERE ST_Intersects(f.geom, g) ORDER BY ST_Area(x.gi) DESC;
  END IF;
  IF to_regclass('open.cos2023') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'cos2023'::text, 'land_cover'::text, s.v::text, round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'cos2023'::text, 'sum(ST_Area(ST_Intersection(cos2023.geom, plot))) GROUP BY cos_label'::text,
             'in'::text, s.v::text, s.v::text, '2023'::text, '2023'::text, NULL::text
      FROM (SELECT c.cos_label AS v, sum(ST_Area(ST_Intersection(c.geom, g))) AS a, ST_Union(ST_Intersection(c.geom, g)) AS gu
            FROM open.cos2023 c WHERE ST_Intersects(c.geom, g) GROUP BY c.cos_label) s
      WHERE s.a > 0 ORDER BY s.a DESC;
  END IF;
  IF to_regclass('open.icnf_perigosidade') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_perigosidade'::text, 'fire_hazard_class'::text, s.v::text, round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'icnf_perigosidade'::text, 'sum(ST_Area(ST_Intersection(icnf_perigosidade.geom, plot))) GROUP BY classe'::text,
             (CASE WHEN s.o >= 4 THEN 'hi' WHEN s.o = 3 THEN 'md' ELSE 'lo' END)::text,
             ('Perigosidade de incêndio: ' || s.v)::text, ('Fire hazard: ' || open.hazard_en(s.v))::text, s.v::text, open.hazard_en(s.v), NULL::text
      FROM (SELECT h.classe AS v, max(h.classe_ord) AS o, sum(ST_Area(ST_Intersection(h.geom, g))) AS a, ST_Union(ST_Intersection(h.geom, g)) AS gu
            FROM open.icnf_perigosidade h WHERE ST_Intersects(h.geom, g) GROUP BY h.classe) s
      WHERE s.a > 0 ORDER BY s.o DESC;
  END IF;
  IF to_regclass('open.apa_perigo_inundacao') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_perigo'::text, 'flood_hazard_class'::text, (s.v || ' — ' || coalesce(s.l, '?'))::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'apa_perigo'::text, 'sum(ST_Area(ST_Intersection(apa_perigo_inundacao.geom, plot))) GROUP BY perigo'::text,
             (CASE WHEN s.v ILIKE 'alto%' THEN 'hi' WHEN s.v ILIKE 'médio%' THEN 'md' ELSE 'lo' END)::text,
             ('Perigo de inundação: ' || s.v)::text, ('Flood hazard: ' || open.hazard_en(s.v))::text, s.v::text, open.hazard_en(s.v), NULL::text
      FROM (SELECT z.perigo AS v, string_agg(DISTINCT z.local, ', ') AS l, sum(ST_Area(ST_Intersection(z.geom, g))) AS a, ST_Union(ST_Intersection(z.geom, g)) AS gu
            FROM open.apa_perigo_inundacao z WHERE ST_Intersects(z.geom, g) GROUP BY z.perigo) s
      WHERE s.a > 0 ORDER BY s.a DESC;
  END IF;
  IF to_regclass('open.apa_zonas_inundaveis') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_zonas_inundaveis'::text, 'flood_extent'::text,
             ('inside the ' || CASE s.v WHEN 'T0020' THEN '20-year' WHEN 'T0100' THEN '100-year' WHEN 'T1000' THEN '1000-year' ELSE s.v END
              || ' return-period flood zone; max water level ' || coalesce(s.n::text, '?') || ' m — ' || coalesce(s.l, '?'))::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'apa_zonas_inundaveis'::text, 'sum(ST_Area(ST_Intersection(apa_zonas_inundaveis.geom, plot))) GROUP BY pretorno'::text,
             'hi'::text,
             ('Zona inundável — cheia de ' || coalesce(ltrim(substr(s.v, 2), '0'), '?') || ' anos'
              || coalesce(' (água até ' || open.fmt_num(s.n::numeric, 1, 'pt') || ' m)', ''))::text,
             ('Flood zone — ' || coalesce(ltrim(substr(s.v, 2), '0'), '?') || '-year flood'
              || coalesce(' (water up to ' || open.fmt_num(s.n::numeric, 1, 'en') || ' m)', ''))::text,
             NULL::text, NULL::text, NULL::text
      FROM (SELECT z.pretorno::text AS v, max(z.nivel_max) AS n, string_agg(DISTINCT z.local, ', ') AS l,
                   ST_Area(ST_Union(ST_Intersection(z.geom, g))) AS a, ST_Union(ST_Intersection(z.geom, g)) AS gu
            FROM open.apa_zonas_inundaveis z WHERE ST_Intersects(z.geom, g) GROUP BY z.pretorno) s
      WHERE s.a > 0 ORDER BY s.v;
  END IF;
  IF to_regclass('open.apa_arpsi') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_arpsi'::text, 'designated_flood_risk_area'::text, (coalesce(z.name, '?') || ' — ' || coalesce(z.uomname, '?'))::text,
             round((100 * ST_Area(x.gi) / a_total)::numeric, 1), round((ST_Area(x.gi) / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(x.gi, 2), 4326))::jsonb,
             'apa_arpsi'::text, 'ST_Intersection(apa_arpsi.geom, plot)'::text,
             'md'::text, ('Dentro de uma ARPSI: ' || coalesce(z.name, '?'))::text, ('Inside an ARPSI: ' || coalesce(z.name, '?'))::text,
             'ARPSI'::text, 'ARPSI'::text, NULL::text
      FROM open.apa_arpsi z CROSS JOIN LATERAL (SELECT ST_Intersection(z.geom, g) AS gi) x WHERE ST_Intersects(z.geom, g);
  END IF;
  IF to_regclass('open.apa_marcas_cheia') IS NOT NULL THEN   -- proximity, not area: nearest historical flood marks ≤ 1 km of the plot
    RETURN QUERY
      SELECT 'apa_marcas_cheia'::text, 'flood_mark_nearby'::text,
             (coalesce(m.descricao, '?') || ' — level ' || coalesce(m.cota_inundacao::text, '?') || ' m'
              || coalesce(', ' || to_char(to_timestamp(m.data::double precision / 1000), 'YYYY-MM-DD'), '')
              || ', ' || CASE WHEN ST_Intersects(m.geom, g) THEN 'inside the plot' ELSE round(ST_Distance(m.geom, g)) || ' m from the plot' END)::text,
             NULL::numeric, NULL::numeric, ST_AsGeoJSON(ST_Transform(m.geom, 4326))::jsonb,
             'apa_marcas_cheia'::text, 'ST_DWithin(apa_marcas_cheia.geom, plot, 1000) ORDER BY distance LIMIT 3'::text,
             'in'::text,
             ('Marca de cheia ' || CASE WHEN ST_Intersects(m.geom, g) THEN 'no terreno' ELSE 'a ' || open.fmt_num(round(ST_Distance(m.geom, g))::numeric, 0, 'pt') || ' m do terreno' END
              || ': ' || coalesce(m.descricao, '?') || ' (' || open.fmt_num(m.cota_inundacao::numeric, 2, 'pt') || ' m)')::text,
             ('Flood mark ' || CASE WHEN ST_Intersects(m.geom, g) THEN 'inside the plot' ELSE open.fmt_num(round(ST_Distance(m.geom, g))::numeric, 0, 'en') || ' m from the plot' END
              || ': ' || coalesce(m.descricao, '?') || ' (' || open.fmt_num(m.cota_inundacao::numeric, 2, 'en') || ' m)')::text,
             NULL::text, NULL::text, NULL::text
      FROM open.apa_marcas_cheia m WHERE ST_DWithin(m.geom, g, 1000) ORDER BY ST_Distance(m.geom, g) LIMIT 3;
  END IF;
  IF to_regclass('open.ine_bgri2021') IS NOT NULL THEN   -- whole-subsection totals: census counts are not spread by area
    RETURN QUERY
      SELECT 'ine_bgri2021'::text, 'census_subsections'::text,
             (count(*) || ' census subsection(s) touched — whole-subsection totals, not area-weighted: '
              || sum(b.n_individuos)::int || ' residents, ' || sum(b.n_edificios)::int || ' buildings, ' || sum(b.n_alojamentos)::int || ' dwellings')::text,
             NULL::numeric, NULL::numeric, NULL::jsonb, 'ine_bgri2021'::text, 'sum(n_*) FROM ine_bgri2021 WHERE ST_Intersects(geom, plot)'::text,
             'in'::text,
             (open.fmt_num(sum(b.n_individuos)::numeric, 0, 'pt') || ' residentes, ' || open.fmt_num(sum(b.n_edificios)::numeric, 0, 'pt') || ' edifícios, '
              || open.fmt_num(sum(b.n_alojamentos)::numeric, 0, 'pt') || ' alojamentos (' || count(*)
              || CASE WHEN count(*) = 1 THEN ' subsecção' ELSE ' subsecções' END || ' dos Censos 2021, inteiras)')::text,
             (open.fmt_num(sum(b.n_individuos)::numeric, 0, 'en') || ' residents, ' || open.fmt_num(sum(b.n_edificios)::numeric, 0, 'en') || ' buildings, '
              || open.fmt_num(sum(b.n_alojamentos)::numeric, 0, 'en') || ' dwellings (' || count(*)
              || CASE WHEN count(*) = 1 THEN ' whole 2021 census subsection)' ELSE ' whole 2021 census subsections)' END)::text,
             NULL::text, NULL::text, 'census_whole_subsections'::text
      FROM open.ine_bgri2021 b WHERE ST_Intersects(b.geom, g) HAVING count(*) > 0;
  END IF;
  IF to_regclass('open.icnf_areas_ardidas') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_areas_ardidas'::text, 'burned_area'::text,
             ('burned in ' || s.ano || coalesce(' (fire started ' || s.d || ')', '') || ' — fire of ' || coalesce(s.fa::text, '?') || ' ha in total')::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'icnf_areas_ardidas'::text, 'ST_Area(ST_Union(ST_Intersection(icnf_areas_ardidas.geom, plot))) GROUP BY ano'::text,
             'md'::text,
             ('Ardeu em ' || s.ano || coalesce(' (incêndio de ' || open.fmt_num(s.fa::numeric, 1, 'pt') || ' ha)', ''))::text,
             ('Burned in ' || s.ano || coalesce(' (fire of ' || open.fmt_num(s.fa::numeric, 1, 'en') || ' ha)', ''))::text,
             'Ardeu'::text, 'Burned'::text, NULL::text
      FROM (SELECT a.ano, min(left(a.dh_inicio, 10)) AS d, max(a.area_ha) AS fa,
                   ST_Area(ST_Union(ST_Intersection(a.geom, g))) AS a, ST_Union(ST_Intersection(a.geom, g)) AS gu
            FROM open.icnf_areas_ardidas a WHERE ST_Intersects(a.geom, g) GROUP BY a.ano) s
      WHERE s.a > 0 ORDER BY s.ano DESC;
    RETURN QUERY   -- overlapping fires counted once: union of every perimeter inside the plot
      SELECT 'icnf_areas_ardidas'::text, 'burn_history'::text,
             (round((100 * s.aa / a_total)::numeric, 1) || '% of the area burned at least once since 1975; '
              || round((100 * s.a10 / a_total)::numeric, 1) || '% in the last 10 years (since ' || (extract(year FROM now())::int - 10) || ')')::text,
             round((100 * s.aa / a_total)::numeric, 1), round((s.aa / 1e4)::numeric, 2), NULL::jsonb, 'icnf_areas_ardidas'::text,
             'ST_Area(ST_Union(ST_Intersection(icnf_areas_ardidas.geom, plot)))'::text,
             'in'::text,
             ('Ardeu pelo menos uma vez desde 1975; ' || open.fmt_num((100 * s.a10 / a_total)::numeric, 1, 'pt') || ' % do terreno nos últimos 10 anos')::text,
             ('Burned at least once since 1975; ' || open.fmt_num((100 * s.a10 / a_total)::numeric, 1, 'en') || ' % of the plot in the last 10 years')::text,
             NULL::text, NULL::text, NULL::text
      FROM (SELECT coalesce(ST_Area(ST_Union(ST_Intersection(a.geom, g))), 0) AS aa,
                   coalesce(ST_Area(ST_Union(ST_Intersection(a.geom, g)) FILTER (WHERE a.ano >= extract(year FROM now())::int - 10)), 0) AS a10
            FROM open.icnf_areas_ardidas a WHERE ST_Intersects(a.geom, g)) s
      WHERE s.aa > 0;
  END IF;
  IF to_regclass('open.icnf_areas_protegidas') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_areas_protegidas'::text, 'protected_area'::text,
             (z.nome || ' — ' || z.rede || ', ' || coalesce(z.categoria, '?') || coalesce(' (' || z.codigo || ')', '') || coalesce('; diploma: ' || z.diploma, ''))::text,
             round((100 * ST_Area(x.gi) / a_total)::numeric, 1), round((ST_Area(x.gi) / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(x.gi, 2), 4326))::jsonb,
             'icnf_areas_protegidas'::text, 'ST_Intersection(icnf_areas_protegidas.geom, plot)'::text,
             'hi'::text, (z.nome || ' — ' || z.rede || ', ' || coalesce(z.categoria, '?') || coalesce(' (' || z.codigo || ')', ''))::text,
             (z.nome || ' — ' || z.rede || ', ' || coalesce(z.categoria, '?') || coalesce(' (' || z.codigo || ')', ''))::text,
             NULL::text, NULL::text, NULL::text
      FROM open.icnf_areas_protegidas z CROSS JOIN LATERAL (SELECT ST_Intersection(z.geom, g) AS gi) x
      WHERE ST_Intersects(z.geom, g) AND ST_Area(x.gi) > 0 ORDER BY z.rede DESC, ST_Area(x.gi) DESC;
  END IF;
  IF to_regclass('open.dgt_crus') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'dgt_crus'::text, 'land_use_plan_class'::text,
             (coalesce(s.cl || ' — ' || coalesce(s.ca, '?'), 'not re-coded to DR 15/2015 classes') || ' (PDM ' || coalesce(s.mu, '?') || ': "'
              || coalesce(s.de, '?') || '", PDM published ' || coalesce(s.dt, '?') || ')')::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'dgt_crus'::text, 'sum(ST_Area(ST_Intersection(dgt_crus.geom, plot))) GROUP BY classe, categoria, designacao_pdm'::text,
             'in'::text, coalesce(s.cl || ' — ' || coalesce(s.ca, '?'), s.de, '?')::text, coalesce(s.cl || ' — ' || coalesce(s.ca, '?'), s.de, '?')::text,
             (CASE WHEN s.cl IS NULL THEN 'Classe original do PDM' ELSE 'Classe do PDM' END)::text,
             (CASE WHEN s.cl IS NULL THEN 'Original PDM class' ELSE 'PDM class' END)::text, NULL::text
      FROM (SELECT c.classe AS cl, c.categoria AS ca, c.designacao_pdm AS de, c.municipio AS mu, c.data_publicacao_pdm AS dt,
                   sum(ST_Area(ST_Intersection(c.geom, g))) AS a, ST_Union(ST_Intersection(c.geom, g)) AS gu
            FROM open.dgt_crus c WHERE ST_Intersects(c.geom, g) GROUP BY 1, 2, 3, 4, 5) s
      WHERE s.a > 0 ORDER BY s.a DESC;
  END IF;
  IF to_regclass('open.ine_precos_habitacao') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'ine_precos_habitacao'::text, ('median_price_eur_m2_' || i.nivel)::text,
             (coalesce(i.eur_m2 || ' €/m²', 'not published (' || coalesce(i.nota, 'no value') || ')')
              || ' — median of family-dwelling sales, 12 months to ' || i.periodo || ', ' || i.nivel || ' ' || i.nome)::text,
             round((100 * ST_Area(x.gi) / a_total)::numeric, 1), round((ST_Area(x.gi) / 1e4)::numeric, 2),
             NULL::jsonb, 'ine_precos_habitacao'::text, 'ST_Intersects(ine_precos_habitacao.geom, plot)'::text,
             (CASE WHEN i.eur_m2 IS NULL THEN 'na' ELSE 'in' END)::text,
             (coalesce(open.fmt_num(i.eur_m2::numeric, 0, 'pt') || ' €/m² — mediana das vendas (12 meses até ' || i.periodo || ')',
                       'Preço não publicado pelo INE') || ', ' || CASE WHEN i.nivel = 'freguesia' THEN 'freguesia' ELSE 'município' END || ' ' || i.nome)::text,
             (coalesce(open.fmt_num(i.eur_m2::numeric, 0, 'en') || ' €/m² — median sale price (12 months to ' || i.periodo || ')',
                       'Price not published by INE') || ', ' || CASE WHEN i.nivel = 'freguesia' THEN 'parish' ELSE 'municipality' END || ' ' || i.nome)::text,
             NULL::text, NULL::text, NULL::text
      FROM open.ine_precos_habitacao i CROSS JOIN LATERAL (SELECT ST_Intersection(i.geom, g) AS gi) x
      WHERE ST_Intersects(i.geom, g) ORDER BY i.nivel, ST_Area(x.gi) DESC;
  END IF;
  IF to_regclass('open.ipma_rcm_snapshot') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'ipma_rcm'::text, 'fire_risk_forecast_snapshot'::text,
             ('RCM ' || r.rcm || ' — ' || r.rcm_label || ' for ' || r.data_prev || ' in ' || m.concelho
              || ' (IPMA forecast run ' || r.data_run || '; stored snapshot — read the live API for today)')::text,
             round((100 * ST_Area(ST_Intersection(m.geom, g)) / a_total)::numeric, 1), NULL::numeric, NULL::jsonb,
             'ipma_rcm'::text, 'ipma_rcm_snapshot WHERE dico = municipality(plot) ORDER BY data_prev DESC LIMIT 1'::text,
             'in'::text, ('Risco de incêndio previsto (IPMA): ' || r.rcm_label || ' — ' || r.data_prev || ', ' || m.concelho)::text,
             ('Forecast fire risk (IPMA): ' || open.hazard_en(r.rcm_label) || ' — ' || r.data_prev || ', ' || m.concelho)::text,
             'Instantâneo'::text, 'Snapshot'::text, NULL::text
      FROM open.caop_municipios m
      JOIN LATERAL (SELECT * FROM open.ipma_rcm_snapshot s WHERE s.dico = m.dico
                    ORDER BY (s.data_prev = current_date) DESC, s.data_prev DESC LIMIT 1) r ON true
      WHERE ST_Intersects(m.geom, g);
  END IF;
  IF to_regclass('open.cos_serie') IS NOT NULL THEN
    RETURN QUERY
      SELECT ('cos' || s.ano)::text, 'land_cover'::text,
             (s.v || ' (' || s.ano || ', COS ' || s.se || CASE WHEN s.se = 'S1' THEN ' — compare at level 1 only' ELSE '' END || ')')::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             ('cos' || s.ano)::text, 'sum(ST_Area(ST_Intersection(cos_serie.geom, plot))) GROUP BY ano, label_n4'::text,
             'in'::text, s.v::text, s.v::text, s.ano::text, s.ano::text, NULL::text
      FROM (SELECT c.ano, c.serie AS se, c.label_n4 AS v, sum(ST_Area(ST_Intersection(c.geom, g))) AS a, ST_Union(ST_Intersection(c.geom, g)) AS gu
            FROM open.cos_serie c WHERE ST_Intersects(c.geom, g) GROUP BY 1, 2, 3) s
      WHERE s.a > 0 ORDER BY s.ano, s.a DESC;
  END IF;
  -- relief: ONE source per plot so slope, elevation and aspect agree — the DGT LiDAR 2024 terrain model (dem_mdt_*,
  -- 10 m pixels = 100 m²) when it has pixels in the plot, else Copernicus GLO-30 (dem_*, 25 m = 625 m², surface model;
  -- a 1 ha plot is ~16 of its pixels, so its shares are coarse — said in the value)
  IF to_regclass('open.dem_mdt_slope') IS NOT NULL AND EXISTS (
       SELECT 1 FROM open.dem_mdt_slope d WHERE ST_Intersects(d.rast, g) AND ST_Count(ST_Clip(d.rast, 1, g, true), 1, true) > 0) THEN
    rs := ARRAY['mdt_lidar2024', 'dem_mdt_', '100', '10 m, DGT LiDAR 2024 MDT terrain model', 'DGT LiDAR 2024 MDT — terrain model, 10 m'];
  ELSIF to_regclass('open.dem_slope') IS NOT NULL THEN
    rs := ARRAY['cop_dem30', 'dem_', '625', '25 m, surface model', 'surface model'];
  END IF;
  -- status columns: label suffix PT / EN ('' for the MDT) and caveat (NULL for the MDT — %L writes an unquoted NULL)
  IF rs IS NOT NULL AND to_regclass('open.' || rs[2] || 'slope') IS NOT NULL THEN
    RETURN QUERY EXECUTE format($f$
      SELECT %1$L::text, 'slope_class'::text,
             (open.slope_class(min(q.val)) || ' — ' || round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1) || ' %% of the plot ('
              || sum(sum(q.cnt)) OVER () || ' pixels of ' || %4$L || ')')::text,
             round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1), round((sum(q.cnt) * %3$s / 1e4)::numeric, 2), NULL::jsonb,
             %1$L::text, 'ST_ValueCount(ST_Clip(%2$sslope.rast, plot)) grouped by slope class'::text,
             'in'::text, (open.slope_class(min(q.val)) || %5$L)::text, (open.slope_class_en(min(q.val)) || %6$L)::text,
             NULL::text, NULL::text, %7$L::text
      FROM (SELECT (vc).value::numeric AS val, (vc).count AS cnt
            FROM (SELECT ST_ValueCount(ST_Clip(d.rast, 1, $1, true), 1, true) AS vc FROM open.%2$sslope d WHERE ST_Intersects(d.rast, $1)) x) q
      GROUP BY open.slope_class(q.val) ORDER BY min(q.val)$f$, rs[1], rs[2], rs[3], rs[4],
      CASE WHEN rs[1] = 'cop_dem30' THEN ' · modelo de superfície' ELSE '' END, CASE WHEN rs[1] = 'cop_dem30' THEN ' · surface model' ELSE '' END,
      CASE WHEN rs[1] = 'cop_dem30' THEN 'relief_fallback' END) USING g;
  END IF;
  IF rs IS NOT NULL AND to_regclass('open.' || rs[2] || 'elev') IS NOT NULL THEN
    RETURN QUERY EXECUTE format($f$
      SELECT %1$L::text, 'elevation_m'::text,
             ('elevation ' || round(min(st.mn)) || '–' || round(max(st.mx)) || ' m, mean ≈ ' || round(sum(st.sm) / nullif(sum(st.n), 0)) || ' m (' || %3$L || ')')::text,
             NULL::numeric, NULL::numeric, NULL::jsonb, %1$L::text, 'ST_SummaryStats(ST_Clip(%2$selev.rast, plot))'::text,
             'in'::text,
             ('Altitude ' || open.fmt_num(round(min(st.mn))::numeric, 0, 'pt') || '–' || open.fmt_num(round(max(st.mx))::numeric, 0, 'pt') || ' m (média ≈ '
              || open.fmt_num(round(sum(st.sm) / nullif(sum(st.n), 0))::numeric, 0, 'pt') || ' m)' || %4$L)::text,
             ('Elevation ' || open.fmt_num(round(min(st.mn))::numeric, 0, 'en') || '–' || open.fmt_num(round(max(st.mx))::numeric, 0, 'en') || ' m (mean ≈ '
              || open.fmt_num(round(sum(st.sm) / nullif(sum(st.n), 0))::numeric, 0, 'en') || ' m)' || %5$L)::text,
             NULL::text, NULL::text, %6$L::text
      FROM (SELECT (ss).min AS mn, (ss).max AS mx, (ss).sum AS sm, (ss).count AS n
            FROM (SELECT ST_SummaryStats(ST_Clip(d.rast, 1, $1, true), 1, true) AS ss FROM open.%2$selev d WHERE ST_Intersects(d.rast, $1)) x
            WHERE (ss).count > 0) st
      HAVING sum(st.n) > 0$f$, rs[1], rs[2], rs[5],
      CASE WHEN rs[1] = 'cop_dem30' THEN ' · modelo de superfície' ELSE '' END, CASE WHEN rs[1] = 'cop_dem30' THEN ' · surface model' ELSE '' END,
      CASE WHEN rs[1] = 'cop_dem30' THEN 'relief_fallback' END) USING g;
  END IF;
  IF rs IS NOT NULL AND to_regclass('open.' || rs[2] || 'aspect') IS NOT NULL THEN
    RETURN QUERY EXECUTE format($f$   -- same pixel caveat as slope; -9999 pixels (flat) form their own class
      SELECT %1$L::text, 'aspect_class'::text,
             ('facing ' || open.aspect_class(min(q.val)) || ' — ' || round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1) || ' %% of the plot ('
              || sum(sum(q.cnt)) OVER () || ' pixels of ' || %4$L || ')')::text,
             round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1), round((sum(q.cnt) * %3$s / 1e4)::numeric, 2), NULL::jsonb,
             %1$L::text, 'ST_ValueCount(ST_Clip(%2$saspect.rast, plot)) grouped by aspect class'::text,
             'in'::text,
             (CASE WHEN min(q.val) < 0 THEN 'Plano (sem orientação)' ELSE 'Virado a ' || open.aspect_class(min(q.val)) END || %5$L)::text,
             (CASE WHEN min(q.val) < 0 THEN 'Flat (no aspect)' ELSE 'Facing ' || open.aspect_class_en(min(q.val)) END || %6$L)::text,
             NULL::text, NULL::text, %7$L::text
      FROM (SELECT (vc).value::numeric AS val, (vc).count AS cnt
            FROM (SELECT ST_ValueCount(ST_Clip(d.rast, 1, $1, true), 1, true) AS vc FROM open.%2$saspect d WHERE ST_Intersects(d.rast, $1)) x) q
      GROUP BY open.aspect_class(q.val) ORDER BY sum(q.cnt) DESC$f$, rs[1], rs[2], rs[3], rs[4],
      CASE WHEN rs[1] = 'cop_dem30' THEN ' · modelo de superfície' ELSE '' END, CASE WHEN rs[1] = 'cop_dem30' THEN ' · surface model' ELSE '' END,
      CASE WHEN rs[1] = 'cop_dem30' THEN 'relief_fallback' END) USING g;
  END IF;
  -- REN / RAN: share of the plot inside each; municipalities of the plot without data are named ("not consulted").
  -- The share outside = 100 − the inside shares, and holds only where the delimitation is loaded.
  IF to_regclass('open.dgt_ren') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'dgt_ren'::text, 'ecological_reserve'::text,
             (CASE WHEN s.t ILIKE 'exclus%' THEN 'EXCLUDED from the REN (exclusion area — not a REN constraint)' ELSE 'inside the REN (' || s.t || ')' END
              || ' — ' || s.c || ': ' || coalesce(s.d, '?') || coalesce(' <' || s.u || '>', ''))::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'dgt_ren'::text, 'ST_Area(ST_Union(ST_Intersection(dgt_ren.geom, plot))) GROUP BY tipologia, diploma'::text,
             (CASE WHEN s.t ILIKE 'exclus%' THEN 'lo' ELSE 'hi' END)::text,
             (CASE WHEN s.t ILIKE 'exclus%' THEN 'Área de exclusão da REN (não é REN)' ELSE 'Dentro da REN' END)::text,
             (CASE WHEN s.t ILIKE 'exclus%' THEN 'REN exclusion area (not REN)' ELSE 'Inside the REN' END)::text,
             (CASE WHEN s.t ILIKE 'exclus%' THEN 'Exclusão' END)::text, (CASE WHEN s.t ILIKE 'exclus%' THEN 'Excluded' END)::text, NULL::text
      FROM (SELECT r.tipologia AS t, r.concelho AS c, r.diploma AS d, min(r.diploma_url) AS u,
                   ST_Area(ST_Union(ST_Intersection(r.geom, g))) AS a, ST_Union(ST_Intersection(r.geom, g)) AS gu
            FROM open.dgt_ren r WHERE ST_Intersects(r.geom, g) GROUP BY 1, 2, 3) s
      WHERE s.a > 0 ORDER BY s.a DESC;
    IF to_regclass('open.dgt_ren_linhas') IS NOT NULL THEN   -- lines have no area: length inside the plot, share NULL
      RETURN QUERY
        SELECT 'dgt_ren'::text, 'ecological_reserve_watercourse'::text,
               ('REN watercourse line(s) of ' || string_agg(DISTINCT l.concelho, ', ') || ': ' || round(sum(ST_Length(ST_Intersection(l.geom, g))))
                || ' m inside the plot — the REN covers the bed and banks (band width not in this layer)')::text,
               NULL::numeric, NULL::numeric, ST_AsGeoJSON(ST_Transform(ST_Collect(ST_Intersection(l.geom, g)), 4326))::jsonb,
               'dgt_ren_linhas'::text, 'ST_Length(ST_Intersection(dgt_ren_linhas.geom, plot))'::text,
               'hi'::text,   -- the line crosses the plot: its bed is REN inside the plot
               ('Linha de água da REN no terreno: ' || open.fmt_num(round(sum(ST_Length(ST_Intersection(l.geom, g))))::numeric, 0, 'pt') || ' m')::text,
               ('REN watercourse line in the plot: ' || open.fmt_num(round(sum(ST_Length(ST_Intersection(l.geom, g))))::numeric, 0, 'en') || ' m')::text,
               NULL::text, NULL::text, NULL::text
        FROM open.dgt_ren_linhas l WHERE ST_Intersects(l.geom, g) HAVING count(*) > 0;
    END IF;
    RETURN QUERY
      SELECT 'dgt_ren'::text, 'ecological_reserve'::text, ('REN not available for ' || m.concelho || ' in this database — not consulted')::text,
             round((100 * ST_Area(ST_Intersection(m.geom, g)) / a_total)::numeric, 1), NULL::numeric, NULL::jsonb, 'dgt_ren'::text,
             'caop_municipios ∩ plot, municipality without dgt_ren rows'::text,
             'na'::text, ('REN não disponível para ' || m.concelho || ' — não consultada')::text,
             ('REN not available for ' || m.concelho || ' — not consulted')::text, NULL::text, NULL::text, NULL::text
      FROM open.caop_municipios m JOIN open.pilot_regions pr ON pr.dico = m.dico
      WHERE ST_Intersects(m.geom, g) AND NOT EXISTS (SELECT 1 FROM open.dgt_ren r WHERE r.dico = m.dico);
  END IF;
  IF to_regclass('open.dgt_ran') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'dgt_ran'::text, 'agricultural_reserve'::text, ('inside the RAN — ' || coalesce(s.c, '?') || ' (map of ' || coalesce(s.dt, '?') || ')')::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'dgt_ran'::text, 'ST_Area(ST_Union(ST_Intersection(dgt_ran.geom, plot))) GROUP BY concelho'::text,
             'hi'::text, 'Dentro da RAN'::text, 'Inside the RAN'::text, NULL::text, NULL::text, NULL::text
      FROM (SELECT r.concelho AS c, max(r.data_geometria) AS dt, ST_Area(ST_Union(ST_Intersection(r.geom, g))) AS a,
                   ST_Union(ST_Intersection(r.geom, g)) AS gu
            FROM open.dgt_ran r WHERE ST_Intersects(r.geom, g) GROUP BY 1) s
      WHERE s.a > 0 ORDER BY s.a DESC;
    RETURN QUERY
      SELECT 'dgt_ran'::text, 'agricultural_reserve'::text, ('RAN not available for ' || m.concelho || ' in this database — not consulted')::text,
             round((100 * ST_Area(ST_Intersection(m.geom, g)) / a_total)::numeric, 1), NULL::numeric, NULL::jsonb, 'dgt_ran'::text,
             'caop_municipios ∩ plot, municipality without dgt_ran rows'::text,
             'na'::text, ('RAN não disponível para ' || m.concelho || ' — não consultada')::text,
             ('RAN not available for ' || m.concelho || ' — not consulted')::text, NULL::text, NULL::text, NULL::text
      FROM open.caop_municipios m JOIN open.pilot_regions pr ON pr.dico = m.dico
      WHERE ST_Intersects(m.geom, g) AND NOT EXISTS (SELECT 1 FROM open.dgt_ran r WHERE r.dico = m.dico);
  END IF;
  -- buildings (LiDAR 2024): footprints inside the plot, or the nearest one when there is none (pilot regions only)
  IF to_regclass('open.dgt_construcoes') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'mconst_lidar2024'::text, 'buildings_in_plot'::text,
             (s.n || ' building footprint(s) inside the plot, ' || round(s.a) || ' m² built (' || round((100 * s.a / a_total)::numeric, 1)
              || ' % of the plot; LiDAR 2024)')::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(s.gc, 4326))::jsonb, 'mconst_lidar2024'::text, 'ST_Intersection(dgt_construcoes.geom, plot)'::text,
             'in'::text,
             (s.n || CASE WHEN s.n = 1 THEN ' edifício' ELSE ' edifícios' END || ' no terreno — ' || open.fmt_num(round(s.a)::numeric, 0, 'pt') || ' m² construídos')::text,
             (s.n || CASE WHEN s.n = 1 THEN ' building' ELSE ' buildings' END || ' on the plot — ' || open.fmt_num(round(s.a)::numeric, 0, 'en') || ' m² built')::text,
             NULL::text, NULL::text, NULL::text
      FROM (SELECT count(*) AS n, sum(ST_Area(ST_Intersection(b.geom, g))) AS a, ST_Collect(ST_Intersection(b.geom, g)) AS gc
            FROM open.dgt_construcoes b WHERE ST_Intersects(b.geom, g)) s
      WHERE s.n > 0;
    RETURN QUERY
      SELECT 'mconst_lidar2024'::text, 'buildings_in_plot'::text,
             ('no building footprint inside the plot (LiDAR 2024); ' || coalesce('nearest one ' || n.d || ' m away', 'none within 1 km'))::text,
             0::numeric, 0::numeric, NULL::jsonb, 'mconst_lidar2024'::text, 'ST_Distance to the nearest dgt_construcoes footprint (KNN)'::text,
             'in'::text,
             ('Nenhum edifício no terreno; ' || coalesce('o mais próximo a ' || open.fmt_num(n.d, 0, 'pt') || ' m', 'nenhum a menos de 1 km'))::text,
             ('No building on the plot; ' || coalesce('nearest ' || open.fmt_num(n.d, 0, 'en') || ' m away', 'none within 1 km'))::text,
             NULL::text, NULL::text, NULL::text
      FROM open.pilot_union u
      LEFT JOIN LATERAL (SELECT round(ST_Distance(b.geom, g))::int AS d FROM open.dgt_construcoes b
                         WHERE ST_DWithin(b.geom, g, 1000) ORDER BY b.geom <-> g LIMIT 1) n ON true
      WHERE ST_Intersects(u.geom, g) AND NOT EXISTS (SELECT 1 FROM open.dgt_construcoes b WHERE ST_Intersects(b.geom, g));
  END IF;
  RETURN;
END $$;

-- facts_for(geojson): ONE entry point for a point or a plot. Accepts a GeoJSON geometry or Feature in WGS84
-- (EPSG:4326). Point → facts_at() rows (share_pct 100, area_ha NULL); Polygon/MultiPolygon → facts_in().
-- Depends on: facts_at, facts_in. Used by: the agent's pg tool (inside the window), the rehearsal explorer.
-- When changing: invalid polygons are repaired with ST_MakeValid (self-intersections from a hand-drawn ring) and the
-- repair is reported as a row, so the answer can say the drawn shape was corrected. The status columns (level …
-- caveat) pass through from facts_at / facts_in unchanged.
CREATE OR REPLACE FUNCTION open.facts_for(geojson text)
RETURNS TABLE (dataset text, attribute text, value text, share_pct numeric, area_ha numeric, geom_geojson jsonb, meta_id text, sql_hint text,
               level text, label_pt text, label_en text, tag_pt text, tag_en text, caveat text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  j jsonb := geojson::jsonb;
  g geometry;
BEGIN
  IF j->>'type' = 'Feature' THEN j := j->'geometry'; END IF;
  g := ST_SetSRID(ST_GeomFromGeoJSON(j::text), 4326);
  IF GeometryType(g) = 'POINT' THEN
    RETURN QUERY SELECT f.dataset, f.attribute, f.value, 100::numeric, NULL::numeric, f.geom_geojson, f.meta_id, f.sql_hint,
                        f.level, f.label_pt, f.label_en, f.tag_pt, f.tag_en, f.caveat
                 FROM open.facts_at(ST_X(g), ST_Y(g)) f;
  ELSIF GeometryType(g) IN ('POLYGON', 'MULTIPOLYGON') THEN
    g := ST_Transform(g, 3763);
    IF NOT ST_IsValid(g) THEN
      g := ST_Multi(ST_CollectionExtract(ST_MakeValid(g), 3));
      RETURN QUERY SELECT 'input'::text, 'geometry_repaired'::text,
        'the drawn polygon was not valid (e.g. crossing edges) and was repaired before the analysis'::text,
        NULL::numeric, round((ST_Area(g) / 1e4)::numeric, 2), NULL::jsonb, NULL::text, 'ST_MakeValid(plot)'::text,
        'in'::text, 'O terreno desenhado tinha arestas cruzadas e foi corrigido antes da análise'::text,
        'The drawn plot had crossing edges and was repaired before the analysis'::text, NULL::text, NULL::text, NULL::text;
    END IF;
    RETURN QUERY SELECT * FROM open.facts_in(g);
  ELSE
    RAISE EXCEPTION 'facts_for: % is not supported — send a Point or a Polygon', GeometryType(g);
  END IF;
END $$;

-- constraints_grid(geojson, radius_m, cell_m): what surrounds a point or a plot, cell by cell — the raw material for
-- "not here, but there". Square cells (fixed grid, origin 0,0 in EPSG:3763) within radius_m of the input; per cell:
-- worst fire-hazard class, flood extent / hazard / ARPSI, protected areas, dominant PDM (CRUS) class, fire years in the
-- cell, dominant land cover (newest COS edition loaded), mean slope, aspect at the cell centre (both from the DGT LiDAR
-- 2024 terrain model, 10 m, or — only where it has no pixel — Copernicus GLO-30, 25 m; relief_source says which), REN / RAN, building
-- footprints (count and built share), and whether the cell lies in the pilot regions (outside: unknown, never "free").
-- in_ren / in_ran are NULL where that municipality's delimitation is not loaded (unknown ≠ free); in_ren is true only for
-- REN proper (an 'Exclusões' area is reported in ren_types but is not a REN constraint). It returns FACTS only; which
-- cells are "free" is decided by the agent's rules (written inside the window). Optional layers are joined only when
-- loaded — the query is built dynamically so a missing table never breaks the call. When the subdivided helper tables
-- `open.grid_*` exist (stage `grelha` in load.sh: same attributes, geometries cut with ST_Subdivide) they are used
-- instead of the source layers: identical answers (checked cell by cell on 349 cells, 2026-09-27), ~80× faster.
-- Depends on: the layer tables above; open.slope_class, open.aspect_class. Used by: the agent (inside the window), the
-- rehearsal explorer (reads columns by name). When changing: keep ≤ 2 500 cells per call (raises otherwise) — a larger
-- radius needs a larger cell; the return type is part of the contract (DROP + CREATE when it changes).
DROP FUNCTION IF EXISTS open.constraints_grid(text, integer, integer);
CREATE FUNCTION open.constraints_grid(geojson text, radius_m integer DEFAULT 500, cell_m integer DEFAULT 50)
RETURNS TABLE (cell_id bigint, lon double precision, lat double precision, dist_m integer, in_pilot boolean,
               fire_max_ord integer, fire_max_class text, in_flood_extent boolean, flood_hazard text, in_arpsi boolean,
               protected text, pdm_class text, pdm_category text, pdm_designation text, pdm_schema text,
               burned_years integer[], land_cover text, land_cover_year integer, slope_pct integer, slope_class text,
               aspect_deg integer, aspect_class text, relief_source text, in_ren boolean, ren_types text, in_ran boolean,
               buildings integer, built_pct numeric, geom_geojson jsonb)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  j jsonb := geojson::jsonb;
  g geometry;
  search geometry;
  n integer;
  lc_sql text;
  sl_sql text;
  as_sql text;
  ren_sql text;
  ran_sql text;
  bd_sql text;
  ren_dicos text[] := '{}';
  ran_dicos text[] := '{}';
  -- source layer or its subdivided helper (same columns)
  t_per text := coalesce(to_regclass('open.grid_perigosidade')::text, 'open.icnf_perigosidade');
  t_zi  text := coalesce(to_regclass('open.grid_zonas_inundaveis')::text, 'open.apa_zonas_inundaveis');
  t_pi  text := coalesce(to_regclass('open.grid_perigo_inundacao')::text, 'open.apa_perigo_inundacao');
  t_ar  text := coalesce(to_regclass('open.grid_arpsi')::text, 'open.apa_arpsi');
  t_pr  text := coalesce(to_regclass('open.grid_protegidas')::text, 'open.icnf_areas_protegidas');
  t_cr  text := coalesce(to_regclass('open.grid_crus')::text, 'open.dgt_crus');
  t_ard text := coalesce(to_regclass('open.grid_ardidas')::text, 'open.icnf_areas_ardidas');
  t_ren text := coalesce(to_regclass('open.grid_ren')::text, to_regclass('open.dgt_ren')::text);
  t_ran text := coalesce(to_regclass('open.grid_ran')::text, to_regclass('open.dgt_ran')::text);
  t_rl  text := coalesce(to_regclass('open.grid_ren_linhas')::text, to_regclass('open.dgt_ren_linhas')::text);
BEGIN
  IF j->>'type' = 'Feature' THEN j := j->'geometry'; END IF;
  g := ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(j::text), 4326), 3763);
  IF NOT ST_IsValid(g) THEN g := ST_MakeValid(g); END IF;
  IF radius_m < 0 OR radius_m > 3000 OR cell_m < 10 THEN RAISE EXCEPTION 'constraints_grid: radius 0–3000 m and cell ≥ 10 m'; END IF;
  search := ST_Buffer(g, radius_m);
  n := ceil(ST_Area(search) / (cell_m::double precision * cell_m));
  IF n > 2500 THEN RAISE EXCEPTION 'constraints_grid: ~% cells — use a larger cell or a smaller radius (max 2 500)', n; END IF;
  -- newest land cover available: the subdivided helper (newest edition) when built, else COS 2025, else COS 2023
  IF to_regclass('open.grid_cos') IS NOT NULL THEN
    lc_sql := 'SELECT x.label_n4 AS label, max(x.ano) AS ano FROM open.grid_cos x WHERE ST_Intersects(x.geom, c.geom)
               GROUP BY x.label_n4 ORDER BY sum(ST_Area(ST_Intersection(x.geom, c.geom))) DESC LIMIT 1';
  ELSIF to_regclass('open.cos_serie') IS NOT NULL AND EXISTS (SELECT 1 FROM open.cos_serie WHERE ano = 2025 LIMIT 1) THEN
    lc_sql := 'SELECT x.label_n4 AS label, 2025 AS ano FROM open.cos_serie x WHERE x.ano = 2025 AND ST_Intersects(x.geom, c.geom)
               ORDER BY ST_Area(ST_Intersection(x.geom, c.geom)) DESC LIMIT 1';
  ELSE
    lc_sql := 'SELECT x.cos_label AS label, 2023 AS ano FROM open.cos2023 x WHERE ST_Intersects(x.geom, c.geom)
               ORDER BY ST_Area(ST_Intersection(x.geom, c.geom)) DESC LIMIT 1';
  END IF;
  -- slope: mean of the cell's pixels in the DGT LiDAR 2024 terrain model (10 m, 25 pixels per 50 m cell); the Copernicus
  -- subquery carries `m.pct IS NULL`, an outer-only condition that the planner turns into a one-time filter — its
  -- raster is read only for cells without MDT pixels (sea, Spain, gaps). NOT ST_Touches: the 1 km MDT tiles line up with
  -- the 50 m cells, so a cell on a tile edge "intersects" the neighbour tile too; its clip is empty and PostGIS raised a
  -- NOTICE per such cell (36 per Santo Varão grid, 2026-09-27) — same answer, noisy logs
  sl_sql := format('SELECT coalesce(m.pct, k.pct) AS pct,
                           CASE WHEN m.pct IS NOT NULL THEN ''mdt_lidar2024'' WHEN k.pct IS NOT NULL THEN ''cop_dem30'' END AS src
                    FROM (%s) m, LATERAL (%s) k',
    CASE WHEN to_regclass('open.dem_mdt_slope') IS NOT NULL THEN
      'SELECT round(sum((ss).sum) / nullif(sum((ss).count), 0))::int AS pct
       FROM (SELECT ST_SummaryStats(ST_Clip(d.rast, 1, c.geom, true), 1, true) AS ss FROM open.dem_mdt_slope d
             WHERE ST_Intersects(d.rast, c.geom) AND NOT ST_Touches(ST_ConvexHull(d.rast), c.geom)) q'
    ELSE 'SELECT NULL::int AS pct' END,
    CASE WHEN to_regclass('open.dem_slope') IS NOT NULL THEN
      'SELECT round(sum((ss).sum) / nullif(sum((ss).count), 0))::int AS pct
       FROM (SELECT ST_SummaryStats(ST_Clip(d.rast, 1, c.geom, true), 1, true) AS ss FROM open.dem_slope d
             WHERE m.pct IS NULL AND ST_Intersects(d.rast, c.geom) AND NOT ST_Touches(ST_ConvexHull(d.rast), c.geom)) q'
    ELSE 'SELECT NULL::int AS pct' END);
  -- aspect: the pixel at the cell centre (MDT first, then Copernicus; COALESCE evaluates the second subquery only when
  -- the first is NULL). c.ctr is a column on purpose: with an expression such as ST_Centroid(c.geom) the raster
  -- ST_Intersects is not inlined, the tile index is skipped and the grid took 1.9 s instead of ~0.1 s (measured 2026-09-27)
  as_sql := format('SELECT coalesce(%s, %s) AS deg',
    CASE WHEN to_regclass('open.dem_mdt_aspect') IS NOT NULL THEN
      '(SELECT ST_Value(d.rast, 1, c.ctr)::int FROM open.dem_mdt_aspect d WHERE ST_Intersects(d.rast, c.ctr) LIMIT 1)'
    ELSE 'NULL::int' END,
    CASE WHEN to_regclass('open.dem_aspect') IS NOT NULL THEN
      '(SELECT ST_Value(d.rast, 1, c.ctr)::int FROM open.dem_aspect d WHERE ST_Intersects(d.rast, c.ctr) LIMIT 1)'
    ELSE 'NULL::int' END);
  IF t_ren IS NOT NULL THEN
    EXECUTE 'SELECT coalesce(array_agg(DISTINCT dico), ''{}'') FROM open.dgt_ren' INTO ren_dicos;
    -- a REN watercourse line crossing the cell counts as REN in it (its bed and banks are REN; the band width is unknown)
    ren_sql := format('SELECT bool_or(x.inside) AS inside, string_agg(DISTINCT x.t, '', '') AS types FROM (
                         SELECT z.tipologia NOT ILIKE ''exclus%%'' AS inside, z.tipologia AS t FROM %s z
                          WHERE ST_Intersects(z.geom, c.geom) AND ST_Area(ST_Intersection(z.geom, c.geom)) > 1 %s) x', t_ren,
                      CASE WHEN t_rl IS NULL THEN ''
                           ELSE format('UNION ALL SELECT true, ''Linhas de Água'' FROM %s l WHERE ST_Intersects(l.geom, c.geom)', t_rl) END);
  ELSE
    ren_sql := 'SELECT NULL::boolean AS inside, NULL::text AS types';
  END IF;
  IF t_ran IS NOT NULL THEN
    EXECUTE 'SELECT coalesce(array_agg(DISTINCT dico), ''{}'') FROM open.dgt_ran' INTO ran_dicos;
    ran_sql := format('SELECT EXISTS (SELECT 1 FROM %s z WHERE ST_Intersects(z.geom, c.geom) AND ST_Area(ST_Intersection(z.geom, c.geom)) > 1) AS inside', t_ran);
  ELSE
    ran_sql := 'SELECT NULL::boolean AS inside';
  END IF;
  IF to_regclass('open.dgt_construcoes') IS NOT NULL THEN
    bd_sql := 'SELECT count(*)::int AS n, round((100 * coalesce(sum(ST_Area(ST_Intersection(b.geom, c.geom))), 0) / ST_Area(c.geom))::numeric, 1) AS pct
               FROM open.dgt_construcoes b WHERE ST_Intersects(b.geom, c.geom)';
  ELSE
    bd_sql := 'SELECT NULL::int AS n, NULL::numeric AS pct';
  END IF;
  RETURN QUERY EXECUTE format($q$
    WITH cells AS (
      SELECT row_number() OVER (ORDER BY ST_Distance(c.geom, $1), c.i, c.j) AS id, c.geom, ST_Centroid(c.geom) AS ctr
      FROM ST_SquareGrid($2, $3) c WHERE ST_Intersects(c.geom, $3)
    )
    SELECT c.id, ST_X(ST_Transform(c.ctr, 4326)), ST_Y(ST_Transform(c.ctr, 4326)),
           round(ST_Distance(c.geom, $1))::int,
           mu.dico IS NOT NULL,
           -- explicit casts: RETURN QUERY rejects varchar where the signature says text (docs/lessons.md)
           fh.o::int, fh.cl::text, fz.inside, fz.perigo::text, fz.arpsi, pa.names::text,
           cr.classe::text, cr.categoria::text, cr.designacao::text, cr.esquema::text, bu.anos::int[],
           lc.label::text, lc.ano::int, sl.pct::int, open.slope_class(sl.pct)::text,
           asp.deg::int, open.aspect_class(asp.deg)::text, sl.src::text,
           CASE WHEN mu.dico = ANY ($4) THEN coalesce(rn.inside, false) END, rn.types::text,
           CASE WHEN mu.dico = ANY ($5) THEN ra.inside END,
           CASE WHEN mu.dico IS NOT NULL THEN bd.n END, CASE WHEN mu.dico IS NOT NULL THEN bd.pct END,
           ST_AsGeoJSON(ST_Transform(c.geom, 4326))::jsonb
    FROM cells c
    -- the pilot municipality under the cell centre (NULL outside the pilot regions → nothing there is known)
    LEFT JOIN LATERAL (SELECT p.dico FROM open.pilot_regions p WHERE ST_Intersects(p.geom, c.ctr) LIMIT 1) mu ON true
    LEFT JOIN LATERAL (SELECT h.classe_ord AS o, h.classe AS cl FROM %1$s h
                       WHERE ST_Intersects(h.geom, c.geom) AND ST_Area(ST_Intersection(h.geom, c.geom)) > 1
                       ORDER BY h.classe_ord DESC LIMIT 1) fh ON true
    LEFT JOIN LATERAL (SELECT EXISTS (SELECT 1 FROM %2$s z WHERE ST_Intersects(z.geom, c.geom)) AS inside,
                              (SELECT string_agg(DISTINCT z.perigo, ', ') FROM %3$s z WHERE ST_Intersects(z.geom, c.geom)) AS perigo,
                              EXISTS (SELECT 1 FROM %4$s z WHERE ST_Intersects(z.geom, c.geom)) AS arpsi) fz ON true
    -- DISTINCT: a subdivided area arrives as several pieces
    LEFT JOIN LATERAL (SELECT string_agg(DISTINCT z.nome || ' (' || z.rede || ')', '; ') AS names FROM %5$s z
                       WHERE ST_Intersects(z.geom, c.geom)) pa ON true
    -- dominant class by summed area (pieces of one polygon, or several polygons of one class, add up)
    LEFT JOIN LATERAL (SELECT x.classe, x.categoria, x.designacao_pdm AS designacao, x.esquema FROM %6$s x
                       WHERE ST_Intersects(x.geom, c.geom) GROUP BY 1, 2, 3, 4
                       ORDER BY sum(ST_Area(ST_Intersection(x.geom, c.geom))) DESC LIMIT 1) cr ON true
    LEFT JOIN LATERAL (SELECT array_agg(DISTINCT a.ano ORDER BY a.ano) AS anos FROM %7$s a
                       WHERE ST_Intersects(a.geom, c.geom)) bu ON true
    LEFT JOIN LATERAL (%8$s) lc ON true
    LEFT JOIN LATERAL (%9$s) sl ON true
    LEFT JOIN LATERAL (%10$s) asp ON true
    LEFT JOIN LATERAL (%11$s) rn ON true
    LEFT JOIN LATERAL (%12$s) ra ON true
    LEFT JOIN LATERAL (%13$s) bd ON true
    ORDER BY c.id $q$, t_per, t_zi, t_pi, t_ar, t_pr, t_cr, t_ard, lc_sql, sl_sql, as_sql, ren_sql, ran_sql, bd_sql)
  USING g, cell_m, search, ren_dicos, ran_dicos;
END $$;

GRANT EXECUTE ON FUNCTION open.facts_in(geometry) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.facts_for(text) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.constraints_grid(text, integer, integer) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.slope_class(numeric) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.aspect_class(numeric) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.relief_at(geometry, text) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.slope_class_en(numeric) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.aspect_class_en(numeric) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.hazard_en(text) TO territorio_ro;
GRANT EXECUTE ON FUNCTION open.fmt_num(numeric, integer, text) TO territorio_ro;

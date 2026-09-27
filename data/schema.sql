-- data/schema.sql — PostGIS schema for Território Explicado (pre-existing data platform)
-- What: creates schema `open`, the provenance table and the lookup functions used by the agent and by the
--       Zetaris views: facts_at (point), facts_for / facts_in (point or drawn plot, share of the plot per value),
--       constraints_grid (facts per cell around a place, no verdicts), slope_class / aspect_class (shared bands).
--       Idempotent. REN/RAN and buildings answer "outside"/"none" only where the data is loaded — elsewhere they say
--       "not available — not consulted" (unknown is never reported as free).
-- Depends on: PostGIS (+ postgis_raster for the relief rasters); tables loaded by data/etl/load.sh (open.caop_*,
--       open.cos2023, open.cos_serie, open.icnf_perigosidade, open.apa_*, open.ine_bgri2021, open.icnf_areas_ardidas,
--       open.icnf_areas_protegidas, open.dgt_crus, open.ine_precos_habitacao, open.ipma_rcm_snapshot, open.dem_elev,
--       open.dem_slope, open.dem_aspect, open.dgt_ren, open.dgt_ren_linhas, open.dgt_ran, open.dgt_construcoes, open.pilot_regions /
--       pilot_union; optional subdivided helpers open.grid_*) — every function guards missing tables.
-- Used by: data/etl/load.sh (runs it first), data/views.sql, data/etl/golden_fill.sh, the rehearsal explorer, the
--       agent's pg tool (inside the window).
-- When changing: the output columns are the evidence contract — facts_at (dataset, attribute, value, geom_geojson,
--       meta_id, sql_hint); facts_for/facts_in add share_pct and area_ha; constraints_grid's columns are read by the
--       alternatives map (by name). Changing them changes the agent's evidence schema.

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

-- facts_at(lon, lat): every layer that touches the point, one row per fact, with the geometry of the
-- intersected feature (simplified for the map) and the provenance id. Layers are added as they are
-- loaded; a missing table must not break the function, hence the EXISTS guards.
CREATE OR REPLACE FUNCTION open.facts_at(lon double precision, lat double precision)
RETURNS TABLE (dataset text, attribute text, value text, geom_geojson jsonb, meta_id text, sql_hint text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  p geometry := ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 3763);
  ren_note text := ' — REN watercourse lines not loaded';
BEGIN
  IF to_regclass('open.caop_freguesias') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'caop2025'::text, 'freguesia'::text, (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(f.geom, 20), 4326))::jsonb,
             'caop2025'::text, 'ST_Intersects(caop_freguesias.geom, point)'::text
      FROM open.caop_freguesias f WHERE ST_Intersects(f.geom, p);
  END IF;
  IF to_regclass('open.cos2023') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'cos2023'::text, 'land_cover'::text, c.cos_label::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(c.geom, 5), 4326))::jsonb,
             'cos2023'::text, 'ST_Intersects(cos2023.geom, point)'::text
      FROM open.cos2023 c WHERE ST_Intersects(c.geom, p);
  END IF;
  IF to_regclass('open.icnf_perigosidade') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_perigosidade'::text, 'fire_hazard_class'::text, h.classe::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(h.geom, 5), 4326))::jsonb,
             'icnf_perigosidade'::text, 'ST_Intersects(icnf_perigosidade.geom, point)'::text
      FROM open.icnf_perigosidade h WHERE ST_Intersects(h.geom, p);
  END IF;
  IF to_regclass('open.apa_perigo_inundacao') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_perigo'::text, 'flood_hazard_class'::text,
             (z.perigo || ' — ' || coalesce(z.local, '?') || ' (' || coalesce(z.designa, '?') || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 5), 4326))::jsonb,
             'apa_perigo'::text, 'ST_Intersects(apa_perigo_inundacao.geom, point)'::text
      FROM open.apa_perigo_inundacao z WHERE ST_Intersects(z.geom, p);
  END IF;
  IF to_regclass('open.apa_zonas_inundaveis') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_zonas_inundaveis'::text, 'flood_extent'::text,
             ('inside the ' || CASE z.pretorno::text WHEN 'T0020' THEN '20-year' WHEN 'T0100' THEN '100-year' WHEN 'T1000' THEN '1000-year' ELSE z.pretorno::text END
              || ' return-period flood zone; max water level ' || coalesce(z.nivel_max::text, '?') || ' m — ' || coalesce(z.local, '?'))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 2), 4326))::jsonb,
             'apa_zonas_inundaveis'::text, 'ST_Intersects(apa_zonas_inundaveis.geom, point)'::text
      FROM open.apa_zonas_inundaveis z WHERE ST_Intersects(z.geom, p) ORDER BY z.pretorno;
  END IF;
  IF to_regclass('open.apa_arpsi') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_arpsi'::text, 'designated_flood_risk_area'::text,
             (coalesce(z.name, '?') || ' — ' || coalesce(z.uomname, '?') || ' (' || coalesce(z.local, '?') || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 5), 4326))::jsonb,
             'apa_arpsi'::text, 'ST_Intersects(apa_arpsi.geom, point)'::text
      FROM open.apa_arpsi z WHERE ST_Intersects(z.geom, p);
  END IF;
  IF to_regclass('open.apa_marcas_cheia') IS NOT NULL THEN   -- proximity evidence, not intersection: nearest historical flood marks within 1 km
    RETURN QUERY
      SELECT 'apa_marcas_cheia'::text, 'flood_mark_nearby'::text,
             (coalesce(m.descricao, '?') || ' — level ' || coalesce(m.cota_inundacao::text, '?') || ' m'
              || coalesce(', ' || to_char(to_timestamp(m.data::double precision / 1000), 'YYYY-MM-DD'), '')
              || ' (' || coalesce(m.fonte, '?') || '), ' || round(ST_Distance(m.geom, p)) || ' m away')::text,
             ST_AsGeoJSON(ST_Transform(m.geom, 4326))::jsonb,
             'apa_marcas_cheia'::text, 'ST_DWithin(apa_marcas_cheia.geom, point, 1000) ORDER BY distance LIMIT 3'::text
      FROM open.apa_marcas_cheia m WHERE ST_DWithin(m.geom, p, 1000) ORDER BY ST_Distance(m.geom, p) LIMIT 3;
  END IF;
  IF to_regclass('open.ine_bgri2021') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'ine_bgri2021'::text, 'census_subsection'::text,
             ('BGRI ' || b.bgri2021 || ': ' || b.n_individuos::int || ' residents, ' || b.n_edificios::int || ' buildings, ' || b.n_alojamentos::int || ' dwellings')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(b.geom, 5), 4326))::jsonb,
             'ine_bgri2021'::text, 'ST_Intersects(ine_bgri2021.geom, point)'::text
      FROM open.ine_bgri2021 b WHERE ST_Intersects(b.geom, p);
  END IF;
  IF to_regclass('open.icnf_areas_ardidas') IS NOT NULL THEN   -- one row per fire that burned the point + one summary row
    RETURN QUERY
      SELECT 'icnf_areas_ardidas'::text, 'burned_area'::text,
             ('burned in ' || a.ano || coalesce(' (fire started ' || left(a.dh_inicio, 10) || ')', '')
              || ' — ' || coalesce(a.area_ha::text, '?') || ' ha burned in total'
              || coalesce('; cause: ' || lower(a.causa_tipo), ''))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(a.geom, 10), 4326))::jsonb,
             'icnf_areas_ardidas'::text, 'ST_Intersects(icnf_areas_ardidas.geom, point) ORDER BY ano DESC'::text
      FROM open.icnf_areas_ardidas a WHERE ST_Intersects(a.geom, p) ORDER BY a.ano DESC;
    RETURN QUERY
      SELECT 'icnf_areas_ardidas'::text, 'burn_history'::text,
             (count(*) || ' burned-area record(s) since 1975 (' || string_agg(DISTINCT a.ano::text, ', ' ORDER BY a.ano::text) || '); '
              || count(*) FILTER (WHERE a.ano >= extract(year FROM now())::int - 10)
              || ' in the last 10 years (since ' || (extract(year FROM now())::int - 10) || '); record 1975–2025')::text,
             NULL::jsonb, 'icnf_areas_ardidas'::text,
             'count(*), count(*) FILTER (WHERE ano >= year(now()) - 10) FROM icnf_areas_ardidas WHERE ST_Intersects(geom, point)'::text
      FROM open.icnf_areas_ardidas a WHERE ST_Intersects(a.geom, p) HAVING count(*) > 0;
  END IF;
  IF to_regclass('open.icnf_areas_protegidas') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_areas_protegidas'::text, 'protected_area'::text,
             (z.nome || ' — ' || z.rede || ', ' || coalesce(z.categoria, '?') || coalesce(' (' || z.codigo || ')', '')
              || coalesce('; diploma: ' || z.diploma, ''))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 20), 4326))::jsonb,
             'icnf_areas_protegidas'::text, 'ST_Intersects(icnf_areas_protegidas.geom, point)'::text
      FROM open.icnf_areas_protegidas z WHERE ST_Intersects(z.geom, p) ORDER BY z.rede DESC, z.categoria;
  END IF;
  IF to_regclass('open.dgt_crus') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'dgt_crus'::text, 'land_use_plan_class'::text,
             (coalesce(c.classe || ' — ' || coalesce(c.categoria, '?'), 'not re-coded to DR 15/2015 classes')
              || ' (PDM ' || coalesce(c.municipio, '?') || ': "' || coalesce(c.designacao_pdm, '?') || '", scale '
              || coalesce(c.escala, '?') || ', PDM published ' || coalesce(c.data_publicacao_pdm, '?') || ')')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(c.geom, 5), 4326))::jsonb,
             'dgt_crus'::text, 'ST_Intersects(dgt_crus.geom, point)'::text
      FROM open.dgt_crus c WHERE ST_Intersects(c.geom, p);
  END IF;
  IF to_regclass('open.ine_precos_habitacao') IS NOT NULL THEN   -- parish row (where INE publishes it) + municipality row
    RETURN QUERY
      SELECT 'ine_precos_habitacao'::text, ('median_price_eur_m2_' || i.nivel)::text,
             (coalesce(i.eur_m2 || ' €/m²', 'not published (' || coalesce(i.nota, 'no value') || ')')
              || ' — median of family-dwelling sales, 12 months to ' || i.periodo || ', ' || i.nivel || ' ' || i.nome)::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(i.geom, 20), 4326))::jsonb,
             'ine_precos_habitacao'::text, 'ST_Intersects(ine_precos_habitacao.geom, point)'::text
      FROM open.ine_precos_habitacao i WHERE ST_Intersects(i.geom, p) ORDER BY i.nivel;
  END IF;
  IF to_regclass('open.ipma_rcm_snapshot') IS NOT NULL THEN   -- latest stored forecast for the municipality; stale by design
    RETURN QUERY
      SELECT 'ipma_rcm'::text, 'fire_risk_forecast_snapshot'::text,
             ('RCM ' || r.rcm || ' — ' || r.rcm_label || ' for ' || r.data_prev || ' (IPMA forecast run ' || r.data_run
              || '; stored snapshot retrieved ' || to_char(r.retrieved_at, 'YYYY-MM-DD') || ' — read the live API for today)')::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(m.geom, 50), 4326))::jsonb,
             'ipma_rcm'::text, 'ipma_rcm_snapshot WHERE dico = municipality(point) ORDER BY data_prev DESC LIMIT 1'::text
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
             ('cos' || c.ano)::text, 'ST_Intersects(cos_serie.geom, point) WHERE ano = ' || c.ano
      FROM open.cos_serie c WHERE ST_Intersects(c.geom, p) ORDER BY c.ano;
  END IF;
  IF to_regclass('open.dem_slope') IS NOT NULL AND to_regclass('open.dem_elev') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'cop_dem30'::text, 'slope_pct'::text,
             ('slope ≈ ' || v.s || ' % — ' || open.slope_class(v.s) || ' (Copernicus GLO-30 surface model at 25 m: canopy and buildings bias it)')::text,
             NULL::jsonb, 'cop_dem30'::text, 'ST_Value(dem_slope.rast, point)'::text
      FROM (SELECT ST_Value(d.rast, 1, p)::numeric AS s FROM open.dem_slope d WHERE ST_Intersects(d.rast, p) LIMIT 1) v WHERE v.s IS NOT NULL;
    RETURN QUERY
      SELECT 'cop_dem30'::text, 'elevation_m'::text, ('elevation ≈ ' || v.e || ' m (surface model)')::text,
             NULL::jsonb, 'cop_dem30'::text, 'ST_Value(dem_elev.rast, point)'::text
      FROM (SELECT ST_Value(d.rast, 1, p)::numeric AS e FROM open.dem_elev d WHERE ST_Intersects(d.rast, p) LIMIT 1) v WHERE v.e IS NOT NULL;
  END IF;
  IF to_regclass('open.dem_aspect') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'cop_dem30'::text, 'aspect'::text,
             (CASE WHEN v.a < 0 THEN 'flat — no aspect' ELSE 'aspect ≈ ' || v.a || '° — facing ' || open.aspect_class(v.a) END
              || ' (Copernicus GLO-30 surface model at 25 m)')::text,
             NULL::jsonb, 'cop_dem30'::text, 'ST_Value(dem_aspect.rast, point)'::text
      FROM (SELECT ST_Value(d.rast, 1, p)::numeric AS a FROM open.dem_aspect d WHERE ST_Intersects(d.rast, p) LIMIT 1) v WHERE v.a IS NOT NULL;
  END IF;
  -- REN / RAN (DGT SRUP): inside; or outside — stated ONLY where the municipality's delimitation is loaded; a pilot
  -- municipality without data says "not available — not consulted", never "not in REN". 'Exclusões' = areas taken OUT
  -- of the REN by the municipal delimitation. Map geometry: the part within 300 m of the point (a whole municipality's
  -- REN is one huge multipolygon).
  IF to_regclass('open.dgt_ren') IS NOT NULL THEN
    -- REN watercourse lines (dgt_ren_linhas) are published only for some municipalities → the "outside" row says which case applies
    IF to_regclass('open.dgt_ren_linhas') IS NOT NULL THEN
      SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM open.dgt_ren_linhas l JOIN open.caop_municipios m ON m.dico = l.dico WHERE ST_Intersects(m.geom, p))
                  THEN ' — REN watercourse lines are not published for this municipality (a stream bed may still be REN)'
                  WHEN EXISTS (SELECT 1 FROM open.dgt_ren_linhas l WHERE ST_DWithin(l.geom, p, 100))
                  THEN ' — but a REN watercourse line runs within 100 m (see ecological_reserve_watercourse)'
                  ELSE ' — no REN watercourse line within 100 m' END INTO ren_note;
      RETURN QUERY
        SELECT 'dgt_ren'::text, 'ecological_reserve_watercourse'::text,
               ('REN watercourse line (' || coalesce(l.tipologia, '?') || ', ' || coalesce(l.concelho, '?') || ') ' || round(ST_Distance(l.geom, p))
                || ' m from the point — the REN covers the bed and banks; the band width is not in this layer')::text,
               ST_AsGeoJSON(ST_Transform(ST_Intersection(l.geom, ST_Buffer(p, 300)), 4326))::jsonb,
               'dgt_ren_linhas'::text, 'ST_DWithin(dgt_ren_linhas.geom, point, 100) ORDER BY distance LIMIT 1'::text
        FROM open.dgt_ren_linhas l WHERE ST_DWithin(l.geom, p, 100) ORDER BY ST_Distance(l.geom, p) LIMIT 1;
    END IF;
    RETURN QUERY
      SELECT 'dgt_ren'::text, 'ecological_reserve'::text,
             (CASE WHEN r.tipologia ILIKE 'exclus%' THEN 'EXCLUDED from the REN (exclusion area of the municipal delimitation — not a REN constraint)'
                   ELSE 'inside the REN (' || r.tipologia || ')' END
              || ' — ' || r.concelho || ': ' || coalesce(r.designacao, '?') || '; ' || coalesce(r.diploma, '?') || coalesce(', DR ' || r.dr, '')
              || coalesce(' <' || r.diploma_url || '>', '') || '; map ' || coalesce(r.escala, '?') || ' of ' || coalesce(r.data_geometria, '?'))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(ST_Intersection(r.geom, ST_Buffer(p, 300)), 2), 4326))::jsonb,
             'dgt_ren'::text, 'ST_Intersects(dgt_ren.geom, point); map geometry = part within 300 m'::text
      FROM open.dgt_ren r WHERE ST_Intersects(r.geom, p);
    RETURN QUERY
      SELECT 'dgt_ren'::text, 'ecological_reserve'::text,
             (CASE WHEN count(r.dico) > 0
                   THEN 'outside the REN areas of ' || m.concelho || ' (' || string_agg(DISTINCT r.diploma, '; ') || ')' || ren_note
                   ELSE 'REN not available for ' || m.concelho || ' in this database — not consulted' END)::text,
             NULL::jsonb, 'dgt_ren'::text, 'NOT ST_Intersects(dgt_ren.geom, point) — municipal delimitation checked'::text
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
             'dgt_ran'::text, 'ST_Intersects(dgt_ran.geom, point); map geometry = part within 300 m'::text
      FROM open.dgt_ran r WHERE ST_Intersects(r.geom, p);
    RETURN QUERY
      SELECT 'dgt_ran'::text, 'agricultural_reserve'::text,
             (CASE WHEN count(r.dico) > 0 THEN 'outside the RAN of ' || m.concelho || ' (municipal delimitation loaded)'
                   ELSE 'RAN not available for ' || m.concelho || ' in this database — not consulted' END)::text,
             NULL::jsonb, 'dgt_ran'::text, 'NOT ST_Intersects(dgt_ran.geom, point) — municipal delimitation checked'::text
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
             ST_AsGeoJSON(ST_Transform(b.geom, 4326))::jsonb, 'mconst_lidar2024'::text, 'ST_Intersects(dgt_construcoes.geom, point)'::text
      FROM open.dgt_construcoes b WHERE ST_Intersects(b.geom, p);
    RETURN QUERY
      SELECT 'mconst_lidar2024'::text, 'buildings_nearby'::text,
             (CASE WHEN s.n200 = 0 THEN 'no building footprint within 200 m'
                   ELSE s.n50 || ' building footprint(s) within 50 m, ' || s.n200 || ' within 200 m; nearest ' || s.d || ' m away' END
              || ' (LiDAR 2024)' || CASE WHEN ST_DWithin(u.boundary, p, 200) THEN ' — the 200 m circle crosses the edge of the pilot regions; buildings beyond it are not loaded' ELSE '' END)::text,
             NULL::jsonb, 'mconst_lidar2024'::text, 'count(*) FROM dgt_construcoes WHERE ST_DWithin(geom, point, 50 | 200)'::text
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
-- polygon evidence contract; attribute names match facts_at so rules can treat point and plot alike.
CREATE OR REPLACE FUNCTION open.facts_in(g geometry)
RETURNS TABLE (dataset text, attribute text, value text, share_pct numeric, area_ha numeric, geom_geojson jsonb, meta_id text, sql_hint text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  a_total double precision := ST_Area(g);
  pct text := 'round(100 * ST_Area(ST_Intersection(layer.geom, plot)) / ST_Area(plot), 1)';
BEGIN
  IF a_total <= 0 THEN RAISE EXCEPTION 'facts_in: empty polygon'; END IF;
  IF a_total > 1e7 THEN RAISE EXCEPTION 'facts_in: polygon of % ha — limit is 1 000 ha', round((a_total / 1e4)::numeric); END IF;
  RETURN QUERY   -- how much of the plot the database covers at all (outside the pilot regions only CAOP answers)
    SELECT 'pilot_regions'::text, 'coverage'::text,
           (round((100 * coalesce(ST_Area(ST_Intersection(u.geom, g)), 0) / a_total)::numeric, 1) || '% of the area lies in the pilot regions'
            || coalesce(' (' || (SELECT string_agg(DISTINCT p.region, ', ') FROM open.pilot_regions p WHERE ST_Intersects(p.geom, g)) || ')', ''))::text,
           round((100 * coalesce(ST_Area(ST_Intersection(u.geom, g)), 0) / a_total)::numeric, 1), round((a_total / 1e4)::numeric, 2),
           NULL::jsonb, 'caop2025'::text, 'ST_Area(ST_Intersection(pilot_union.geom, plot)) / ST_Area(plot)'::text
    FROM open.pilot_union u;
  IF to_regclass('open.caop_freguesias') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'caop2025'::text, 'freguesia'::text, (f.freguesia || ' (' || f.concelho || ', ' || f.distrito || ')')::text,
             round((100 * ST_Area(x.gi) / a_total)::numeric, 1), round((ST_Area(x.gi) / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(x.gi, 2), 4326))::jsonb,
             'caop2025'::text, 'ST_Intersection(caop_freguesias.geom, plot)'::text
      FROM open.caop_freguesias f CROSS JOIN LATERAL (SELECT ST_Intersection(f.geom, g) AS gi) x
      WHERE ST_Intersects(f.geom, g) ORDER BY ST_Area(x.gi) DESC;
  END IF;
  IF to_regclass('open.cos2023') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'cos2023'::text, 'land_cover'::text, s.v::text, round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'cos2023'::text, 'sum(ST_Area(ST_Intersection(cos2023.geom, plot))) GROUP BY cos_label'::text
      FROM (SELECT c.cos_label AS v, sum(ST_Area(ST_Intersection(c.geom, g))) AS a, ST_Union(ST_Intersection(c.geom, g)) AS gu
            FROM open.cos2023 c WHERE ST_Intersects(c.geom, g) GROUP BY c.cos_label) s
      WHERE s.a > 0 ORDER BY s.a DESC;
  END IF;
  IF to_regclass('open.icnf_perigosidade') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_perigosidade'::text, 'fire_hazard_class'::text, s.v::text, round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'icnf_perigosidade'::text, 'sum(ST_Area(ST_Intersection(icnf_perigosidade.geom, plot))) GROUP BY classe'::text
      FROM (SELECT h.classe AS v, max(h.classe_ord) AS o, sum(ST_Area(ST_Intersection(h.geom, g))) AS a, ST_Union(ST_Intersection(h.geom, g)) AS gu
            FROM open.icnf_perigosidade h WHERE ST_Intersects(h.geom, g) GROUP BY h.classe) s
      WHERE s.a > 0 ORDER BY s.o DESC;
  END IF;
  IF to_regclass('open.apa_perigo_inundacao') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_perigo'::text, 'flood_hazard_class'::text, (s.v || ' — ' || coalesce(s.l, '?'))::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'apa_perigo'::text, 'sum(ST_Area(ST_Intersection(apa_perigo_inundacao.geom, plot))) GROUP BY perigo'::text
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
             'apa_zonas_inundaveis'::text, 'sum(ST_Area(ST_Intersection(apa_zonas_inundaveis.geom, plot))) GROUP BY pretorno'::text
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
             'apa_arpsi'::text, 'ST_Intersection(apa_arpsi.geom, plot)'::text
      FROM open.apa_arpsi z CROSS JOIN LATERAL (SELECT ST_Intersection(z.geom, g) AS gi) x WHERE ST_Intersects(z.geom, g);
  END IF;
  IF to_regclass('open.apa_marcas_cheia') IS NOT NULL THEN   -- proximity, not area: nearest historical flood marks ≤ 1 km of the plot
    RETURN QUERY
      SELECT 'apa_marcas_cheia'::text, 'flood_mark_nearby'::text,
             (coalesce(m.descricao, '?') || ' — level ' || coalesce(m.cota_inundacao::text, '?') || ' m'
              || coalesce(', ' || to_char(to_timestamp(m.data::double precision / 1000), 'YYYY-MM-DD'), '')
              || ', ' || CASE WHEN ST_Intersects(m.geom, g) THEN 'inside the plot' ELSE round(ST_Distance(m.geom, g)) || ' m from the plot' END)::text,
             NULL::numeric, NULL::numeric, ST_AsGeoJSON(ST_Transform(m.geom, 4326))::jsonb,
             'apa_marcas_cheia'::text, 'ST_DWithin(apa_marcas_cheia.geom, plot, 1000) ORDER BY distance LIMIT 3'::text
      FROM open.apa_marcas_cheia m WHERE ST_DWithin(m.geom, g, 1000) ORDER BY ST_Distance(m.geom, g) LIMIT 3;
  END IF;
  IF to_regclass('open.ine_bgri2021') IS NOT NULL THEN   -- whole-subsection totals: census counts are not spread by area
    RETURN QUERY
      SELECT 'ine_bgri2021'::text, 'census_subsections'::text,
             (count(*) || ' census subsection(s) touched — whole-subsection totals, not area-weighted: '
              || sum(b.n_individuos)::int || ' residents, ' || sum(b.n_edificios)::int || ' buildings, ' || sum(b.n_alojamentos)::int || ' dwellings')::text,
             NULL::numeric, NULL::numeric, NULL::jsonb, 'ine_bgri2021'::text, 'sum(n_*) FROM ine_bgri2021 WHERE ST_Intersects(geom, plot)'::text
      FROM open.ine_bgri2021 b WHERE ST_Intersects(b.geom, g) HAVING count(*) > 0;
  END IF;
  IF to_regclass('open.icnf_areas_ardidas') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'icnf_areas_ardidas'::text, 'burned_area'::text,
             ('burned in ' || s.ano || coalesce(' (fire started ' || s.d || ')', '') || ' — fire of ' || coalesce(s.fa::text, '?') || ' ha in total')::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'icnf_areas_ardidas'::text, 'ST_Area(ST_Union(ST_Intersection(icnf_areas_ardidas.geom, plot))) GROUP BY ano'::text
      FROM (SELECT a.ano, min(left(a.dh_inicio, 10)) AS d, max(a.area_ha) AS fa,
                   ST_Area(ST_Union(ST_Intersection(a.geom, g))) AS a, ST_Union(ST_Intersection(a.geom, g)) AS gu
            FROM open.icnf_areas_ardidas a WHERE ST_Intersects(a.geom, g) GROUP BY a.ano) s
      WHERE s.a > 0 ORDER BY s.ano DESC;
    RETURN QUERY   -- overlapping fires counted once: union of every perimeter inside the plot
      SELECT 'icnf_areas_ardidas'::text, 'burn_history'::text,
             (round((100 * s.aa / a_total)::numeric, 1) || '% of the area burned at least once since 1975; '
              || round((100 * s.a10 / a_total)::numeric, 1) || '% in the last 10 years (since ' || (extract(year FROM now())::int - 10) || ')')::text,
             round((100 * s.aa / a_total)::numeric, 1), round((s.aa / 1e4)::numeric, 2), NULL::jsonb, 'icnf_areas_ardidas'::text,
             'ST_Area(ST_Union(ST_Intersection(icnf_areas_ardidas.geom, plot)))'::text
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
             'icnf_areas_protegidas'::text, 'ST_Intersection(icnf_areas_protegidas.geom, plot)'::text
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
             'dgt_crus'::text, 'sum(ST_Area(ST_Intersection(dgt_crus.geom, plot))) GROUP BY classe, categoria, designacao_pdm'::text
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
             NULL::jsonb, 'ine_precos_habitacao'::text, 'ST_Intersects(ine_precos_habitacao.geom, plot)'::text
      FROM open.ine_precos_habitacao i CROSS JOIN LATERAL (SELECT ST_Intersection(i.geom, g) AS gi) x
      WHERE ST_Intersects(i.geom, g) ORDER BY i.nivel, ST_Area(x.gi) DESC;
  END IF;
  IF to_regclass('open.ipma_rcm_snapshot') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'ipma_rcm'::text, 'fire_risk_forecast_snapshot'::text,
             ('RCM ' || r.rcm || ' — ' || r.rcm_label || ' for ' || r.data_prev || ' in ' || m.concelho
              || ' (IPMA forecast run ' || r.data_run || '; stored snapshot — read the live API for today)')::text,
             round((100 * ST_Area(ST_Intersection(m.geom, g)) / a_total)::numeric, 1), NULL::numeric, NULL::jsonb,
             'ipma_rcm'::text, 'ipma_rcm_snapshot WHERE dico = municipality(plot) ORDER BY data_prev DESC LIMIT 1'::text
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
             ('cos' || s.ano)::text, 'sum(ST_Area(ST_Intersection(cos_serie.geom, plot))) GROUP BY ano, label_n4'::text
      FROM (SELECT c.ano, c.serie AS se, c.label_n4 AS v, sum(ST_Area(ST_Intersection(c.geom, g))) AS a, ST_Union(ST_Intersection(c.geom, g)) AS gu
            FROM open.cos_serie c WHERE ST_Intersects(c.geom, g) GROUP BY 1, 2, 3) s
      WHERE s.a > 0 ORDER BY s.ano, s.a DESC;
  END IF;
  IF to_regclass('open.dem_slope') IS NOT NULL AND to_regclass('open.dem_elev') IS NOT NULL THEN
    RETURN QUERY   -- 25 m pixels: a 1 ha plot is ~16 pixels, so shares are coarse — said in the value
      SELECT 'cop_dem30'::text, 'slope_class'::text,
             (open.slope_class(min(q.val)) || ' — ' || round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1) || ' % of the plot ('
              || sum(sum(q.cnt)) OVER () || ' pixels of 25 m, surface model)')::text,
             round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1), round((sum(q.cnt) * 625 / 1e4)::numeric, 2), NULL::jsonb,
             'cop_dem30'::text, 'ST_ValueCount(ST_Clip(dem_slope.rast, plot)) grouped by slope class'::text
      FROM (SELECT (vc).value::numeric AS val, (vc).count AS cnt
            FROM (SELECT ST_ValueCount(ST_Clip(d.rast, 1, g, true), 1, true) AS vc FROM open.dem_slope d WHERE ST_Intersects(d.rast, g)) x) q
      GROUP BY open.slope_class(q.val) ORDER BY min(q.val);
    RETURN QUERY
      SELECT 'cop_dem30'::text, 'elevation_m'::text,
             ('elevation ' || round(min(st.mn)) || '–' || round(max(st.mx)) || ' m, mean ≈ ' || round(sum(st.sm) / nullif(sum(st.n), 0)) || ' m (surface model)')::text,
             NULL::numeric, NULL::numeric, NULL::jsonb, 'cop_dem30'::text, 'ST_SummaryStats(ST_Clip(dem_elev.rast, plot))'::text
      FROM (SELECT (ss).min AS mn, (ss).max AS mx, (ss).sum AS sm, (ss).count AS n
            FROM (SELECT ST_SummaryStats(ST_Clip(d.rast, 1, g, true), 1, true) AS ss FROM open.dem_elev d WHERE ST_Intersects(d.rast, g)) x
            WHERE (ss).count > 0) st
      HAVING sum(st.n) > 0;
  END IF;
  IF to_regclass('open.dem_aspect') IS NOT NULL THEN
    RETURN QUERY   -- same pixel caveat as slope; -9999 pixels (flat) form their own class
      SELECT 'cop_dem30'::text, 'aspect_class'::text,
             ('facing ' || open.aspect_class(min(q.val)) || ' — ' || round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1) || ' % of the plot ('
              || sum(sum(q.cnt)) OVER () || ' pixels of 25 m, surface model)')::text,
             round(100.0 * sum(q.cnt) / sum(sum(q.cnt)) OVER (), 1), round((sum(q.cnt) * 625 / 1e4)::numeric, 2), NULL::jsonb,
             'cop_dem30'::text, 'ST_ValueCount(ST_Clip(dem_aspect.rast, plot)) grouped by aspect class'::text
      FROM (SELECT (vc).value::numeric AS val, (vc).count AS cnt
            FROM (SELECT ST_ValueCount(ST_Clip(d.rast, 1, g, true), 1, true) AS vc FROM open.dem_aspect d WHERE ST_Intersects(d.rast, g)) x) q
      GROUP BY open.aspect_class(q.val) ORDER BY sum(q.cnt) DESC;
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
             'dgt_ren'::text, 'ST_Area(ST_Union(ST_Intersection(dgt_ren.geom, plot))) GROUP BY tipologia, diploma'::text
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
               'dgt_ren_linhas'::text, 'ST_Length(ST_Intersection(dgt_ren_linhas.geom, plot))'::text
        FROM open.dgt_ren_linhas l WHERE ST_Intersects(l.geom, g) HAVING count(*) > 0;
    END IF;
    RETURN QUERY
      SELECT 'dgt_ren'::text, 'ecological_reserve'::text, ('REN not available for ' || m.concelho || ' in this database — not consulted')::text,
             round((100 * ST_Area(ST_Intersection(m.geom, g)) / a_total)::numeric, 1), NULL::numeric, NULL::jsonb, 'dgt_ren'::text,
             'caop_municipios ∩ plot, municipality without dgt_ren rows'::text
      FROM open.caop_municipios m JOIN open.pilot_regions pr ON pr.dico = m.dico
      WHERE ST_Intersects(m.geom, g) AND NOT EXISTS (SELECT 1 FROM open.dgt_ren r WHERE r.dico = m.dico);
  END IF;
  IF to_regclass('open.dgt_ran') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'dgt_ran'::text, 'agricultural_reserve'::text, ('inside the RAN — ' || coalesce(s.c, '?') || ' (map of ' || coalesce(s.dt, '?') || ')')::text,
             round((100 * s.a / a_total)::numeric, 1), round((s.a / 1e4)::numeric, 2),
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(s.gu, 2), 4326))::jsonb,
             'dgt_ran'::text, 'ST_Area(ST_Union(ST_Intersection(dgt_ran.geom, plot))) GROUP BY concelho'::text
      FROM (SELECT r.concelho AS c, max(r.data_geometria) AS dt, ST_Area(ST_Union(ST_Intersection(r.geom, g))) AS a,
                   ST_Union(ST_Intersection(r.geom, g)) AS gu
            FROM open.dgt_ran r WHERE ST_Intersects(r.geom, g) GROUP BY 1) s
      WHERE s.a > 0 ORDER BY s.a DESC;
    RETURN QUERY
      SELECT 'dgt_ran'::text, 'agricultural_reserve'::text, ('RAN not available for ' || m.concelho || ' in this database — not consulted')::text,
             round((100 * ST_Area(ST_Intersection(m.geom, g)) / a_total)::numeric, 1), NULL::numeric, NULL::jsonb, 'dgt_ran'::text,
             'caop_municipios ∩ plot, municipality without dgt_ran rows'::text
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
             ST_AsGeoJSON(ST_Transform(s.gc, 4326))::jsonb, 'mconst_lidar2024'::text, 'ST_Intersection(dgt_construcoes.geom, plot)'::text
      FROM (SELECT count(*) AS n, sum(ST_Area(ST_Intersection(b.geom, g))) AS a, ST_Collect(ST_Intersection(b.geom, g)) AS gc
            FROM open.dgt_construcoes b WHERE ST_Intersects(b.geom, g)) s
      WHERE s.n > 0;
    RETURN QUERY
      SELECT 'mconst_lidar2024'::text, 'buildings_in_plot'::text,
             ('no building footprint inside the plot (LiDAR 2024); ' || coalesce('nearest one ' || n.d || ' m away', 'none within 1 km'))::text,
             0::numeric, 0::numeric, NULL::jsonb, 'mconst_lidar2024'::text, 'ST_Distance to the nearest dgt_construcoes footprint (KNN)'::text
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
-- repair is reported as a row, so the answer can say the drawn shape was corrected.
CREATE OR REPLACE FUNCTION open.facts_for(geojson text)
RETURNS TABLE (dataset text, attribute text, value text, share_pct numeric, area_ha numeric, geom_geojson jsonb, meta_id text, sql_hint text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  j jsonb := geojson::jsonb;
  g geometry;
BEGIN
  IF j->>'type' = 'Feature' THEN j := j->'geometry'; END IF;
  g := ST_SetSRID(ST_GeomFromGeoJSON(j::text), 4326);
  IF GeometryType(g) = 'POINT' THEN
    RETURN QUERY SELECT f.dataset, f.attribute, f.value, 100::numeric, NULL::numeric, f.geom_geojson, f.meta_id, f.sql_hint
                 FROM open.facts_at(ST_X(g), ST_Y(g)) f;
  ELSIF GeometryType(g) IN ('POLYGON', 'MULTIPOLYGON') THEN
    g := ST_Transform(g, 3763);
    IF NOT ST_IsValid(g) THEN
      g := ST_Multi(ST_CollectionExtract(ST_MakeValid(g), 3));
      RETURN QUERY SELECT 'input'::text, 'geometry_repaired'::text,
        'the drawn polygon was not valid (e.g. crossing edges) and was repaired before the analysis'::text,
        NULL::numeric, round((ST_Area(g) / 1e4)::numeric, 2), NULL::jsonb, NULL::text, 'ST_MakeValid(plot)'::text;
    END IF;
    RETURN QUERY SELECT * FROM open.facts_in(g);
  ELSE
    RAISE EXCEPTION 'facts_for: % is not supported — send a Point or a Polygon', GeometryType(g);
  END IF;
END $$;

-- constraints_grid(geojson, radius_m, cell_m): what surrounds a point or a plot, cell by cell — the raw material for
-- "not here, but there". Square cells (fixed grid, origin 0,0 in EPSG:3763) within radius_m of the input; per cell:
-- worst fire-hazard class, flood extent / hazard / ARPSI, protected areas, dominant PDM (CRUS) class, fire years in the
-- cell, dominant land cover (newest COS edition loaded), mean slope, aspect at the cell centre, REN / RAN, building
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
               aspect_deg integer, aspect_class text, in_ren boolean, ren_types text, in_ran boolean,
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
  IF to_regclass('open.dem_slope') IS NOT NULL THEN
    sl_sql := 'SELECT round(sum((ss).sum) / nullif(sum((ss).count), 0))::int AS pct
               FROM (SELECT ST_SummaryStats(ST_Clip(d.rast, 1, c.geom, true), 1, true) AS ss FROM open.dem_slope d
                     WHERE ST_Intersects(d.rast, c.geom)) q';
  ELSE
    sl_sql := 'SELECT NULL::int AS pct';
  END IF;
  -- aspect: the pixel at the cell centre (a 50 m cell is 4 pixels of 25 m). c.ctr is a column on purpose: with an
  -- expression such as ST_Centroid(c.geom) the raster ST_Intersects is not inlined, the tile index is skipped and the
  -- grid took 1.9 s instead of ~0.1 s (measured 2026-09-27)
  IF to_regclass('open.dem_aspect') IS NOT NULL THEN
    as_sql := 'SELECT ST_Value(d.rast, 1, c.ctr)::int AS deg FROM open.dem_aspect d
               WHERE ST_Intersects(d.rast, c.ctr) LIMIT 1';
  ELSE
    as_sql := 'SELECT NULL::int AS deg';
  END IF;
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
           asp.deg::int, open.aspect_class(asp.deg)::text,
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

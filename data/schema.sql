-- data/schema.sql — PostGIS schema for Território Explicado (pre-existing data platform)
-- What: creates schema `open`, the provenance table and the point-lookup function used by the agent
--       and by the Zetaris views. Idempotent.
-- Depends on: PostGIS extension; tables loaded by data/etl/load.sh (open.caop_*, open.cos2023,
--       open.icnf_perigosidade, open.apa_perigo_inundacao, open.apa_zonas_inundaveis, open.apa_arpsi,
--       open.apa_marcas_cheia, open.ine_bgri2021, open.icnf_areas_ardidas, open.icnf_areas_protegidas,
--       open.dgt_crus, open.ine_precos_habitacao, open.ipma_rcm_snapshot).
-- Used by: data/etl/load.sh (runs it first), data/views.sql, the agent's pg tool (facts_at).
-- When changing: facts_at() output columns are the evidence contract (dataset, attribute, value,
--       geom_geojson, meta_id, sql_hint) — changing them changes the agent's evidence schema.

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

-- facts_at(lon, lat): every layer that touches the point, one row per fact, with the geometry of the
-- intersected feature (simplified for the map) and the provenance id. Layers are added as they are
-- loaded; a missing table must not break the function, hence the EXISTS guards.
CREATE OR REPLACE FUNCTION open.facts_at(lon double precision, lat double precision)
RETURNS TABLE (dataset text, attribute text, value text, geom_geojson jsonb, meta_id text, sql_hint text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  p geometry := ST_Transform(ST_SetSRID(ST_MakePoint(lon, lat), 4326), 3763);
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
  RETURN;
END $$;

GRANT EXECUTE ON FUNCTION open.facts_at(double precision, double precision) TO territorio_ro;

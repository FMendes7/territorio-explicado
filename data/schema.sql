-- data/schema.sql — PostGIS schema for Território Explicado (pre-existing data platform)
-- What: creates schema `open`, the provenance table and the point-lookup function used by the agent
--       and by the Zetaris views. Idempotent.
-- Depends on: PostGIS extension; tables loaded by data/etl/load.sh (open.caop_*, open.cos2023,
--       open.icnf_perigosidade, open.apa_perigo_inundacao, open.apa_zonas_inundaveis, open.apa_arpsi,
--       open.apa_marcas_cheia, open.ine_bgri2021).
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
             ('inside the ' || z.pretorno || ' flood zone; max water level ' || coalesce(z.nivel_max::text, '?') || ' m — ' || coalesce(z.local, '?'))::text,
             ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(z.geom, 2), 4326))::jsonb,
             'apa_zonas_inundaveis'::text, 'ST_Intersects(apa_zonas_inundaveis.geom, point)'::text
      FROM open.apa_zonas_inundaveis z WHERE ST_Intersects(z.geom, p) ORDER BY z.pretorno;
  END IF;
  IF to_regclass('open.apa_arpsi') IS NOT NULL THEN
    RETURN QUERY
      SELECT 'apa_arpsi'::text, 'designated_flood_risk_area'::text,
             (coalesce(z.local, '?') || ' (' || coalesce(z.designa, '?') || ', ' || coalesce(z.pretorno, '?') || ')')::text,
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
  RETURN;
END $$;

GRANT EXECUTE ON FUNCTION open.facts_at(double precision, double precision) TO territorio_ro;

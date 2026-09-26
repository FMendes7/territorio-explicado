-- data/views.sql — flat views for federated engines (Zetaris) that may not understand `geometry`
-- What: exposes each layer without the geometry type: WKT, centroid lon/lat, bbox, area. Plus a
--       precomputed point-facts table (plan B) if the federation cannot push ST_* down to PostGIS.
-- Depends on: data/schema.sql and the tables loaded by data/etl/load.sh.
-- Used by: Zetaris data source registration (F2); the agent's zetaris tools query these views.
-- When changing: view names are what the Zetaris semantic layer (USL) is built from; renaming
--       breaks the USL and the agent's discovery step.

CREATE OR REPLACE VIEW open.v_caop_freguesias AS
SELECT dico, freguesia, concelho, distrito,
       ST_X(ST_Transform(ST_Centroid(geom), 4326)) AS lon,
       ST_Y(ST_Transform(ST_Centroid(geom), 4326)) AS lat,
       round((ST_Area(geom) / 10000)::numeric, 2) AS area_ha,
       ST_AsText(ST_Envelope(geom)) AS bbox_wkt
FROM open.caop_freguesias;

-- Plan B (decided by 8 Oct): facts precomputed on a regular grid inside the pilot regions so a
-- federated engine can answer by nearest grid cell with plain SQL. Created only if needed.
-- CREATE TABLE open.grid_facts AS ...

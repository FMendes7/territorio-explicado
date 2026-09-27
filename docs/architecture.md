# Architecture (target)

```
Browser (React + MapLibre, PT/EN)
   │  SSE (steps, evidence, final answer)
   ▼
API — Node 20 / TypeScript / Express
   │
   ├─ Agent loop — bounded steps with explicit carry-over state (Markovian-style):
   │     plan → discover → query → verify → compose. Each step logs {input, tool calls, tokens, ms}.
   ├─ LLM router (OpenAI-compatible client → integrate.api.nvidia.com)
   │     planner/composer: Nemotron 3 Super · extractor/verifier: Nemotron 3.5 Lightning (ids in .env)
   ├─ Tools
   │     geocode(place) ............ Nominatim (1 req/s, cached) → lon/lat + display name
   │     zetaris.*  ................ MCP Streamable HTTP + Bearer: get_schema, run_sql / run_query, get_dq_score
   │     pg.facts_at(lon,lat) ...... direct PostGIS fallback, same evidence contract
   │     ipma.fire_risk(dico) ...... IPMA RCM daily index (live REST)
   │     memory.recall/remember .... H-MEM (mining, retrieval with trace, trust ledger)
   └─ Evidence assembler → {answer, claims[{text, evidence[{dataset, publisher, licence, date, sql, geom_ref}]}], unknowns, confidence}

PostGIS `territorio-db` (dedicated container, schema `open`) — full list and licences in data/sources.md
   national: caop_freguesias · caop_municipios
   3 pilot regions (26 municipalities):
     land cover ... cos2023 · cos_serie (1995 S1 · 2018v4 · 2025v1) + view v_cos_serie
     fire ......... icnf_perigosidade · icnf_areas_ardidas (1975–2025) · ipma_rcm_snapshot (live API in the agent)
     water ........ apa_perigo_inundacao · apa_zonas_inundaveis (T20/T100/T1000) · apa_arpsi · apa_marcas_cheia
     planning ..... dgt_crus (PDM classes, DR 15/2015) · dgt_ren (+ dgt_ren_linhas) · dgt_ran · icnf_areas_protegidas (RNAP + Natura 2000)
     buildings .... dgt_construcoes (LiDAR 2024 footprints)
     people/price . ine_bgri2021 · ine_precos_habitacao (€/m²)
     relief ....... dem_elev · dem_slope · dem_aspect (rasters, 25 m, Copernicus GLO-30 surface model)
   derived: grid_* (ST_Subdivide copies for the grid), pilot_regions / pilot_union
   dataset_meta (provenance) · facts_at() · facts_for() / facts_in() (point or drawn plot) ·
   constraints_grid() (facts per cell, no verdicts) · flat views for federation (data/views.sql)
   stage `qa` of data/etl/load.sh asserts every geometry lies inside its tagged region after each load
```

## Why the answer can "explain why"

1. Every fact comes from `facts_at()` or a governed SQL query: the SQL text, the dataset id and the
   intersected geometry travel with the fact.
2. The composer may only write a claim if it references ≥1 evidence id; the verifier (small model)
   rejects claims without evidence or with evidence that does not support them.
3. Unknowns are first-class: layers not loaded, places outside the pilot regions, geocoding ambiguity.
4. Memory recalls are shown with their trust-ledger origin (which earlier case, when, how it was scored).

## Deployment

- Hosted demo: `territorio.mvp.tugachain.com` (personal server, Docker, public during judging).
- Judges' one-command run: `docker compose up` → app + PostGIS + sample data for one municipality.

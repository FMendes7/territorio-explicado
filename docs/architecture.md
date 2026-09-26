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
   │     planner/composer: Nemotron Super · extractor/verifier: Nemotron Nano
   ├─ Tools
   │     geocode(place) ............ Nominatim (1 req/s, cached) → lon/lat + display name
   │     zetaris.*  ................ MCP Streamable HTTP + Bearer: get_schema, run_sql / run_query, get_dq_score
   │     pg.facts_at(lon,lat) ...... direct PostGIS fallback, same evidence contract
   │     ipma.fire_risk(dico) ...... IPMA RCM daily index (live REST)
   │     memory.recall/remember .... H-MEM (mining, retrieval with trace, trust ledger)
   └─ Evidence assembler → {answer, claims[{text, evidence[{dataset, publisher, licence, date, sql, geom_ref}]}], unknowns, confidence}

PostGIS `territorio-db` (dedicated container, schema `open`)
   caop_freguesias (national) · cos2023 · icnf_perigosidade · apa_cheias · ine_bgri2021 (3 pilot regions)
   dataset_meta (provenance) · facts_at() · flat views for federation
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

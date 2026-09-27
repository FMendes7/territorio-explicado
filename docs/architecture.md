# Architecture (target — built inside the window)

```
Browser (React + MapLibre, PT/EN)
   │  SSE (hand-offs, evidence, final answer)
   ▼
API — Node 20 / TypeScript / Express
   │
   ├─ Agent roles on a shared case state (each role: own prompt, input/output schema, log entries)
   │     Intake ........... intent + place (point, drawn plot, geocoded text); asks when ambiguous
   │     Planner .......... Nemotron 3 Super — relationships that matter for the intent → tasks for the Tracer
   │     Evidence Tracer .. tools below + Nemotron 3.5 Lightning for extraction → evidence items
   │     Rule engine ...... deterministic: relationship rules + intent thresholds (LEGAL / TECHNICAL) → findings
   │     Challenger ....... Nemotron 3.5 Lightning, adversarial prompt → accept / reject / revision request per link
   │     Explainer ........ Nemotron 3 Super → answer from accepted links + explanation graph + unknowns
   │     Memory keeper .... H-MEM → recall before planning (low weight), store after, trust ledger
   │   loop: Planner → Tracer → rules → Challenger ─┬─ accept ───────────▶ Explainer
   │                                                  └─ revision request ─▶ Planner (≤ 3 rounds, then escalate to "unknown")
   ├─ LLM router (OpenAI-compatible client → integrate.api.nvidia.com; ids in .env)
   ├─ Tools (every call has a timeout and a declared fallback — table below)
   │     geocode(place) ............ Nominatim (1 req/s, cached) → lon/lat + display name
   │     zetaris.*  ................ MCP Streamable HTTP + Bearer: get_schema, run_sql / run_query, get_dq_score
   │     pg.facts_for(geojson) ..... direct PostGIS, same evidence contract (also the fallback for zetaris.*)
   │     pg.constraints_grid(...) .. facts per cell around the place (no verdicts in SQL)
   │     ipma.fire_risk(dico) ...... IPMA RCM daily index (live REST)
   │     memory.recall/remember .... H-MEM (mining, retrieval with trace, trust ledger)
   └─ Evidence assembler → {answer, claims[{text, evidence[{dataset, publisher, licence, date, sql, geom_ref}]}],
                            graph, unknowns[{layer, why}], confidence}

PostGIS `territorio-db` (dedicated container, schema `open`) — counts and limits in data/README.md
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

1. Every fact comes from `facts_for()` or a governed SQL query: the SQL text, the dataset id and the intersected
   geometry travel with the fact.
2. The Explainer may only write a claim that references ≥ 1 evidence id **and** was accepted by the Challenger; a
   rejected or unsupported link goes back to the Planner as a revision request, not into the answer.
3. The explanation graph (conclusion ← link ← rule ← evidence ← dataset) carries the Challenger's verdict on each link;
   disagreements between sources are explicit nodes.
4. Unknowns are first-class: layers not loaded or not published for this municipality, places outside the pilot
   regions, geocoding ambiguity, a service that did not answer — each with its reason.
5. Memory recalls are shown with their trust-ledger origin (which earlier case, when, how it was scored).
6. When a LEGAL constraint decides the answer, the Explainer names it and points to a *Pedido de Informação Prévia* at
   the municipality — the agent informs, it does not license.

## Timeouts, retries and fallbacks (targets, measured in evals)

| Service | Timeout | Retries | Fallback (logged with `status: "fallback"`) |
|---|---|---|---|
| NVIDIA — Super | 60 s | 1 (backoff; on 429 wait as told) | Lightning also plans and explains; the answer is marked *degraded* |
| NVIDIA — Lightning | 30 s | 1 | Super takes the Challenger role (slower) |
| Zetaris MCP | 20 s | 1 | `pg.*` directly, same evidence contract; sponsor-fit counts it |
| PostGIS | 10 s per query | 0 | that layer becomes an unknown with the reason |
| IPMA RCM | 8 s | 1 | the dated snapshot in the database, shown with its date |
| Nominatim | 5 s | 0 | ask for a map click or coordinates |
| H-MEM | 5 s | 0 | run without memory, said in the trace |

A run is bounded: at most 3 revision rounds and 20 tool calls, hard cap 120 s; target median ≤ 30 s.

## Logs as evidence

One JSON line per hand-off or tool call in `logs/trace-<run_id>.jsonl`, plus a readable line per step on stdout; never
edited afterwards; secrets masked. Fields as recommended by the HackOS AI Usage Policy and Technical Execution Guide,
plus cost and tool:

Format only — an illustrative line, not a record of a real run:

```json
{"timestamp": "2026-10-16T21:42:00Z", "run_id": "example", "agent_name": "Challenger", "action": "request_revision",
 "input_summary": "link plot-RAN has no evidence item for this municipality",
 "output_summary": "ask the Planner to check the RAN delimitation status",
 "target_agent": "Planner", "model": "nvidia/nemotron-3.5-lightning-30b-a3b", "tool": null,
 "confidence": 0.0, "status": "success", "retry_count": 0, "tokens": 0, "ms": 0}
```

`status` is one of `success`, `needs_revision`, `fallback`, `error`. On stdout, one readable line per step, e.g.
`[INFO] run_id=<id> Challenger → Planner: RAN delimitation not in evidence, revision requested`.

The step trace in the UI is rendered from these lines, so what a judge sees is the run that happened.

## Programmatic entry point (besides the UI)

Judges must be able to run the agent without clicking through a screen (HackOS Technical Execution Guide).

- `POST /run` — in: `{run_id, input: {place | plot (GeoJSON), intent}, options: {sample_mode}}`; out: `{run_id, status,
  output: {answer, claims, graph, unknowns, revisions}, agents: [{name, role}], trace_id, log_file,
  execution_time_seconds}`. On failure a structured error, never a silent crash:
  `{run_id, status: "error", error: {type, message, recoverable}, trace_id, execution_time_seconds}`.
- CLI: `npm run agent -- input_examples/<case>.json` → the same JSON on stdout.
- The API listens on port 8000 and three examples are named `input_examples/example_1.json` … `example_3.json` (plus
  one per golden case), so the organizers' self-test (`curl -X POST http://localhost:8000/run -H "Content-Type:
  application/json" -d @input_examples/example_1.json`) runs verbatim.
- The API binds to `0.0.0.0` inside the container; the UI runs on its own port.
- CPU only: the models are hosted APIs; nothing installs or downloads during a run.

## Sample mode (for reviewers without keys)

The HackOS pre-submission checklist asks that sample mode "still runs real agent logic on cached data, rather than
replaying a saved output", and warns that judges test with their own inputs. So:

- `SAMPLE_MODE=false` (default): the real agent, real model calls.
- `SAMPLE_MODE=true`: no network and no credentials. The database is the sample extract (`data/sample/`: the
  municipality of the main demo plot plus the golden-case areas; target < 50 MB, or a release asset fetched by a script
  if larger). The roles still run and still interact; only the model calls are replaced by deterministic
  implementations of the same contracts:
  - Planner — the relationships listed for the intent in `data/pretensoes.json`;
  - Evidence Tracer — the same SQL tools on the sample extract;
  - rule engine — unchanged (it is deterministic already);
  - Challenger — the structural checks (evidence present and supporting the rule's threshold, blocking layer unknown,
    share without its location, sources that disagree) → the same revision requests and escalations;
  - Explainer — template sentences built from the accepted links, with the same evidence path;
  - Memory keeper — H-MEM's no-model capture (direct summaries).

  Every answer and log line carries `sample_mode: true`. Any point or plot inside the sample works, not only the golden
  cases; outside it the answer is "outside the sample", never a made-up result. Nothing is read from `output_examples/`.

## Deployment

- Hosted demo: `territorio.mvp.tugachain.com` (personal server, Docker, public during judging).
- Judges' run: `docker compose up` (app + PostGIS + sample extract), documented in the README. If cheap, also one image
  with the app and the PostGIS sample, so the organizers' `docker build -t oah-submission .` and
  `docker run --rm -p 8000:8000 --env-file .env oah-submission` run verbatim. Both work with an empty `.env` in
  `SAMPLE_MODE=true`; CPU only.

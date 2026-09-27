# Sponsor technology — where each one fits (skeleton; measured sections filled inside the window)

Scored under "Sponsor tech" (10) and read by each sponsor's panel. Written to be honest: what we use, what we measured,
what we did not use. Every number below comes from `evals/results/` or the JSONL logs of a dated run — no estimate is
written as a result.

## Zetaris — data layer

- **Use:** the agent discovers and queries the territorial data through the Zetaris MCP endpoint
  (`get_schema`, `list_tables`, `run_sql`/`run_query`, `get_dq_score`) instead of hard-coded SQL against
  one database. A semantic layer (USL) `territorio` is built from the PostGIS source with
  `generate_ddl_from_datasource` → `compile_usl` → `deploy_usl`.
- **Why it matters here:** the problem *is* fragmentation; a governed, logged, single access point across
  PostGIS + REST/CSV sources is the natural data plane, and its per-query log doubles as lineage.
- **Open question (answer before 8 Oct):** do PostGIS functions (`ST_*`, `open.facts_for`) push down through `run_sql`?
  If not, plan B: Zetaris serves discovery + the flat views of `data/views.sql`, the spatial functions stay on `pg.*` —
  and this page says so.

| Measure | How | Where logged | Result |
|---|---|---|---|
| Latency per query (p50/p95) | 30 golden cases × `run_sql` | `logs/*.jsonl` (`tool=zetaris.*`, `ms`) | *(window)* |
| Spatial push-down | `SELECT … FROM open.facts_for(…)` via `run_sql` | `docs/lessons.md` | *(F2)* |
| DQ score per layer | `get_dq_score` on each `open.*` table | `evals/results/dq_<date>.json` | *(window)* |
| Share of answers whose evidence came through Zetaris | count per run | eval summary | *(window)* |

- **Limits found:** *(F2 + window)*

## NVIDIA — token layer

- **Use:** two Nemotron models behind one router, one per role: Super is the Planner and the Explainer; Lightning
  extracts structured facts for the Evidence Tracer and is the Challenger that accepts, rejects or sends links back
  for revision. Both via build.nvidia.com
  (OpenAI-compatible API; ids in `docs/lessons.md`).

| Measure | How | Where logged | Result |
|---|---|---|---|
| Task success, routed vs Super-only | same 30 cases, both configurations, sequential | `evals/results/<date>.json` | *(window)* |
| Tokens and latency per case, per model | usage fields of every call | `logs/*.jsonl` | *(window)* |
| Challenger catches | planted unsupported claims rejected / planted; revision rounds that closed a gap | eval summary + `logs/*.jsonl` | *(window)* |
| Rate-limit hits (429) | count per run | `logs/*.jsonl` | *(window)* |

- **Limits found:** rate limits, tool-call formatting quirks, context handling *(window)*.

## Meterless — orchestration layer

- **Use (conditional):** the H-MEM reference implementation (Apache-2.0, copied under `third_party/` with its licence)
  is the Memory keeper role. It stays in this project only if a recall changes the Planner's first plan in a measured
  way; otherwise it is removed from the README and the video rather than shown bolted on. Components:
  `MemoryMiningService` (facts from each answered case), `MemoryRetrievalService` (recall with trace),
  `TrustLedgerService` (append-only audit of where a recalled fact came from). The agent loop follows
  the Markovian pattern: bounded steps, explicit carry-over, no unbounded history.
- **Why it matters here:** "explain why" includes explaining *what the agent remembered and why it trusted it*.
  Recall is low-weight evidence that must be confirmed by a live query (relevance on a small corpus is weak — lessons).

| Measure | How | Where logged | Result |
|---|---|---|---|
| Context tokens per step, with vs without memory | same cases, memory on/off | eval summary | *(window)* |
| Recall precision on repeated/similar cases | 5 paired cases | eval summary | *(window)* |
| Trust-ledger entries shown per answer | count | UI + logs | *(window)* |

- **Not used:** Relay, Gaia, Swarms (proprietary binaries), Scout Intent (spec only).

## What we built on, but is not sponsor technology

PostGIS, MapLibre, OpenStreetMap Nominatim, and open data from DGT, ICNF, APA, INE, IPMA and Copernicus — listed with
licences in `data/sources.md`.

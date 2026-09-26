# Sponsor technology — where each one fits (draft, finalised inside the window)

Scored under "Sponsor tech" (10) and read by each sponsor's panel. Written to be honest: what we use,
what we measured, what we did not use.

## Zetaris — data layer

- **Use:** the agent discovers and queries the territorial data through the Zetaris MCP endpoint
  (`get_schema`, `list_tables`, `run_sql`/`run_query`, `get_dq_score`) instead of hard-coded SQL against
  one database. A semantic layer (USL) `territorio` is built from the PostGIS source with
  `generate_ddl_from_datasource` → `compile_usl` → `deploy_usl`.
- **Why it matters here:** the problem *is* fragmentation; a governed, logged, single access point across
  PostGIS + REST/CSV sources is the natural data plane, and its per-query log doubles as lineage.
- **Measured (to fill):** latency per query; whether spatial predicates push down; DQ score of each layer.
- **Limits found (to fill):** …

## NVIDIA — token layer

- **Use:** two Nemotron models behind one router: the large one plans and composes, the small one
  extracts structured facts and verifies claims against evidence. Both via build.nvidia.com
  (OpenAI-compatible API).
- **Measured (to fill):** tokens, latency and cost per case for (a) large-only, (b) routed; success rate of each.
- **Limits found (to fill):** rate limits, tool-call formatting quirks, context handling.

## Meterless — orchestration layer

- **Use:** the H-MEM reference implementation (Apache-2.0, vendored) provides case memory:
  `MemoryMiningService` (facts from each answered case), `MemoryRetrievalService` (recall with trace),
  `TrustLedgerService` (append-only audit of where a recalled fact came from). The agent loop follows
  the Markovian pattern: bounded steps, explicit carry-over, no unbounded history.
- **Why it matters here:** "explain why" includes explaining *what the agent remembered and why it trusted it*.
- **Not used:** Relay, Gaia, Swarms (proprietary binaries), Scout Intent (spec only).
- **Measured (to fill):** context tokens per step with vs without memory; recall precision on repeated cases.

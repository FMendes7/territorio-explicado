# Pre-existing components (declaration)

The Open Agent Hackathon 2026 rules (section 4 and 5) say that work committed before the build window
(15 Oct 2026 00:00 UTC) is not eligible **except for clearly declared pre-existing components**, and
that pre-existing product code must be declared in the submission form. This file is that declaration,
kept current until submission.

## Declared as pre-existing (built before 15 Oct 2026)

| Component | What it is | Why it is not "the agent" |
|---|---|---|
| PostGIS data platform (`data/schema.sql`, `data/views.sql`, `data/etl/*`) | Open datasets (DGT: CAOP, COS2023, CRUS/PDM classes · ICNF: fire hazard, burned areas 1975–2025, RNAP + Natura 2000 · APA: flood layers · INE: BGRI 2021, median €/m² · IPMA: dated fire-risk snapshot) downloaded, clipped to three pilot regions and loaded into PostGIS, with a `dataset_meta` provenance table and SQL lookup functions: `open.facts_at()` (point), `open.facts_for()` / `open.facts_in()` (point or drawn plot, share of the plot per value), `open.constraints_grid()` (facts per cell around a place — no verdicts). Also COS 1995/2018/2025 for land-cover trajectories and a Copernicus GLO-30 elevation/slope raster | Data preparation. The agent could run against any other database with the same schema |
| Accounts and connections | NVIDIA build API key, Zetaris Cloud cluster with the PostGIS source registered and a semantic layer built, Meterless H-MEM reference vendored | Configuration of sponsor technology, done so the window is spent on the agent |
| Golden evaluation cases (`evals/cases/*.jsonl`) | Places or drawn plots, the person's intent, questions and expected facts, validated by hand | Test data, not code |
| Intent profiles (`data/pretensoes.json`) | Per intent (build, farm, forestry, solar, buy, risks, describe): which evidence matters, its role, and thresholds typed LEGAL (cited, human-validated) or TECHNICAL | Domain knowledge as data; the rule engine that applies it is written inside the window |
| Documentation (`docs/*.md`, `README.md`) | Architecture, decisions, lessons from a private rehearsal | Text |

## Explicitly NOT pre-existing (written inside the window)

Agent loop, tool definitions, MCP client wiring, LLM router, evidence schema, API, web UI, evaluation
runner, logs, Docker packaging, demo video.

## Rehearsal

Before the window a **private, throwaway prototype** was built to learn the sponsor stack and to find
failure modes early. **No file from it is copied into this repository.** Whatever was learned is written
down in `docs/lessons.md`. If, during the window, any file is copied verbatim from the rehearsal, it will
be listed here with its path.

_Last updated: 2026-09-26 (Tier-1 datasets; plot/grid lookup functions, COS series, relief, intent profiles)._

# Pre-existing components (declaration)

The Open Agent Hackathon 2026 rules (section 4 and 5) say that work committed before the build window
(15 Oct 2026 00:00 UTC) is not eligible **except for clearly declared pre-existing components**, and
that pre-existing product code must be declared in the submission form. This file is that declaration,
kept current until submission.

**Checked 2026-09-27.** The Official Rules on the event page (the binding text) say: *"Work committed before the window
opens is not eligible, except for clearly declared pre-existing components"* (§4) and *"Pre-existing product code must be
declared in the submission form"* (§5). The FAQ inside HackOS is stricter — it allows pre-existing code only in the
Tinkerer Track — and says the Official Rules prevail; the "Official Rules" document inside HackOS is marked *working
draft* and lists other tracks and partners. Because the data platform below includes code (ETL scripts and SQL lookup
functions), the organizers were asked on 27 September 2026 through HackOS Support (questions in
`docs/discord-perguntas.md`; no answer yet); their answer will be recorded here. If declared pre-existing code is not accepted in the main tracks, the project is entered in the
Tinkerer Track instead. Either way, the last commit before the window is tagged `pre-window`: everything after that
tag is window work.

## Declared as pre-existing (built before 15 Oct 2026)

| Component | What it is | Why it is not "the agent" |
|---|---|---|
| PostGIS data platform (`data/schema.sql`, `data/views.sql`, `data/etl/*`) | Open datasets (DGT: CAOP, COS2023, CRUS/PDM classes, REN and RAN delimitations, LiDAR 2024 building footprints · ICNF: fire hazard, burned areas 1975–2025, RNAP + Natura 2000 · APA: flood layers · INE: BGRI 2021, median €/m² · IPMA: dated fire-risk snapshot) downloaded, clipped to three pilot regions (26 municipalities) and loaded into PostGIS, with a `dataset_meta` provenance table, a spatial QA stage and SQL lookup functions: `open.facts_at()` (point), `open.facts_for()` / `open.facts_in()` (point or drawn plot, share of the plot per value), `open.constraints_grid()` (facts per cell around a place — no verdicts). Also COS 1995/2018/2025 for land-cover trajectories and relief rasters (elevation/slope/aspect at 10 m from the DGT LiDAR 2024 terrain model, downloaded with `data/etl/download_mdt.sh`; Copernicus GLO-30 at 25 m as the fallback), with `open.relief_at()` naming the source of each value | Data preparation. The agent could run against any other database with the same schema |
| Accounts and connections | NVIDIA build API key (tested 2026-09-27). Zetaris Cloud account on the free Hobby tier (created 2026-09-27; no compute yet). **Planned before the window, not done yet (2026-09-27):** a Zetaris cluster with the PostGIS source registered and a semantic layer. The Meterless World Model reference was read and its tests run in a scratch directory outside this repository (2026-09-27, `docs/world-model.md`); nothing is copied before the window — the copy under `third_party/` with its licence is window work, as is any H-MEM code. This row is updated when each is done; anything not done by 15 Oct becomes window work | Configuration of sponsor technology, done so the window is spent on the agent |
| Golden evaluation cases (`evals/cases/*.jsonl`) | Places or drawn plots, the person's intent, questions and expected facts, validated by hand | Test data, not code |
| Intent profiles (`data/pretensoes.json`) | Per intent (build, farm, forestry, solar, buy, risks, describe): which evidence matters, its role, and thresholds typed LEGAL (cited, human-validated) or TECHNICAL | Domain knowledge as data; the rule engine that applies it is written inside the window |
| Documentation (`docs/*.md`, `README.md`) | Architecture, decisions, lessons from a private rehearsal | Text |

## Explicitly NOT pre-existing (written inside the window)

Agent roles and their revision loop (Planner, Evidence Tracer, Challenger, Explainer, Memory keeper), the World Model
store (shared case state and its append log), tool definitions
with timeouts and fallbacks, MCP client wiring, LLM router, evidence schema and explanation graph, API, web UI, sample
mode (the sample extract and the deterministic stand-ins for the model calls), evaluation runner, structured logs, input/output examples,
Docker packaging, demo video.

## Rehearsal

Before the window a **private, throwaway prototype** was built to learn the sponsor stack and to find
failure modes early. **No file from it is copied into this repository.** Whatever was learned is written
down in `docs/lessons.md`. If, during the window, any file is copied verbatim from the rehearsal, it will
be listed here with its path.

_Last updated: 2026-09-27 (REN/RAN, LiDAR building footprints, aspect, Mortágua PDM; multi-region split and spatial QA in the loader; intent profiles updated) and 2026-09-27 evening (accounts row corrected — Zetaris and H-MEM are planned, not done; open point on pre-existing code; `pre-window` tag) and 2026-09-27, 19:00 (track selected with a decision rule; questions sent to the organizers; World Model integration notes, no code; relief from the DGT LiDAR 2024 terrain model at 10 m, Copernicus as fallback)._

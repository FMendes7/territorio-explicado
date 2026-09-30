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
| PostGIS data platform (`data/schema.sql`, `data/views.sql`, `data/etl/*`) | Open datasets (DGT: CAOP, COS2023, CRUS/PDM classes, REN and RAN delimitations, LiDAR 2024 building footprints · ICNF: fire hazard, burned areas 1975–2025, RNAP + Natura 2000 · APA: flood layers · INE: BGRI 2021, median €/m² · IPMA: dated fire-risk snapshot) downloaded, clipped to four regions (55 municipalities: Região de Coimbra, Cávado, Lisboa, and since 2026-09-30 the other 29 municipalities of the Lisbon study area for site selection) and loaded into PostGIS, with a `dataset_meta` provenance table, a spatial QA stage and SQL lookup functions: `open.facts_at()` (point), `open.facts_for()` / `open.facts_in()` (point or drawn plot, share of the plot per value), `open.constraints_grid()` (facts per cell around a place — no verdicts). Each fact also carries its status as data (2026-09-28): `level` (inside / conditions / outside a loaded layer / not available / information), a one-line PT and EN reading and a `caveat` code for what the row does not know — a classification of the fact, not a verdict on the intent. Also COS 1995/2018/2025 for land-cover trajectories and relief rasters (elevation/slope/aspect at 10 m from the DGT LiDAR 2024 terrain model, downloaded with `data/etl/download_mdt.sh`; Copernicus GLO-30 at 25 m as the fallback), with `open.relief_at()` naming the source of each value | Data preparation. The agent could run against any other database with the same schema |
| Accounts and connections | NVIDIA build API key (tested 2026-09-27). Zetaris Cloud account on the free Hobby tier (created 2026-09-27; no compute yet). **Planned before the window, not done yet (2026-09-27):** a Zetaris cluster with the PostGIS source registered and a semantic layer. The Meterless World Model reference was read and its tests run in a scratch directory outside this repository (2026-09-27, `docs/world-model.md`); nothing is copied before the window — the copy under `third_party/` with its licence is window work, as is any H-MEM code. This row is updated when each is done; anything not done by 15 Oct becomes window work | Configuration of sponsor technology, done so the window is spent on the agent |
| Golden evaluation cases (`evals/cases/*.jsonl`) | Places or drawn plots, the person's intent, questions and expected facts, validated by hand. Since 2026-09-30 also `site_golden.jsonl`: site-selection requests for the Lisbon study area (airport benchmark against the CTI, probe points per type with the exclusion / procedure / favourable zoning / unknown expected there, "cannot assess", out-of-area and coverage cases), with the layer facts at each probe measured on the loaded data | Test data, not code |
| Intent profiles (`data/pretensoes.json`) | Per intent (build, farm, forestry, solar, buy, risks, describe): which evidence matters, its role, and thresholds typed LEGAL (cited, human-validated) or TECHNICAL | Domain knowledge as data; the rule engine that applies it is written inside the window |
| Site profiles (`data/site_profiles.json`, 2026-09-30) | For the site-selection mode: a catalogue of 15 requirement primitives (area/shape, slope, physical exclusion, measured LEGAL regimes, favourable zoning, distance to networks, travel time, population, existing services, hazards, climate, grid capacity, noise, geology, water/telecoms), each bound to layers with their availability tier; shared rules and 7 type profiles (airport, large PV, logistics, school/health centre, housing, high-speed rail corridor, data centre as "cannot assess"). Every threshold typed LEGAL (diploma + article + how far it was verified) or TECHNICAL (rule of thumb or study value), all `proposta` until the author validates them | Domain knowledge as data; the screening, footprint fit, ranking and explanation that apply it are written inside the window |
| Documentation (`docs/*.md`, `README.md`) | Architecture, decisions, lessons from a private rehearsal; the site-selection design note (`docs/site-selection.md`, 2026-09-30 — design only, nothing built); the open-data inventory for the Lisbon study area (`data/inventory.md`, 2026-09-30 — metadata only) | Text |

## Explicitly NOT pre-existing (written inside the window)

Agent roles and their revision loop (Planner, Evidence Tracer, Challenger, Explainer, Memory keeper), the World Model
store (shared case state and its append log), tool definitions
with timeouts and fallbacks, MCP client wiring, LLM router, evidence schema and explanation graph, API, web UI, sample
mode (the sample extract and the deterministic stand-ins for the model calls), evaluation runner, structured logs, input/output examples,
Docker packaging, demo video, and the site-selection mode of `docs/site-selection.md` (screening grid, footprint fit, zone ranking, benchmark checks).

## Rehearsal

Before the window a **private, throwaway prototype** was built to learn the sponsor stack and to find
failure modes early. **No file from it is copied into this repository.** Whatever was learned is written
down in `docs/lessons.md`. The same prototype is used to test the interface layout of `docs/ux.md` with real users
before the window; the window's UI is written from that document, not from the prototype's code. If, during the
window, any file is copied verbatim from the rehearsal, it will be listed here with its path. On 2026-09-30 a **static mock-up of the new main screen** ("where to build?") was added to the rehearsal to test the
layout with a reviewer: it reads `data/site_profiles.json` for the real parts (types, requirements, coverage, LEGAL regimes)
and shows three fixed example positions and empty pros/cons boxes, labelled as a mock-up; it computes no candidate.

_Last updated: 2026-09-27 (REN/RAN, LiDAR building footprints, aspect, Mortágua PDM; multi-region split and spatial QA in the loader; intent profiles updated) and 2026-09-27 evening (accounts row corrected — Zetaris and H-MEM are planned, not done; open point on pre-existing code; `pre-window` tag) and 2026-09-27, 19:00 (track selected with a decision rule; questions sent to the organizers; World Model integration notes, no code; relief from the DGT LiDAR 2024 terrain model at 10 m, Copernicus as fallback) and 2026-09-30 (site-selection design note; no code). and 2026-09-30, later (site profiles as data: `data/site_profiles.json`, no code) and 2026-09-30, afternoon (Tier 1 + LiDAR relief for the Lisbon study area — 4 regions; site-selection golden cases; loader fixes: ST_Covers trim and QA, tiled Int16 rasters, per-municipality SRUP fallback and the CCDR Alentejo REN service)._

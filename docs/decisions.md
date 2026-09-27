# Decision log

One entry per significant choice: **what** and **why**. Append-only; reversals get a new entry.

## 2026-09-26 — Enter solo, option A, track 3

Solo entry (the 144-hour window is one person's attention → small and deep). Project: an agent that
answers territorial questions in Portugal with evidence from fragmented open geodata. Primary track:
**The Agent That Can Explain Why**; tracks 1 and 2 fit without extra work but are not scored twice.
Rationale: the author's GIS/PostGIS background is the differentiator, the impact story is verifiable,
and all three sponsor layers fit naturally (Zetaris federates PostGIS + REST; Nemotron routes reasoning;
H-MEM gives memory with an audit trail).

## 2026-09-26 — Three pilot regions, not national

CIM Região de Coimbra (19 municipalities), CIM do Cávado (6) and the municipality of Lisbon.
Administrative boundaries (CAOP) national. Why: the hosting server has ~18 GB free with a disk alert at
85 %, and full national COS2023 + hazard + census would blow it; three regions keep the database ≤ 2.5 GB
and cover places the author can validate by hand (Coimbra, Esposende) plus one the jury recognises (Lisbon).

## 2026-09-26 — Nemotron-first

Reasoning via NVIDIA build (OpenAI-compatible): a large Nemotron model plans, a small one extracts and
verifies. Zero cost, complete "token layer" story, cost/latency measured in evals. The client abstracts
the provider so another model can be A/B-tested later. Local inference was ruled out: the only GPU
available has 2 GB.

## 2026-09-26 — Zetaris via Cloud Hobby (BYOC on AWS) + own MCP fallback

Zetaris Hobby is free but runs in the participant's own AWS account; the node is started only during
tests and a budget alert is set. The PostGIS source is exposed to the Zetaris node only (dedicated
container, IP allow-list, TLS, read-only role). If federation cannot push spatial functions down, plan B
is flat views + a precomputed grid-facts table (decision deadline 8 Oct). If Zetaris fails entirely, a
tiny MCP server over the same database keeps the architecture intact (losing only the sponsor points).

## 2026-09-26 — Strict pre-window / window separation

Everything built before 15 Oct is data, accounts, evaluation cases and docs, listed in `PRE-EXISTING.md`.
A private rehearsal prototype exists only to learn; nothing is copied from it. Why: rule 4 ("judged on
new work built during the hackathon"); a clean line is worth more than a head start.

## 2026-09-26 — TypeScript end to end

Node 20 + Express API, MCP TypeScript SDK client, Meterless H-MEM reference (TypeScript, zero deps)
vendored, React + MapLibre UI. Why: fewest moving parts across the sponsor stack; PostGIS does the
spatial work, the app only orchestrates.

## 2026-09-26 — Data platform validated locally before touching the server

The full ETL ran against a throwaway PostGIS container on the laptop (same image as the server,
`postgis/postgis:16-3.4`). Result for the three pilot regions (after dedupe and boundary trim): COS2023 65 683 polygons, fire hazard
124 327 polygons (Cávado 35 818 · Coimbra 87 442 · Lisboa 1 067), INE BGRI 21 482 subsections, CAOP national
3 049 freguesias, APA flood areas 5 polygons; ~570 MB on disk with update bloat, less after dump/restore. Well under the 2.5 GB budget → the server copy will be a
`pg_dump` of schema `open` restored into `territorio-db`, not a re-run of the ETL over the VPN.
All 19 golden cases return facts from every loaded layer (`evals/cases/golden_facts_2026-09-26.txt`,
to be checked by hand); the two "outside" cases behave as designed (Porto: CAOP only; Madrid: nothing).

Decisions taken while loading (each one cost time; see `docs/lessons.md`):
- read big GeoPackages/shapefiles **extracted**, never through `/vsizip/`; build `.qix` first;
- **bbox filter + PostGIS trim** instead of `-clipsrc` (clipping produced GeometryCollections → lost rows);
  features stay whole and get a `region` tag;
- `-nlt CONVERT_TO_LINEAR` because INE stores some MultiSurface geometries;
- fire hazard from the official SNIT zip (WFS broken), `gridcode` 0–5 mapped to labels;
- `facts_at()` casts every value to `text` (RETURN QUERY is strict about varchar vs text);
- dedupe by geometry hash (a feature whose bbox touches two region bboxes is loaded twice) and trim only
  the features that touch the pilot boundary — a naive bbox self-join for dedupe ran 30 min on COS.

## 2026-09-26 — Tier-1 datasets loaded; CRUS (all pilot municipalities) instead of a Lisbon-only PDM layer

Added to the platform before the window (data only): ICNF burned areas 1975–2025, ICNF protected areas (RNAP +
Natura 2000 ZEC/ZPE), DGT CRUS (PDM land-use classes), INE median €/m² (12 months, parish + municipality) and a
dated IPMA fire-risk snapshot. Choices:
- **CRUS instead of "PDM Lisboa — Planta de Qualificação"**: the dados.gov.pt record we had noted was Cascais's
  and Lisbon publishes no open vector PDM we could reach. DGT's CRUS is the same information (classification and
  qualification from each PDM's ordinance plan, DR 15/2015 classes, original designation kept) for **25 of the 26**
  pilot municipalities (Mortágua's WFS fails server-side), from one official source → one table `open.dgt_crus`
  covering all three regions, so "can I build here?" gets a PDM reading almost everywhere, not only in Lisbon.
  Six PDMs are not re-coded to DR 15/2015 (only their original designation; `esquema` says so, no class is
  inferred). The agent still says the PDM regulation and the constraint maps were not consulted (failure mode 12).
- **INE prices joined through BGRI 2021**, not CAOP 2025: parish codes in the price statistics are the 2013 map
  (failure mode 10). Both the parish and the municipality row are returned, labelled by level.
- **IPMA stays live**: the agent reads `api.ipma.pt` at question time; `open.ipma_rcm_snapshot` only keeps dated
  forecasts (today + 2 days per run) as a fallback and as history for evals.
- **ICNF from its own GeoServer WFS**, not from the DGT SRUP copies (the DGT WFS failed for the fire-hazard map).

Result (local DB, 2026-09-26): burned areas 4 917 polygons, protected areas 25, CRUS 20 333, INE prices 166 rows
(26 municipalities + 140 parishes, 55 with a value), IPMA snapshot 78 rows (26 × 3 days); 0 geometry duplicates;
database 691 MB (390 MB when restored from `pg_dump -Fc -n open`, i.e. without update bloat). The server copy will
be that dump — the restore procedure was rehearsed locally with identical row counts in all 17 tables.

## 2026-09-26 — From answers to decisions: point or plot, intent, alternatives, explanation graph, time, relief

After a review of "is this too simple?": a chatbot over a database is what many entries will show; what a generic agent
cannot do is spatial reasoning with consequences. So the demo shows a **drawn plot** answered in shares, the person's
**intent** (pretensão) shaping the analysis, a map of **where nearby the blockers disappear**, and a navigable
**explanation graph** with an adversarial verifier. Data side done now (declared pre-existing): `facts_for()` accepts a
point or a polygon (one entry point; `facts_at()` unchanged for compatibility), `constraints_grid()` returns facts per
cell and **no verdicts**, `data/pretensoes.json` types every threshold LEGAL or TECHNICAL, COS 1995/2018/2025 for
trajectories, and relief from Copernicus GLO-30 (open, global, but a surface model) until the DGT LiDAR 2024 terrain
model can be downloaded with an account. Everything that decides — rules, verdicts, graph, verifier, UI — is written
inside the window.


## 2026-09-27 — Spatial QA, one copy per region, REN/RAN, buildings, aspect

- **A load is not done until the space is checked.** Stage `qa` asserts that every trimmed geometry lies inside its
  tagged region (1 m tolerance) for every vector layer, and coverage is compared per region and per COS edition after
  each load. It exposed two defects row counts could not: features spanning several regions carried one region tag
  (fixed by splitting them — one copy per region), and multipolygon islands wholly outside a region were never trimmed
  (fixed by trimming every feature not covered by its region). The first explanation offered for the first defect
  (a GEOS bug) was wrong and was retracted after decomposing the geometry — kept in `docs/lessons.md` as a lesson.
- **REN and RAN are loaded** (DGT SNIT SRUP WFS, CC BY) instead of being declared missing: the DGT GeoMedia servers
  work with WFS 1.1.0 and an `EPSG:3763` bbox; the 2.0.0 URN form fails server-side. Only each pilot municipality's own
  delimitation is kept; the functions answer *inside / excluded / outside (diploma) / not available — not consulted*,
  and `constraints_grid` returns NULL, never `false`, where a delimitation is missing (failure mode 21).
- **Buildings from the DGT LiDAR 2024 footprint map** (open, national, footprints only) instead of OSM: official,
  dated, one source for the three regions; heights would need the LiDAR MDS/MDT (DGT account).
- **Aspect** from the same Copernicus surface model as slope, labelled as such; replaced by the LiDAR MDT when the
  account exists.
- **Rasters load client-side** (`\lo_import` → `ST_FromGDALRaster` → `ST_Tile`) because the PostGIS image has no
  `raster2pgsql`; values checked against `gdallocationinfo`.

Result (local DB, 2026-09-27): stage `qa` bad = 0 in all 13 checked tables (before: 32 features in 6 layers, 213 km²
outside their tag); every COS edition now covers exactly each region (Cávado 1 245.8 · Coimbra 4 335.6 · Lisboa
100.1 km²) — before, 1995 Lisbon read 37 km² and 2018/2025 Lisbon 92 km² (the road network was tagged Coimbra); CRUS
20 812 polygons in 26/26 municipalities; REN 45 features in 25/26 (none published for Condeixa-a-Nova) + watercourse
lines in 12; RAN 25/26 (none for Lisboa); 457 032 building footprints; relief 3 × 1 088 raster tiles. `constraints_grid`
on 349 cells in 0.39–0.49 s with the new columns; 31 golden cases (7 plots) filled in 11 s. Dump `pg_dump -Fc -n open`
826.6 MB (137 s); restore into a scratch database with the §11.1 flags in 51 s, identical row counts in 37 tables,
every table owned by `territorio_rw`, 1 361 MB restored (the working copy is 1 765 MB with update bloat).

## 2026-09-27 — HackOS participant resources are binding: roles that revise, sample mode, honest claims, conditional track

The HackOS resource library (Welcome Guide, Participant Journey Map, APPROACH guide, Hackathon Overview, Event
Calendar, FAQ, AI Usage Policy) was read on 2026-09-27. Where it differs from the event page the Official Rules prevail,
but it states how judges read a submission. Changes, all in documentation (no code before 15 Oct):

- **Agents that challenge and revise, not a pipeline.** Judges discount "Agent A → B → C" chains and single agents
  presented as agent systems; the AI Usage Policy treats presenting a fixed chain as something else as
  misrepresentation. `docs/reasoning.md` §1 now defines roles (Intake, Planner, Evidence Tracer, rule engine,
  Challenger, Explainer, Memory keeper) on a shared case state, a revision loop (≤ 3 rounds) and escalation of open
  gaps to explicit unknowns. The explanation graph moves to days 1–2: it is the core of track 3.
- **One user, one decision.** Someone about to buy or use a plot; what constrains it for their intent. When a LEGAL
  constraint decides, the answer points to a *Pedido de Informação Prévia* at the municipality.
- **Reproducible for reviewers without keys.** Default mode runs the real agent; `SAMPLE_MODE=true` replays recorded real
  runs on a sample extract, labelled as replays. Timeouts and fallbacks per external service (`docs/architecture.md`).
- **Logs are evidence.** Hand-offs logged with the policy's fields (`agent_name`, `action`, `target_agent`, `status`,
  `retry_count`, …); logs are never edited.
- **Claims match reality.** `PRE-EXISTING.md` listed the Zetaris cluster and the H-MEM copy as done; neither exists yet —
  corrected to "planned". H-MEM stays only if it changes what the Planner does; otherwise it leaves the sponsor claims
  rather than being bolted on. It goes under `third_party/`, because `vendor/` is git-ignored.
- **Track is conditional and locks early.** The FAQ allows pre-existing code only in the Tinkerer Track, while Official
  Rules 4–5 allow declared pre-existing components; the data platform includes code (ETL, SQL functions). To be
  clarified with the organizers (`docs/discord-perguntas.md`); if declared components are not accepted in the main
  tracks, the entry moves to the Tinkerer Track. The FAQ locks the track at the end of 15 Oct. The last pre-window
  commit is tagged `pre-window`.
- **Binding text checked on the event page (2026-09-27):** §3 "you may change track any time before the submission
  deadline"; §4 "work committed before the window opens is not eligible, except for clearly declared pre-existing
  components"; §5 "pre-existing product code must be declared in the submission form"; the bonus of up to 30 points is
  still listed; the Tinkerer Track names NVIDIA and Zetaris; Neo4j is not mentioned. The "Official Rules" document inside
  HackOS is a *working draft* with other tracks (Fragmented, Autonomous Intelligence, Persistent Memory, Real-World
  Industry) and partners (Zetaris, Neo4j, Meterless), as are the AI Usage Policy and the Technical Execution Guide.
  Plan on the stricter reading where they differ (track final by the end of 15 Oct) and ask the organizers which set is
  current.
- **Technical Execution Guide:** a programmatic entry point besides the UI (`POST /run`, JSON in and out, structured
  errors), logs to stdout and `logs/trace-<run_id>.jsonl`, CPU only, at least three sample inputs and outputs, timeouts
  of 10–30 s for external APIs and 30–90 s for models, bounded loops, a sample mode with no network.

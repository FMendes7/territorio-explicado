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
- **Reproducible for reviewers without keys.** Default mode runs the real agent; `SAMPLE_MODE=true` runs the same roles
  on a sample extract with deterministic stand-ins for the model calls (corrected the same evening — a replay of
  recorded runs was the first idea; the HackOS checklist rules it out). Timeouts and fallbacks per external service.
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

## 2026-09-27 (evening) — Second batch of HackOS documents: sample mode corrected, self-test verbatim, two document sets

Read: Disqualification (pre-submission) Checklist, Team Formation Rules, Technical Execution Guide, Channel Directory,
Escalation Path, the Meterless agent-engine guides (index, H-MEM, Markovian, World Model), the onboarding deck and a
learning-session deck.

- **Sample mode runs real logic.** The checklist: sample mode "still runs real agent logic on cached data, rather than
  replaying a saved output", and judges test with their own inputs. `SAMPLE_MODE=true` now runs the same roles on the
  sample extract with deterministic stand-ins for the model calls (architecture.md).
- **The organizers' self-test must run verbatim:** API on port 8000, `input_examples/example_1..3.json` with matching
  outputs, `docker build`/`docker run` or a documented `docker compose up`, and a run with no `.env`.
- **Logs:** `status` includes `needs_revision`; a readable line per step on stdout.
- **Challenger rubric and loop spec:** accuracy · appropriateness · actionability (0–3 each, < 7/9 → one fix), and the
  eight-line loop spec from the learning session (`docs/reasoning.md` §1.2).
- **Two sets of documents disagree.** The event page (binding) and six participant guides list the tracks Connected
  Agent Context / Autonomous Agent / The Agent That Can Explain Why / Reasoning Architecture + Tinkerer, with NVIDIA.
  The onboarding deck, the draft rules, the channel directory, the technical guide and the Meterless guides list
  Fragmented / Autonomous Intelligence / Persistent Memory Agents / Real-World Industry Agents, with Zetaris, Neo4j and
  Meterless, and placeholders ("TBA", "to be confirmed"); two of them refer to an earlier "G42" agentathon. Which set
  is current is asked of the organizers. If the second set is current, the closest home for this project is
  Real-World Industry Agents.

## 2026-09-27 — Meterless World Model as the shared case state

The roles share one world model per run (Meterless World Model agent engine): the point or plot, the features it
touches, datasets, diplomas, the intent's rules and the evidence as a typed graph with provenance, the Challenger's
verdict on each link, validity intervals for the time series, and an append-only log (`logs/world-<run_id>.jsonl`)
from which the canonical view is rebuilt. The explanation graph is a query over it.

Why: track 3 asks for "relationships and evidence to produce explainable conclusions" — this makes them the state the
agents work on, not a picture drawn at the end; it gives the Meterless partner a load-bearing role even if H-MEM (whose
value shows only across sessions) is cut; and the append log is the evidence judges ask for. Substrate: in-process +
JSONL during a run, PostgreSQL schema `agent` (own role, never `open`) across runs; a Neo4j adapter only if the
organizers confirm Neo4j as a partner. Written inside the window (`PRE-EXISTING.md`).

## 2026-09-27 (19:00) — Track 3 selected, with a decision rule; World Model reference read

**Track: 3 — The Agent That Can Explain Why.** Evidence:

- The binding event page lists it and allows "clearly declared pre-existing components" (§4), with pre-existing product
  code declared in the submission (§5); this project's base is declared in `PRE-EXISTING.md`.
- Its text — "relationships and evidence to produce explainable conclusions" — scores what this project is built
  around: evidence on every claim, the Challenger's verdict on every link, the explanation graph, explicit unknowns.
- Tinkerer Track: judged only on the work done in the window and requires NVIDIA or Zetaris — a clean fallback, since
  the whole agent is window work; how it is judged against the main tracks is unknown (question 2).
- Real-World Industry Agents appears only in the draft document set, not on the event page — it matters only if HackOS
  turns out to use that set (question 5).
- Track 1 (Connected Agent Context) stays weaker here: the cross-source discovery was done before the window (the data
  platform). Revisited on Mon 12 Oct only if Zetaris joins live sources at query time.

Decision rule, applied when the answers arrive; the track is final by the end of Thu 15 Oct (UTC):

| Organizers' answer | Track |
|---|---|
| Declared pre-existing components are accepted in the main tracks | 3, confirmed |
| Pre-existing code only in the Tinkerer Track | Tinkerer |
| The HackOS track list is the draft set (no "Explain Why") | Real-World Industry Agents, after re-running the comparison |
| No answer by the 14 Oct onboarding | ask in its live Q&A; still none by the end of 15 Oct → 3, on the binding event-page text (the HackOS FAQ itself defers to the Official Rules), with `PRE-EXISTING.md` and the `pre-window` tag as the record |

The seven questions went through HackOS Support on 27 Sep (`docs/discord-perguntas.md` §1); no answer yet.

**World Model reference read and run, outside this repository** (`docs/world-model.md`): Apache-2.0, TypeScript, no
runtime dependencies, conformance 8/8 on the laptop. Two findings change the design: a new edge with the same
`(from, type, context)` closes the previous one, so multi-valued links point feature → place; and name-keyed entities
are fuzzy-merged, so every entity gets an external key. Its file storage is not an append log, so the log is our own
JSONL sink on the event stream. Nothing is copied before the window.

## 2026-09-27 — Relief from the DGT LiDAR 2024 terrain model at 10 m; Copernicus only as the fallback

- **Terrain, not surface.** The DGT LiDAR 2024 Modelo Digital do Terreno (2 m, buildings and vegetation removed) is
  now the primary source of elevation, slope and aspect; the Copernicus GLO-30 surface model stays loaded and answers
  only where the MDT has no value. Every relief fact names its source (`open.relief_at`); a plot uses one source for
  all three facts; `constraints_grid` says which one answered per cell (`relief_source`, failure mode 22).
- **10 m in the database, 2 m on the laptop.** At 2 m the 26 municipalities (5 680 km²) are ≈ 8.5 GB of rasters —
  over the 2.5 GB server budget. The 2 m tiles are averaged to 10 m and slope/aspect are computed on the 10 m model:
  the general slope of the ground that planning and farming rules talk about, not the micro-relief of walls and
  terraces. Options weighed with Fernando: 10 m (chosen) · 5 m slope + 10 m elevation/aspect (≈ 2.1 GB on the server,
  little headroom) · 10 m plus the 2 m GeoTIFFs on the server disk (76 % → ≈ 85 %).
- **New tables, not a replacement.** `dem_mdt_*` sit next to `dem_*`, so the 27 Sep dump stays valid and the server
  got the three tables and the new functions incrementally (nothing dropped).
- **The download is the operator's.** The data centre needs a DGT account (Keycloak login); `data/etl/download_mdt.sh`
  runs in Fernando's terminal and reads the password from the vault through stdin — the agent never sees it.

Result (2026-09-27): 5 748 of 6 224 MDT tiles downloaded (6.4 GB, sha256 manifest); the other 476 — whole blocks in
Cávado, flight 07-2025 — answer HTTP 404 on every retry (not published yet), so coverage is Região de Coimbra 100 %,
Lisboa 100 %, Cávado 66.5 %. Three 10 m rasters × 5 778 tiles = 218 MB; server database 1 364 → 1 574 MB; row counts
identical in 40 tables; `constraints_grid` (Santo Varão, 349 cells) 0.40–0.51 s on the laptop and 0.25–0.29 s on the
server, with `relief_source` = MDT in every cell. Golden facts regenerated (31 cases, 15 s): 36 slope facts from the
MDT, 9 from the fallback. Biggest change: Paço das Escolas slope 26 % → 7 % (the surface model measured the University
buildings); Pinhal de Ofir flat share 41 % → 62 % (pine canopy). Spatial QA re-run after the load (2026-09-28, 49 min): bad = 0 in all 13 vector tables.

## 2026-09-28 — Fact status as columns (level, PT/EN reading, pill word, caveat), not parsed from the English value

- **Problem.** The only reader with a UI (the private rehearsal explorer) built PT/EN card titles, statuses and the
  "what we don't know" list with regular expressions over the English `value` text that `facts_at` / `facts_in` write.
  Any wording change in `schema.sql` broke it silently — and it already had: two-word IPMA classes and four plot facts
  showed raw English on the Portuguese page (`docs/lessons.md`).
- **Contract (approved by Fernando).** Six columns appended at the END of `facts_at`, `facts_in` and `facts_for` (readers
  that select by name are unaffected): `level` (hi · md · lo · na · in), `label_pt`, `label_en`, `tag_pt`, `tag_en`
  (short pill word when it is not the level's own word — hazard class, "Perto", "Exclusão", COS year) and `caveat`
  (`relief_fallback` · `ren_lines_unpublished` · `census_whole_subsections` · `pilot_edge`). The SQL writes them where the
  raw columns are at hand (`classe_ord`, `tipologia`, `pretorno`, counts), with four small helpers (`slope_class_en`,
  `aspect_class_en`, `hazard_en`, `fmt_num`). `value` is unchanged — it stays the agent's English evidence and the
  golden files' text. `constraints_grid` is unchanged.
- **Behaviour changes (approved).** A point within 100 m of a REN watercourse line is `md` "Linha de água da REN a 28 m"
  (was shown as "inside"; the point is near the bed, not in it, and the band width is not in the layer); on the line,
  or a line crossing a plot, stays `hi`. EN translates ordinal classes (hazard, IPMA risk, slope classes, SO/O/NO →
  SW/W/NW); names stay Portuguese. A municipality without a REN/RAN delimitation reads "não disponível … — não
  consultada" (the database cannot tell "not published" from "not loaded"). Plot facts that had no PT text now have it.
- **Checks (laptop, 2026-09-28).** Golden `value` identical to the pre-change run (694 lines); 632 fact rows over the 31
  cases, 0 with a NULL level or label, all levels in the vocabulary; REN branches tested outside the golden set (on a
  line → hi, 28 m → md "Perto", outside polygons with a line at 57 m → md, Condeixa-a-Nova → na, plot crossed by
  117 m of line → hi). `facts_at` Paço das Escolas 0.26 s (old function 0.35 s, same session), `facts_for` 7.6 ha plot
  0.16 s, `constraints_grid` 349 cells 0.80–0.85 s. The explorer reads the columns (regex kept only as a fallback — the
  same four cases render identically with the columns stripped); 62 screens (31 cases × PT/EN) with 0 console errors. Spatial QA re-run after the change (53 min): bad = 0 in the 13 vector tables.

## 2026-09-30 — Site selection ("where could this go?"): designed now; the airport benchmark is a gated demo scene

- **What.** A second mode that inverts the question — the person states what to build and the conditions, the agent
  returns ranked zones in a study area, each with its explanation graph, and a why-not map. Design only:
  `docs/site-selection.md`. Test case: the new Lisbon airport, framed as a **benchmark against the public CTI study**
  (9 options, final report 11 Mar 2024; Government decision for the Campo de Tiro de Alcochete, 14 May 2024) — the agent
  reproduces a screening from open data and explains each exclusion; it does not decide anything.
- **Decided by the author.** Airport in the demo; study area AML + Lezíria do Tejo + Vendas Novas (30 municipalities,
  7 512 km², all nine CTI options inside); other intents to support later: large PV, logistics, data centre, public
  facility; data for the airport area loaded **before** the window, each load with its own go-ahead.
- **Guard rails.** Plot mode stays the core and is never cut. Site mode is built in the window only if the Sat 17
  midpoint checkpoint is green (loop with revisions, graph, ≥ 5 golden cases); otherwise nothing about it is claimed.
  No new SQL function before the window; new loader stages are declared as pre-existing ETL. For national
  infrastructure, LEGAL regimes are measured and named with the procedure they trigger, not treated as exclusions,
  until the author validates one as absolute.

## 2026-09-30 (later) — Site selection becomes the core; plot mode becomes the secondary entry

- **What.** The submission is built around the inverse question: the person says what they want to build or do and
  the agent works out what has to be analysed, checked and compared, then presents the **three best candidates with
  pros, cons, evidence and what it could not assess**. The plot mode ("evaluate a place") stays — as a secondary button
  and as the detail view of each candidate. The airport is one catalogue type (benchmark against the CTI), not a
  separate scene.
- **Why (the author).** More useful than starting from a coordinate; with the structure prepared, any question — an
  airport, a school, a solar plant — only depends on what that structure needs. Open data is what makes it possible, so
  the demo focuses where the data is densest: **Lisbon and its surroundings** (AML + Lezíria do Tejo + Vendas Novas).
- **Catalogue for the demo.** Airport, large PV plant, logistics park, school/health centre, housing development; a
  high-speed rail corridor if possible (a different engine — corridor, not footprint); the data centre as the honest
  "cannot assess" example. Requests outside the catalogue are composed from requirement primitives, and every answer
  states its coverage.
- **Data.** Open-data inventory in `data/inventory.md` (metadata only); loads in three tiers, each with a go-ahead.
  Coimbra and Cávado stay loaded for now (31 golden cases live there); dropping them is an option only if disk forces it,
  decided with measurements.
- **Guard rails unchanged.** Pre-window = data, profiles as data, docs; the engine is written inside the window; no
  new SQL function before it. To rewrite before 14 Oct: `docs/plano-janela.md`, `docs/ux.md`, README, video script,
  golden cases for the Lisbon area.

## 2026-09-30 (later) — Site profiles as data; what reading the legal texts changed

- **What.** `data/site_profiles.json`: 15 requirement primitives bound to layers (with the tier each layer arrives in),
  shared rules, and 7 type profiles — airport (benchmark), large PV, logistics, school/health centre, housing,
  high-speed rail corridor (corridor engine) and data centre (`assessment_policy: no_ranking`). Every threshold is
  LEGAL or TECHNICAL, `proposta`, and says how far its article was checked (`texto_oficial`, `texto_consolidado`,
  `fonte_secundaria`, `nao_verificado`). Numbers without a found source stay `null` — the author sets them.
- **Found in the texts (30 Sep), and why it matters.** (1) SGIFR art. 60 n.º 2 c) exempts non-residential works with no
  alternative location — energy production, transport routes, grids — from the building ban in priority fire areas: for
  PV, airport and rail, fire hazard is a technical risk, not a ban; for housing and schools it can be a ban.
  (2) RJREN: for public infrastructure subject to EIA, a favourable EIA decision counts as recognition of relevant public
  interest — REN is a procedure for the airport and rail, not an exclusion. (3) Since DL 11/2023 the solar EIA threshold
  is by area (≥ 100 ha of panels; ≥ 10 ha or ≥ 20 MW in sensitive areas), logistics platforms ≥ 15 ha, urban allotments
  ≥ 10 ha or > 500 dwellings. (4) RJAIA art. 31-A provides an environmental analysis of corridor alternatives — the same
  shape as the corridor engine. (5) The noise regulation forbids licensing new dwellings, schools and hospitals where
  sensitive-zone limits (Lden 55 / Ln 45) are exceeded — open noise maps exist only for Lisboa and Oeiras, so elsewhere
  noise is "not assessed".
- **Guard rails.** Data only; the engine that reads it is window work. Coverage per profile is computed from the layer
  availability, so the data centre stays "cannot assess" by construction (power for consumption, cooling water and
  fibre have no open data).

## 2026-09-30 (evening) — Tier 1 closed for the Lisbon study area; Tier 2 starts with the SRUP pack, study area only

- **What.** Region `lisboa_tejo` (the other 29 municipalities of the study area) loaded with every Tier-1 stage and the
  LiDAR relief: 4 regions, 55 municipalities, spatial QA `bad = 0` in 13 tables, golden facts changed only where the
  data changed (IPMA snapshot, Cávado relief now from the MDT). The author approved Tier 2 the same day; its first
  family is the DGT SRUP pack — 16 easement families (aeronautical, defence, heritage, public water domain, abstraction
  protection zones, pipelines, forest regime, irrigation, …) in `dgt_srup`, `dgt_srup_linhas`, `dgt_srup_pontos`,
  loaded for regions `lisboa` + `lisboa_tejo` only.
- **Why this scope.** Site selection needs the LEGAL regimes measured inside the study area; outside it they are not
  used before the window, and a smaller database keeps the deployment copy within its disk budget.
- **Loader changes kept** (`docs/lessons.md`, 2026-09-30): `ST_Covers(region, x)` in the trim and the QA (prepared
  geometry; hours → minutes, same results), tiled Int16 rasters, one SRUP request per municipality when the region
  request fails, the CCDR Alentejo REN service (Vendas Novas), no XSD download for SRUP.
- **Licences.** Every SRUP record used is CC BY 4.0 on dados.gov.pt; "Espécies Agrícolas e Florestais" is left out
  (licence not specified). Tier-2 sources whose licence is "not stated" (LNEG areas, APA protection perimeters, Metro
  GTFS) may be loaded but are not shown in the demo until the licence is confirmed.
- **Consequences.** REN is not published by the source for 12 municipalities of `lisboa_tejo` (checked in the GML) —
  they answer "not available", never "outside". Older PDMs overlap their neighbours at the border (CRUS) — a known
  issue to fix in the loader. Tier-2 tables reach the deployment copy incrementally, after the author's OK and a disk
  check.

## 2026-09-30 (night) — Tier 2 mostly loaded for the Lisbon study area; CRUS clipped to each plan's municipality

- **What.** Six more Tier-2 families loaded locally for regions `lisboa` + `lisboa_tejo`: IP rail and national roads,
  OpenStreetMap (road/rail network, power lines, substations and plants, schools/health/stations), E-REDES (hosting
  capacity and load per substation, secondary substations), APA drinking-water protection perimeters and groundwater
  bodies, TML schools and health centres of the AML, and Oeiras's strategic noise map. Spatial QA `bad = 0` in 22
  tables; golden facts unchanged (0 differences over 696 lines). 244 MB locally, a 50 MB dump; not on the demo server.
- **Licences.** OSM and the TML facilities are ODbL (attribution; a published derived database stays ODbL) — the TML
  licence is the one of its source repository, although dados.gov.pt says "not specified". APA perimeters and
  groundwater bodies stay "not stated": loaded, marked in `dataset_meta`, never shown in the demo until confirmed.
- **CRUS.** The border overlap of older PDMs was measured over all 55 municipalities (≈ 2 050 ha, not the ~3.5 km² of the
  first look) and fixed in the loader: each plan is clipped to its own municipality (CAOP 2025) before trimming. No golden
  fact changed.
- **Found and fixed on the way** (`docs/lessons.md`): the SRUP pack loaded in the afternoon had its `lisboa_tejo`
  attributes cut to the types GDAL guessed from the `lisboa` file (texts, diploma links, decimals) — reloaded with every
  attribute as the published text; geometry unchanged. A national feature reaching another pilot region is now removed
  from Tier-2 tables (`keep_study_area`).
- **Not loaded, and why.** Lisboa's noise map (a download behind a JavaScript challenge — noise is "unknown" outside
  Oeiras); official hospital points and registered users per primary-care unit (no open point layer; the SNS dataset is
  aggregated per ACES — OSM hospitals instead); LNEG PAER / less-sensitive areas and geology, DGEG plants, GTFS (next).
- **Later the same night:** LNEG areas of lower sensitivity for solar and wind (4 scenarios; licence not stated →
  marked) and public transport (Carris Metropolitana stops and route patterns from the TML OGC API, Metro de Lisboa
  stations and lines; CC BY 4.0) — QA `bad = 0` in 24 tables, golden facts unchanged; Tier 2 now 292 MB locally, 65 MB
  dump. The LNEG acceleration areas (PAER) are view-only (the service returns no geometry) and transit timetables stay
  out (the Carris Metropolitana GTFS has no stated licence): transit travel time is not assessable before the window.
- **Open for the author.** E-REDES substation load (availability for consumption at distribution level) is loaded but
  bound to no requirement: whether it enters the data-centre profile as partial evidence is a profile decision.

## 2026-10-01 — Organizers' answers and the current rules: track confirmed; Zetaris, Meterless and Cursor are mandatory

- **Track: The Agent That Can Explain Why — confirmed** by the decision rule of 2026-09-27 (first row): the organizers
  answered that declared pre-existing data components are accepted and only window work is judged (`docs/lessons.md`,
  2026-10-01). The event page now lists it as the second of three challenge tracks (Solving Fragmented Intelligence, The
  Agent That Can Explain Why, Reasoning Architecture) plus the Wildcard [Tinkerer]; its text: "Build agents that
  investigate complex questions across multiple data sources, connect findings, and produce evidence-backed answers or
  recommendations". §3 allows changing track until the deadline; it is selected in HackOS on Day 1 anyway.
- **Binding text re-read 2026-10-01** (event page, §5–§7): "Every submission must integrate Zetaris and Meterless, and
  teams must use Cursor for development." · "Integrate NVIDIA technology wherever it contributes to your project,
  workflow or use case." · §6: a demo video of 1–4 minutes showing "how Zetaris and Meterless are integrated"; a slide
  deck (problem and users, solution, workflow or architecture, stack, how Zetaris and Meterless were used, what was
  unique about the sponsor use, product visuals, future enhancements); a GitHub repository with a README covering setup,
  usage and dependencies; "a clear explanation of how Zetaris and Meterless were integrated, how Cursor was used during
  development, where NVIDIA technology contributes". · §7: Impact 30, Technical 20, Innovation 15, Demo 15, Product & UX
  10, Sponsor tech 10 — no bonus points.
- **Consequences for the plan** (`docs/plano-janela.md`): Zetaris (at least discovery + one governed query) and the
  Meterless World Model move to "Never cut"; H-MEM stays optional (the World Model is the Meterless integration); the
  build-window code is written in **Cursor** — installed, signed in and the repository opened there before 14 Oct (how
  AI assistance is used inside Cursor is the author's call); a **slide deck** joins the Mon 19 deliverables; the video
  target stays 2:50 (inside 1–4 min) and names Zetaris and Meterless on screen; a public URL is not required — the demo
  server can stay behind its password with the access details in the submission form, and `docker compose up` from the
  README is the path every judge can run.
- **Still open with the organizers:** Zetaris access (hosted sandbox or own account; MCP on the Hobby tier) and spatial
  push-down — the flat views of `data/views.sql` and precomputed tables are the fallback they called safe; NVIDIA event
  credits and model ids. Answers expected on HackOS and at the Zetaris + Cursor workshop (12 Oct, 22:00 UTC).

## 2026-10-01 (later) — Geology at 1:500 000, DGEG solar plants without the owner, and licence statements in conflict

- **Geology: the LNEG map at 1:500 000 (5th edition, 1992), not the AML map at 1:100 000.** Checked the same day: the AML
  map is CC BY 4.0 on dados.gov.pt but published only as two sheet images (JPG, PDF) — loading it would mean digitising;
  the continuous 1:200 000 vector prototype (CC BY) covers 1 km² of the 7 512 km² study area (measured); the 1:500 000
  vector map covers 7 510 km² (`lneg_geologia`, 57 rows, 50 units). Consequence: geology is a **regional** TECHNICAL
  reading (0.5 mm on the map = 250 m on the ground) for the airport and logistics profiles, never a foundation fact for a
  plot; the AML 1:100 000 stays a post-hackathon item (digitising, or asking LNEG for the vector).
- **DGEG solar plants are loaded without the `proprietario` field.** No rule needs it and a licence holder can be a natural
  person; the project keeps no personal data. 114 rows from 59 licensing processes in the study area; park-level power
  and area repeat on every block row, so nothing is summed per row (failure mode 32).
- **Licence statements in conflict → the stricter applies, display is the author's call.** The LNEG lower-sensitivity
  areas (until today "not stated") have a dados.gov.pt record with CC BY 4.0, while the LNEG geoPortal legal notice says
  no commercial use (and no public display without written consent); the DGEG register is CC BY 4.0 on dados.gov.pt and
  CC BY-NC 4.0 in its own service. Both are recorded with where each statement was found (`data/sources.md`,
  `dataset_meta`), as for the fire-hazard map. The LNEG areas stay off screen until the author decides; the APA layers,
  with no statement anywhere, stay off screen until APA confirms.

## 2026-10-01 (afternoon) — REN charts as a view-only backdrop (option B); EEA noise contours loaded

- **Author's choice for the REN gap (option B):** where the DGT publishes no REN polygons, the official REN chart is
  shown as an **image**, labelled "REN chart (image) — not measured", never a fact, a share or a verdict; the cell stays
  *unknown* for REN. Options (a) — asking the DGT to reuse the SNIT-SGT deposit files — and (c) — nothing — were not taken.
  Source of the images: the DGT's per-municipality WMS (`SDISNITWMSREN_<DICO>_1`, georeferenced by the DGT) when it
  answers — on 2026-10-01 its GetMap did not (60–90 s, 0 bytes) while GetCapabilities did — else the chart images of the
  SNIT-SGT portal, kept in `data/raw/ren_snit/` (git-ignored, never committed or put in the sample: SNIT terms allow
  consultation and visualisation only) by `data/etl/ren_cartas.sh`. Those images carry no georeference: Loures and
  Salvaterra de Magos are fitted to the CAOP 2025 extent of the municipality (one scale and one margin) and checked by
  overlay; Amadora is approximate, Alpiarça and Sesimbra do not fit that way and Coruche is nine sheets — WMS or hand
  georeferencing (QGIS, ground control points) for those.
- **Noise: the EEA's END 2022 contours for Portugal** (research and non-profit use) add the whole agglomerations of
  Amadora and Odivelas and the major-road corridors in the study area; Oeiras keeps its municipal map; Lisboa is in
  neither (the CML file stays behind a Cloudflare challenge — the author downloads it by hand if wanted). Non-commercial
  terms → displayed only by the author's decision, like the DGEG register.

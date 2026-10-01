# Slide deck — skeleton (text only; for the author's review by 13 Oct)

Required by the Official Rules §6 (re-read 2026-10-01, `docs/decisions.md`): problem and users, solution, workflow or
architecture, stack, how Zetaris and Meterless were used, what was unique about the sponsor use, product visuals, future
enhancements. The slides below follow that order, plus one slide of evals and one of limits.

**What this file is:** the words and the plan of each slide, written before the window. **What it is not:** the deck.
Screenshots, diagrams and every number marked *(window)* come from the build and the dated eval runs of 15–19 Oct; the
deck is assembled on Mon 19, 20:15–21:00 (`docs/plano-janela.md`). Nothing here describes code that exists today: the
agent, the site engine and the UI are window work (`PRE-EXISTING.md`).

**Rules for every slide** (same as `docs/video.md`): no number typed by hand — each comes from `evals/results/` or a
dated log, or from `data/README.md` for the data counts; no single suitability score; never "licensable" or "forbidden";
grey for unknown, never green; no layer whose licence is "not stated" (`data/sources.md`) in any screenshot; "©
OpenStreetMap contributors" on every map that draws an OSM layer; "screening, not a decision" said once; publishers
named as text, not logos. Language: English (the data values stay Portuguese, labelled).

Legend: **F** = fact checked in the repository today · **P** = plan or design, to be true by the deadline or removed ·
**W** = filled from the window's build and runs.

---

## 1. Title

- **On the slide:** Território Explicado — *Territory, Explained*. "Where could it go — and why not elsewhere?" Track:
  The Agent That Can Explain Why · Open Agent Hackathon 2026 · Fernando Mendes (solo).
- **Visual:** the why-not map of the opening request, one excluded cell open with its reason (W; same frame as the
  video's cold open).

## 2. Problem

- **On the slide:** Where could a solar park, a school, a logistics hub or an airport go in Portugal? The answer crosses
  PDM land-use plans, REN, RAN, protected areas, a dozen kinds of easement, flood and fire hazard, terrain, road, rail
  and grid — **more than ten publishers, incompatible formats** (F: `data/sources.md`). The law rarely says *no*: it
  says *which procedure, how many hectares, who decides*. Early screening = weeks of consultant work; the reasons rarely
  reach the people affected.
- **Visual:** a wall of publisher names as text tiles — DGT, ICNF, APA, INE, IPMA, IP, E-REDES, LNEG, TML, municipalities
  — each with the format it publishes in (WFS, shapefile, ArcGIS REST, CSV, GTFS).
- **Speaker note:** one sentence on why "explain why" matters here: a siting decision without its reasons is not
  checkable by the people it affects.

## 3. Users

- **On the slide:** municipal and intermunicipal planners and promoters doing an early screening · journalists and
  citizens checking the reasons behind a siting decision · secondary: a person who wants to know what constrains one
  plot.
- **What they need (one line each):** the reasons, not a score · the procedures a site would trigger · what nobody can
  know yet from open data · the source of every claim.
- **Speaker note:** real requests behind the golden cases (13 site cases, 31 plot cases — F: `evals/cases/`).

## 4. Solution

- **On the slide:** "Onde construir?" → **coverage first** ("*n* of *m* requirements can be assessed", each missing one
  with its reason) → **three candidate zones**, each with pros, cons, the LEGAL procedures it would trigger and what
  could not be assessed → a **why-not map** where every excluded cell names its rule → any candidate or plot opens to
  "Avaliar um sítio".
- **Rules it never breaks (P, `docs/site-selection.md`):** unknown is never free · LEGAL = a procedure with hectares,
  not "forbidden" · every threshold typed LEGAL (diploma) or TECHNICAL (rule of thumb) · no single score: Pareto layers
  · never picks "the" site · not legal advice — when the law decides, it points to the municipality's formal answer
  (*Pedido de Informação Prévia*).
- **Visual:** the main screen with the coverage line and the three cards (W).

## 5. Workflow — roles that challenge each other

- **On the slide:** request → **Planner** (site profile from 15 requirement primitives, coverage) → **Evidence Tracer**
  (screening grid, footprints, facts) → **Challenger** (samples excluded cells and claims; accept / reject / ask for
  more) ⇄ revision, at most 3 rounds, then an explicit unknown → **Explainer** (cards and trade-off from accepted links
  only). All roles read and write one **Meterless World Model**.
- **Visual:** the loop diagram (the README's text diagram, redrawn), and next to it the real revision round from the
  log of the opening run: the claim the Challenger rejected and what the Planner changed (W).
- **Speaker note:** not a fixed chain — the roles interact more than once in a run, and the log shows it (HackOS
  participant resources).

## 6. Architecture

- **On the slide:** Browser (React + MapLibre) ⇄ API (Node 20 / TypeScript) → roles on the World Model → tools:
  Zetaris MCP (discovery, governed SQL) · PostGIS fallback · live IPMA fire risk · geocoder → LLM router (Nemotron) →
  answer = candidates + why-not map + evidence paths + unknowns.
- **Data platform (F, declared pre-existing):** PostGIS, 4 regions / 55 municipalities, the Lisbon study area of 30
  municipalities and 7 512 km² for site selection; Tier 1 in all four regions, Tier 2 (11 families: easements,
  networks, grid capacity, services, noise, renewables zoning, transit, geology, existing solar plants) in the study
  area (`data/README.md`).
- **Visual:** the architecture diagram of `docs/architecture.md`, redrawn; pre-existing parts in one colour, window
  parts in another.

## 7. Stack

| Layer | Technology | Built |
|---|---|---|
| Agent roles, loop, site engine, API | Node 20 + TypeScript | window (P) |
| UI | React + MapLibre GL JS | window (P) |
| Shared case state | Meterless World Model (+ H-MEM only if wired) | window (P) |
| Data access | Zetaris MCP; PostGIS directly where a spatial function does not push down | window (P) |
| Models | NVIDIA Nemotron 3 Super (Planner, Explainer) · Nemotron 3.5 Lightning (extraction, Challenger) | window (P) |
| Data platform | PostgreSQL 16 / PostGIS 3.4, GDAL/OGR ETL, open data | pre-existing, declared (F) |
| Development | Cursor (window); Claude Code before the window for data and docs (declared) | — |

## 8. How Zetaris is used

- **On the slide (P):** the Evidence Tracer's data layer. Discovery (`get_schema`, `list_tables`) tells the agent what is
  loaded for the study area; governed SQL over the `territorio` semantic layer returns the facts per cell and per
  candidate; each evidence item keeps its query, and the query log is the lineage the evidence panel shows. A spatial
  function that does not push down runs on PostGIS, via the flat views of `data/views.sql` where possible — and the
  answer names the path that served it.
- **Numbers (W):** share of evidence served through Zetaris · latency p50/p95 · limits found (`docs/sponsor-fit.md`).
- **Visual:** the evidence panel of one claim: dataset, publisher, licence, date, and the Zetaris query (W).
- **Open (F):** Zetaris access and spatial push-down are still being answered by the organizers; the workshop is on
  12 Oct, 22:00 UTC. This slide is rewritten after it.

## 9. How Meterless is used

- **On the slide (P):** the World Model agent engine **is** the shared case state: one typed graph per run — request,
  profile, cells, zones, datasets, diplomas, rules, evidence — with provenance on every edge and the Challenger's
  verdict on every link, plus an append-only log from which the canonical view is rebuilt. The explanation graph of a
  candidate is a query over it, not a picture drawn afterwards. H-MEM (Memory keeper) appears here only if a recall
  changed a first plan in a measured way; otherwise it is not on the slide.
- **Numbers (W):** claims reconstructable from the log alone · edges per answer and share with a verdict · rebuild time.
- **Visual:** the graph of one candidate, from the World Model, next to its card (W).

## 10. What is unique in the sponsor use

Proposals — each stays on the slide only if the build does it (P):

- **Lineage the user can click:** every reason on the why-not map opens to the governed Zetaris query that produced it —
  the data layer's audit trail becomes the explanation, not a back-office log.
- **The World Model is the explanation:** cards and why-not map are queries over the graph; the Challenger's verdicts are
  edges; "why" can be rebuilt from the append log alone.
- **Unknowns are first-class:** a layer that is not loaded, not open or not licensed is an entity with its reason, so
  "not assessable" is as traceable as a finding — the coverage line is a count over those entities.

## 11. Product visuals (screenshots from the window build)

1. Main screen: request, coverage line, three candidate cards (W).
2. Why-not map: the four states (excluded · legal regime · unknown · admissible) told apart by pattern and word; a grey
   cell open with its reason (W).
3. Evidence panel: dataset, publisher, licence, date, query (W).
4. Trace by role with a revision round (W).
5. A candidate opened in "Avaliar um sítio": shares of the plot per constraint and the law behind each (W).
6. The data centre: "I can't rank candidates for this type" and the requirement with no open data (W).

## 12. Evals

- **On the slide (W):** site golden cases — coverage correct, why-not probes exact, honesty, abstention; the airport
  benchmark line (CTA and Vendas Novas in the top 5? first failing criterion vs the CTI's stated reason); plot golden
  cases — task success, evidence integrity; revision rounds, latency and tokens per case; routed vs Super-only.
  Tables in `docs/submission.md` §Evals.
- **Speaker note:** the benchmark reproduces a public screening from open data and explains each exclusion; it does not
  re-open the decision.

## 13. Limits we found (honest)

- **On the slide (F, `docs/failure-modes.md`):** absence in OpenStreetMap is not absence (135 of 2 119 TML schools in
  the AML have no OSM point within 200 m) · 24 of 128 E-REDES substations known only by municipality · noise known in 1
  of 30 municipalities · transit without timetables → no travel time · layers with licences not stated kept off screen ·
  LNEG acceleration areas view-only.
- **Plus** the failure modes found inside the window (W).

## 14. Future enhancements

- Tier 2 beyond the Lisbon study area; Tier 1 for the whole mainland (F: today 4 regions).
- Corridor engine for linear works (high-speed rail between two endpoints) — designed, not built (`docs/site-selection.md`
  §4).
- Transit travel time once timetables are published with a licence; noise beyond Oeiras.
- Airspace, obstacle surfaces from the DGT LiDAR surface model, aircraft-noise contours (post-hackathon, §8).
- LEGAL thresholds validated by a jurist, article by article; licences confirmed with APA and LNEG.
- A hand-off to the formal route: the evidence pack of a candidate as the attachment of a *Pedido de Informação Prévia*.

## 15. Close

- **On the slide:** repository (public) · `docker compose up` · `SAMPLE_MODE=true` without keys · demo URL (password in
  the submission form, never on the slide) · "Built in the window: the agent and the site engine. Declared
  pre-existing: the data platform."

---

## For the author (decide by 13 Oct)

| Decision | Options | Proposal |
|---|---|---|
| Tool and file | Google Slides · a claude.ai Slides artifact (exports .pptx/PDF) · PDF from Markdown | one that exports PDF; upload PDF |
| Length | 15 slides as above · 10 (merge 2+3, 6+7, 12+13; drop 15) | 12–15; the rules give no limit |
| Opening request | solar park near Samora Correia (`site-lx-005`) · airport | same as the video (`docs/video.md`: solar by default) |
| Slide 13 (limits) | keep · move to an appendix | keep — the track is about explaining why, limits included |
| Slide 10 claims | keep the three · keep only what the build proves on the Sat 17 check | decide on Sat 17 |

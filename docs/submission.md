# Submission form — draft (final text on Mon 19 Oct; fields marked *(window)* are filled from real results)

Hard deadline **Wed 21 Oct 00:45 Lisbon** (Tue 20 23:45 UTC); target **Mon 19 by 22:00**, before judging opens (Tue 20
01:00). Ties are broken by Impact, then by submission timestamp. The submission can be updated until the deadline
(HackOS FAQ); the form's availability is announced in HackOS Announcements.

HackOS asks for: project name, description, team members, selected track; links to the GitHub repository, the live demo
and Google Drive where relevant; an uploaded short demo video; the problem, solution, technologies used and sponsor
technology. The Official Rules (§5–§6, re-read 2026-10-01) require: a **demo video of 1–4 minutes** showing the main
workflow, how the agent solves the challenge, its key features and **how Zetaris and Meterless are integrated**; a
**slide deck** (problem and users, solution, workflow or architecture, stack, how Zetaris and Meterless were used, what
was unique about the sponsor use, product visuals, future enhancements — skeleton in [`deck.md`](deck.md)); the GitHub
repository with a README covering setup, usage and dependencies; **a clear explanation of how Zetaris and Meterless
were integrated, how Cursor was used during development, where NVIDIA contributes**; and the declaration of
pre-existing product code. A public URL is not required; the password-protected demo URL goes in with its access
details (organizers, 1 Oct).

**Rewritten 2026-10-01 for site selection as the core** (`docs/decisions.md`, 2026-09-30; README and `docs/video.md`
already were): the description, problem and solution lead with "where could it go?"; the plot mode is the deep-dive.
The previous plot-first text is in git history.

## Fields

- **Project name:** Território Explicado — Territory, Explained
- **Track (exactly one):** The Agent That Can Explain Why (second of the three challenge tracks on the event page) —
  selected 2026-09-27, confirmed 2026-10-01 after the organizers accepted declared pre-existing data components
  (`docs/decisions.md`, `PRE-EXISTING.md`). Selected in HackOS on Day 1.
- **Team members:** Fernando Mendes (solo)
- **One-liner (158 chars):** An agent that finds where something could be built in Portugal and explains why there and not
  elsewhere, every reason traced to the map, the data and the law.
- **One-liner, long form (316 chars):** Say what you want to build — a solar park, a school, an airport — and where. The
  agent screens the area with open geodata, says first what it can assess, and returns three candidate zones with pros,
  cons, the legal procedures each would trigger and the unknowns, plus a map where every excluded place names its rule.

### Problem (≈ 90 words)

Where could a solar park, a logistics hub, a school or an airport go in Portugal? The answer crosses municipal land-use
plans (PDM), the ecological and agricultural reserves (REN, RAN), protected areas, a dozen kinds of easement, flood and
wildfire hazard, terrain, road, rail and grid networks — published by more than ten institutions in incompatible
formats. And for most of these regimes the law does not say *no*: it says which procedure, how many hectares, who
decides. Early screening takes weeks of consultant work; its reasons rarely reach the people affected.

**Users:** municipal and intermunicipal planners and promoters doing an early screening of where something could go;
journalists and citizens checking the reasons behind a siting decision. Secondary: a person who wants to know what
constrains one plot of land.

### Solution (≈ 130 words)

The person says what they want to build, where, and under which conditions (hectares, "avoid cork-oak montado"). A
Planner composes a site profile from typed requirements and **states the coverage first** — what the open data can and
cannot assess here. An Evidence Tracer screens a grid over the study area through Zetaris. A Challenger samples
excluded cells and candidate claims and sends weak ones back — at most three rounds, then the gap becomes an explicit
unknown. An Explainer returns **three
candidate zones** with pros, cons, the LEGAL procedures each would trigger and what could not be assessed, plus a
**why-not map** where every excluded cell names its rule. All roles share one Meterless World Model; any candidate, or
any plot, opens to an explained assessment ("Avaliar um sítio").

It never picks "the" site, never says "licensable", never shows unknown as free; when the law decides, it points to the
formal route (a *Pedido de Informação Prévia* at the municipality). It is screening, not legal advice.

### Technologies

Node 20 + TypeScript agent roles, loop and site engine *(window)* · PostgreSQL 16 / PostGIS 3.4 data platform
(pre-existing, declared) · React + MapLibre *(window)* · Zetaris MCP data layer · Meterless World Model (shared case
state and explanation graph) + H-MEM (Memory keeper — only if wired into the loop) · NVIDIA Nemotron 3 Super (Planner,
Explainer) + Nemotron 3.5 Lightning (extraction, Challenger) · open data from DGT, ICNF, APA, INE, IPMA, IP, E-REDES,
LNEG, TML, Metro de Lisboa, OpenStreetMap contributors, Copernicus · developed in **Cursor** inside the window; the
pre-window data platform was prepared with Claude Code (declared). All code reviewed and tested by the author.

### Sponsor technology — where each is used (draft for the form; final text from `docs/sponsor-fit.md`)

- **Zetaris (required):** the Evidence Tracer's data layer — discovery of what is loaded for the study area
  (`get_schema`, `list_tables`) and governed SQL over the `territorio` semantic layer for the facts per cell and per
  candidate; each evidence item keeps its query, and the query log is the lineage shown in the evidence panel. A
  spatial function Zetaris does not push down runs on PostGIS directly, through the flat views of `data/views.sql`
  where possible, and the answer names the path that served it. *(window: share of evidence served through Zetaris,
  latency, limits found)*
- **Meterless (required):** the World Model agent engine is the shared case state — every role reads and writes one
  typed graph per run (request, profile, cells, zones, datasets, diplomas, rules, evidence) with provenance and the
  Challenger's verdict on every edge, plus an append-only log the canonical view is rebuilt from; the explanation
  graph of each candidate is a query over it. H-MEM stays only if a recall changes the Planner's first plan in a
  measured way. *(window: claims reconstructable from the log, edges with a verdict)*
- **Cursor (required for development):** every line written in the window, in Cursor; which features were used, for
  which files and what was rewritten by hand is logged daily in `docs/sponsor-fit.md`. *(window)*
- **NVIDIA (where it contributes):** Nemotron 3 Super plans and explains; Nemotron 3.5 Lightning extracts and
  challenges; routed vs Super-only measured on the same cases. *(window)*

### Links

- Repository (public): https://github.com/FMendes7/territorio-explicado
- Live demo: https://territorio.mvp.tugachain.com — password-protected; access details in the form only, never in the
  repository *(window — URL confirmed at deploy)*
- Video (1–4 min, target 2:50, uploaded to HackOS; YouTube unlisted mirror): *(window)*
- Slide deck: exported from [`deck.md`](deck.md) + the window's screenshots and eval numbers *(window)*
- Google Drive: only if the sample extract is too large for the repository *(window)*
- Evals: `evals/results/` + summary in README *(window)*

### Failure modes found

`docs/failure-modes.md` — 32 entries before the window: data quality, geometry, legal vs technical thresholds,
unknown vs free, and the limits of the Tier-2 site layers (absence in OpenStreetMap, substations known only by name,
noise known in one municipality, transit without timetables, licences not stated or in conflict, a view-only map
service, legal text cut silently by a typed reader, park figures repeated on every block) — plus the dated section "Found inside the window", including the fallback drill
*(window)*.

### Pre-existing components (rules 4 and 5)

`PRE-EXISTING.md`: the PostGIS data platform (ETL, schema, lookup functions; Tier 1 in four regions and Tier 2 in the
Lisbon study area), accounts and connections, golden cases for both modes, the plot intents and the site profiles (as
data), documentation; the last pre-window commit is tagged `pre-window`. The site engine (screening grid, cell
verdicts, footprint fit, zones and ranking), the agent roles and loop, tools, router, World Model store, evidence
schema and explanation graph, UI, sample mode, evaluation runner, packaging, deck and video are written inside the
window. A private rehearsal prototype (and a static mock-up of the main screen) existed; no file from it is in the
repository.

### Evals (numbers) *(window)*

Site selection (`evals/cases/site_golden.jsonl`, checks in `evals/README.md`):

| Metric | Routed (Super + Lightning) | Super only |
|---|---|---|
| Coverage line correct (`coverage`) | | |
| Why-not probes exact (`probe`: exclusion rules; procedures, favourable zoning and unknowns named) | | |
| Airport benchmark: CTA and Vendas Novas in the top-5 zones (`benchmark_recall`) | | |
| Airport benchmark: first failing criterion matches the CTI (`benchmark_reason`) | | |
| Honesty (`honesty`: every unknown named, nothing in `must_not` said) | | |
| Abstention (`abstain`: outside the study area; the data centre "cannot rank") | | |

Plot mode (`evals/cases/golden.jsonl`) and both modes:

| Metric | Routed (Super + Lightning) | Super only |
|---|---|---|
| Task success (golden, fields set) | | |
| Evidence integrity (claims with ≥ 1 evidence) | | |
| Correct abstention (outside the loaded regions) | | |
| Revision rounds / escalations per case | | |
| Median latency per case | | |
| Tokens per case | | |

## Before pressing submit

- [ ] Every link opens in a private window, off-VPN (phone on mobile data).
- [ ] `docker compose up` from a clean clone works, with keys and with an empty `.env` in `SAMPLE_MODE=true`.
- [ ] No secret in the repo, the logs, the screenshots, the deck or the video: `git log -p | grep -iE
      "api[_-]?key|token|password"` reviewed by eye.
- [ ] Outputs come from real agent runs, never from stored files; `SAMPLE_MODE` runs the same roles on the sample
      extract with deterministic stand-ins for the model calls, labelled; logs are unedited.
- [ ] The organizers' self-test runs verbatim: `docker build`/`docker run -p 8000:8000` (or the documented
      `docker compose up`), `curl -X POST http://localhost:8000/run -d @input_examples/example_1.json`, `example_2`,
      `example_3` (at least one site request and one plot), and again with no `.env` and `SAMPLE_MODE=true`.
- [ ] The roles interact more than once in a run (a revision round is visible in the logs of the demo cases).
- [ ] README, `sponsor-fit.md`, the deck and `PRE-EXISTING.md` claim nothing the code does not do; limitations are
      stated.
- [ ] `input_examples/` and `output_examples/` hold real, dated runs of more than one case.
- [ ] `PRE-EXISTING.md` dated and complete, with the organizers' answer on pre-existing code; video 1–4 min (60–240 s,
      `ffprobe`; Zetaris and Meterless shown) and its link opens logged out.
- [ ] Slide deck uploaded, every number in it from `evals/results/`; the sponsor explanation (Zetaris, Meterless,
      Cursor, NVIDIA) filled from `docs/sponsor-fit.md`; the demo URL's access details in the form, never in the
      repository.
- [ ] No layer whose licence is "not stated" (`data/sources.md`) appears in the video, the deck or the screenshots;
      "© OpenStreetMap contributors" visible wherever an OSM layer is drawn.

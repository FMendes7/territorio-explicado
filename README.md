# Território Explicado — *Territory, Explained*

> **Status: pre-build.** Entry for the [Open Agent Hackathon 2026](https://hackathon.genai.works/event/open-agent-hackathon-2026)
> (GenAI.Works, build window 15–20 October 2026). Track: **The Agent That Can Explain Why** (selected 27 September;
> it changes only if the organizers, asked the same day, do not accept declared pre-existing code in the main tracks —
> then the Tinkerer Track; see [`PRE-EXISTING.md`](PRE-EXISTING.md) and `docs/decisions.md`). Final by the end of
> 15 October (UTC). The agent and the site engine are written **inside the build window**. What exists here before
> 15 October is the data platform, the site and plot profiles (as data), the evaluation cases and the documentation, all
> declared in `PRE-EXISTING.md`; the last pre-window commit will be tagged `pre-window`.

## The problem

*Where* can a solar park, a logistics hub, a school, new housing — or an airport — go in Portugal? The answer crosses
the municipal land-use plans (PDM), the ecological and agricultural reserves (REN, RAN), protected areas, a dozen kinds
of easement (airports, defence, pipelines, heritage, water abstractions…), flood and wildfire hazard, terrain, road,
rail and electricity networks, grid capacity and where people and services are — published by more than ten
institutions (DGT, ICNF, APA, INE, IPMA, IP, E-REDES, LNEG, municipalities…) in incompatible formats. And for most of
these regimes the law does not say *no*: it says *which procedure*, *how many hectares* and *who decides*. Today that
screening is weeks of consultant work, and its reasons rarely reach the people affected.

**Who it is for:** municipal and intermunicipal planners and promoters doing an early screening of where something
could go; journalists and citizens who want to check the reasons behind a siting decision. Secondary: a person who
wants to know what constrains one plot of land.

**In one sentence:** an agent that, given what someone wants to build and under which conditions, screens a study
area with open data and returns the three best candidate zones — each with its pros, cons, the LEGAL procedures it
would trigger and what could not be assessed — plus a *why-not* map in which every excluded place names the rule that
excluded it; any candidate, or any plot, then opens to an explained assessment with its evidence path.

## What the agent does (design — built inside the window)

**Main screen — "Onde construir?" / "Where could it go?"** ([`docs/ux.md`](docs/ux.md) §0):

1. **What and where** — a type from the catalogue (airport, large PV plant, logistics park, school or health centre,
   housing, high-speed rail corridor, data centre) or free text; the study area; conditions (hectares, MW, "avoid
   cork-oak montado", distance to a place).
2. **Coverage first** — "*n* of *m* requirements can be assessed with the loaded data", each missing one with its
   reason — shown before any candidate, never after.
3. **Three best candidates** — a card each: pros, cons, the LEGAL procedures it would trigger (hectares per regime,
   diploma, who decides; "to confirm" while a rule is not validated), what could not be assessed, and one sentence of
   trade-off against the other candidates. No single suitability score: candidates are ranked by Pareto layers.
4. **Why not elsewhere** — every cell of the screening grid is *excluded* (physical infeasibility, with the rule id),
   *legal regime* (a procedure, measured), *unknown* (grey, with the reason — never green) or *admissible*.

**Secondary — "Avaliar um sítio" / "Evaluate a place":** click a point or draw a plot (or open a candidate) and choose
an intent; the agent explains what constrains it, with shares of the plot, the law behind each constraint, what is
unknown, and where nearby the constraints stop.

Agents with distinct roles work on a shared case and **challenge each other** instead of running once in a fixed chain:

```text
request ─▶ Planner ─▶ Evidence Tracer ─▶ Challenger ──accept──▶ Explainer ─▶ candidates + why-not map + evidence paths
 (type,      ▲          (screening grid,       │
  area,      │           footprints, facts)    │  samples excluded cells and claims; checks each against the evidence
  terms)     └──── revision request ◀──────────┘  at most 3 rounds; a gap still open becomes an explicit "unknown"
Shared case state: a Meterless World Model — request, profile, cells, zones, datasets, diplomas, rules and evidence as a
typed graph with provenance and an append log; the explanation graph is a query over it
```

| Role | Model / tool | Does |
|---|---|---|
| Planner | Nemotron 3 Super | turns the request into a site profile from the requirement primitives (`data/site_profiles.json`), states the coverage, revises the plan when challenged |
| Evidence Tracer | tools (Zetaris MCP or PostGIS, the screening grid, live IPMA, geocoder) + Nemotron 3.5 Lightning for extraction | computes the facts per cell and per candidate footprint |
| Challenger | Nemotron 3.5 Lightning | samples excluded cells and candidate claims, tests claim ↔ evidence ↔ rule; accepts, rejects or asks for more evidence |
| Explainer | Nemotron 3 Super | writes the cards and the trade-off from accepted links only, with the evidence path and the unknowns |
| Memory keeper (optional) | Meterless H-MEM | recalls similar cases (context, never facts) with a trust-ledger entry |

Rules the design never breaks ([`docs/site-selection.md`](docs/site-selection.md)): **unknown is never free**; a LEGAL
regime is a procedure with hectares, not "forbidden", until the author validates it as absolute for that use; every
threshold is typed LEGAL (diploma and article) or TECHNICAL (a rule of thumb, said as such); the agent never picks
"the" site nor says something is licensable — when the law decides, it points to the formal route (e.g. a *Pedido de
Informação Prévia* at the municipality). **It is not legal advice.** When the decisive data is not open (a data
centre's grid connection for consumption), it says it cannot rank candidates, and why.

Golden cases for both modes: [`evals/cases/site_golden.jsonl`](evals/cases/site_golden.jsonl) (13 site cases: the
airport benchmark against the published candidate sites of the independent technical commission, solar parks, a
logistics park, a school, housing, the data centre that cannot be ranked, a request outside the study area) and
[`evals/cases/golden.jsonl`](evals/cases/golden.jsonl) (plot mode).

Design: [`docs/site-selection.md`](docs/site-selection.md) · [`docs/reasoning.md`](docs/reasoning.md) ·
[`docs/architecture.md`](docs/architecture.md) · [`docs/ux.md`](docs/ux.md) (interface) · [`docs/manual.md`](docs/manual.md)
(user manual, PT/EN) · [`docs/plano-janela.md`](docs/plano-janela.md) (window plan, proposal).

## Data (pre-existing, declared)

Open data loaded into PostGIS, clipped to **four regions, 55 municipalities**: CIM Região de Coimbra, Cávado, and the
**Lisbon study area** of the site mode — AML, Lezíria do Tejo and Vendas Novas, 30 municipalities, 7 512 km²;
administrative boundaries are national.

- **Tier 1, all four regions:** CAOP 2025, land cover (COS 1995–2025), PDM land-use classes (CRUS), REN, RAN,
  protected areas, fire hazard and burned areas, flood zones, census 2021, housing prices, building footprints and the
  DGT LiDAR 2024 terrain model at 10 m (elevation, slope, aspect).
- **Tier 2, Lisbon study area only (loaded 30 September 2026 in the build database; not yet on the demo server):**
  the DGT pack of easements (SRUP, 16 families), the national rail and road network (IP), the OpenStreetMap road/rail
  network, power lines, substations, schools, health units and stations, E-REDES hosting capacity and load per
  substation and secondary substations, APA drinking-water protection perimeters and groundwater bodies, the schools
  and health centres of the AML (TML), and Oeiras's strategic noise map.

Licences: CC BY 4.0 for most; **ODbL** for OpenStreetMap and the TML facilities (attribution, share-alike for a
published derived database); sources whose licence is **not stated** (APA perimeters and groundwater bodies) are loaded
but never shown in the demo until confirmed. What is loaded, row counts, how to rebuild it and its limits:
[`data/README.md`](data/README.md). Sources, licences and reference dates: [`data/sources.md`](data/sources.md). Every
open dataset found for the study area, loaded or not: [`data/inventory.md`](data/inventory.md).

## Sponsor technology (planned use)

| Layer | Technology | Role in this project |
|---|---|---|
| Data | **Zetaris** (MCP endpoint over federated sources) | discovery, governed SQL and lineage for the Evidence Tracer; falls back to direct PostGIS and says so |
| Token | **NVIDIA Nemotron** via build.nvidia.com | Super plans and explains; Lightning extracts and challenges; cost and latency measured in evals |
| Cognition | **Meterless World Model** agent engine | the shared case state every role reads and writes — entities, typed relationships with provenance, append log — and the source of the explanation graph |
| Cognition (optional) | **Meterless H-MEM** (reference implementation) | Memory keeper: recalled cases change the Planner's first plan, with a trust ledger of where each recall came from — kept only if it does; otherwise removed from this table |

Details and honest limits: [`docs/sponsor-fit.md`](docs/sponsor-fit.md).

## Repository layout

| Path | Purpose |
|---|---|
| `PRE-EXISTING.md` | What existed before the build window and why it is allowed |
| `data/` | Sources, inventory, schema, views, ETL scripts, the site profiles (`site_profiles.json`) and plot intents (`pretensoes.json`) — `data/README.md` |
| `evals/` | Golden cases for both modes (data) and, from 15 Oct, the runner and dated results |
| `docs/` | Decisions, site-selection design, architecture, reasoning, UX spec and user manual, sponsor fit, failure modes, lessons, window plan, video script |
| `input_examples/`, `output_examples/` | from the window: inputs and the outputs of real, dated runs |

## Running it

_Written inside the build window._ Target:

- **Live demo:** `https://territorio.mvp.tugachain.com`, public during judging.
- **One command:** `git clone` → `cp .env.example .env` → `docker compose up` → the app, a PostGIS instance and a sample
  extract (a slice of the Lisbon study area for the main site demo plus the areas of the golden cases).
- **Programmatic entry point:** `POST http://localhost:8000/run` and `npm run agent -- input_examples/example_1.json`
  (JSON in — a site request or a plot — JSON out, trace in `logs/trace-<run_id>.jsonl`) — the UI is not required to
  judge the agent.
- **Default mode runs the real agent** (needs `NVIDIA_API_KEY`; without Zetaris it uses PostGIS directly and says so).
- **`SAMPLE_MODE=true`** runs without keys or network: the same roles run on the sample extract, with deterministic
  implementations in place of the model calls (profile from the type, structural challenges, template sentences). It
  works for any request or plot inside the sample, is labelled in every answer and log line, and never reads a stored
  output.

## AI and model usage

- **Models:** NVIDIA Nemotron 3 Super (Planner, Explainer) and Nemotron 3.5 Lightning (Evidence Tracer extraction,
  Challenger) through build.nvidia.com; model ids in `.env.example`.
- **Agent framework:** none — a small TypeScript loop, written inside the window.
- **Partner technology:** the table above; measured use in `docs/sponsor-fit.md`.
- **Development tools:** AI-assisted coding (Claude Code) for scaffolding, debugging, data preparation and
  documentation. The author reviews and tests all code and can explain every part of it.
- **Data:** public open data, no personal data; the golden cases are real places and real requests, not synthetic.
- **Known limitations:** [`docs/failure-modes.md`](docs/failure-modes.md) and [`data/README.md`](data/README.md).

## Third-party code, data and licences

| Component | Licence | Use |
|---|---|---|
| PostgreSQL / PostGIS | PostgreSQL Licence / GPL-2.0-or-later | database, used as a service |
| GDAL/OGR | MIT | ETL (`ogr2ogr`, `gdal*` in `data/etl/`; `data/etl/osmconf.ini` is GDAL's OSM configuration, adapted) |
| OpenStreetMap data (Geofabrik extract) | ODbL 1.0 — © OpenStreetMap contributors | roads, rail, power, schools, health units, stations (Tier 2) |
| MapLibre GL JS | BSD-3-Clause | map (from the window) |
| Meterless agent engines (World Model, H-MEM) | as published by Meterless (H-MEM reference: Apache-2.0) | shared case state and memory (from the window; any copied code under `third_party/` with its licence and notice) |

Updated as dependencies are added; substantially adapted code is noted in the file header.

## Licence

Code: Apache-2.0 (see `LICENSE`). Data: each dataset keeps its own licence, listed in `data/sources.md`.

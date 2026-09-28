# Território Explicado — *Territory, Explained*

> **Status: pre-build.** Entry for the [Open Agent Hackathon 2026](https://hackathon.genai.works/event/open-agent-hackathon-2026)
> (GenAI.Works, build window 15–20 October 2026). Track: **The Agent That Can Explain Why** (selected 27 September;
> it changes only if the organizers, asked the same day, do not accept declared pre-existing code in the main tracks —
> then the Tinkerer Track; see [`PRE-EXISTING.md`](PRE-EXISTING.md) and `docs/decisions.md`). Final by the end of
> 15 October (UTC). The agent itself is written **inside the build window**. What exists here before
> 15 October is the data platform, the evaluation cases and the documentation, all declared in `PRE-EXISTING.md`; the
> last pre-window commit will be tagged `pre-window`.

## The problem

Deciding what you can do with a plot of land in Portugal — build a house, farm it, plant forest, install solar panels —
depends on the municipal land-use plan (PDM), the ecological and agricultural reserves (REN, RAN), flood and wildfire
hazard, protected areas and terrain, published by five institutions (DGT, ICNF, APA, INE, IPMA) in incompatible
formats. People pay consultants or guess; municipal teams answer the same questions by hand.

**Who it is for:** a person about to buy or use a plot of land. Municipal technicians and consultants who answer these
questions are secondary users.

**In one sentence:** an agent that helps someone about to buy or use a plot of land in Portugal understand what
constrains it for what they want to do, by tracing the relationships between the plot, the land-use classes, reserves,
hazard zones and protected areas that touch it, and the law behind each, using open data from DGT, ICNF, APA, INE and
IPMA, producing an explained assessment with its evidence path, what is unknown, and where nearby the constraints stop.

## What the agent does (design — built inside the window)

The person clicks a point or draws a plot and chooses an intent. Agents with distinct roles work on a shared case and
**challenge each other** instead of running once in a fixed chain:

```
intent + place ─▶ Planner ─▶ Evidence Tracer ─▶ Challenger ──accept──▶ Explainer ─▶ answer + evidence path + map
                    ▲                                │
                    └───── revision request ◀────────┘   at most 3 rounds; a gap still open becomes an explicit "unknown"
Shared case state: a Meterless World Model — plot, features, datasets, diplomas, rules and evidence as a typed graph
with provenance and an append log; the explanation graph is a query over it
Memory keeper (optional): earlier cases as low-weight context, each shown with its trust-ledger origin
```

| Role | Model / tool | Does |
|---|---|---|
| Planner | Nemotron 3 Super | reads the intent and the place, decides which relationships and layers matter, revises the plan when challenged |
| Evidence Tracer | tools (Zetaris MCP or PostGIS, grid, live IPMA, geocoder) + Nemotron 3.5 Lightning for extraction | fetches the evidence for each relationship |
| Challenger | Nemotron 3.5 Lightning | tests each link claim ↔ evidence ↔ rule; accepts, rejects or asks for more evidence |
| Explainer | Nemotron 3 Super | writes the answer from accepted links only, with the evidence path and the unknowns |
| Memory keeper | Meterless H-MEM | recalls similar cases (context, never facts) and stores the case with a ledger entry |

Every sentence of the answer opens to its evidence: dataset, publisher, licence, reference date, the query that produced
it and the geometry on the map; legal constraints open the official diploma. Missing data is reported as *unknown*,
never as *free*. When a legal constraint decides the answer, the agent says so and points to the formal route — a
*Pedido de Informação Prévia* at the municipality. **It is not legal advice.**

Design: [`docs/reasoning.md`](docs/reasoning.md) · [`docs/architecture.md`](docs/architecture.md) · [`docs/ux.md`](docs/ux.md) (interface) · [`docs/manual.md`](docs/manual.md) (user manual, PT/EN).

## Data (pre-existing, declared)

Open datasets under CC BY 4.0 or equivalent, loaded into a PostGIS database for **three pilot regions** (CIM Região de
Coimbra, Cávado, municipality of Lisbon — 26 municipalities); administrative boundaries are national. What is loaded,
row counts, how to rebuild it and its limits: [`data/README.md`](data/README.md). Sources, licences and reference
dates: [`data/sources.md`](data/sources.md).

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
| `data/` | Sources, schema, views and ETL scripts for the PostGIS platform (`data/README.md`) |
| `evals/` | Golden cases (data) and, from 15 Oct, the runner and dated results |
| `docs/` | Decisions, architecture, reasoning, UX spec and user manual, sponsor fit, failure modes, lessons, window plan |
| `input_examples/`, `output_examples/` | from the window: inputs and the outputs of real, dated runs |

## Running it

_Written inside the build window._ Target:

- **Live demo:** `https://territorio.mvp.tugachain.com`, public during judging.
- **One command:** `git clone` → `cp .env.example .env` → `docker compose up` → the app, a PostGIS instance and a sample
  extract (the municipality of the main demo plot plus the areas of the golden cases).
- **Programmatic entry point:** `POST http://localhost:8000/run` and `npm run agent -- input_examples/example_1.json`
  (JSON in, JSON out, trace in `logs/trace-<run_id>.jsonl`) — the UI is not required to judge the agent.
- **Default mode runs the real agent** (needs `NVIDIA_API_KEY`; without Zetaris it uses PostGIS directly and says so).
- **`SAMPLE_MODE=true`** runs without keys or network: the same roles run on the sample extract, with deterministic
  implementations in place of the model calls (planning from the intent profile, structural challenges, template
  sentences). It works for any point or plot inside the sample, is labelled in every answer and log line, and never
  reads a stored output.

## AI and model usage

- **Models:** NVIDIA Nemotron 3 Super (Planner, Explainer) and Nemotron 3.5 Lightning (Evidence Tracer extraction,
  Challenger) through build.nvidia.com; model ids in `.env.example`.
- **Agent framework:** none — a small TypeScript loop, written inside the window.
- **Partner technology:** the table above; measured use in `docs/sponsor-fit.md`.
- **Development tools:** AI-assisted coding (Claude Code) for scaffolding, debugging and documentation. The author
  reviews and tests all code and can explain every part of it.
- **Data:** public open data, no personal data; the golden cases are real places, not synthetic.
- **Known limitations:** [`docs/failure-modes.md`](docs/failure-modes.md) and [`data/README.md`](data/README.md).

## Third-party code and licences

| Component | Licence | Use |
|---|---|---|
| PostgreSQL / PostGIS | PostgreSQL Licence / GPL-2.0-or-later | database, used as a service |
| GDAL/OGR | MIT | ETL (`ogr2ogr`, `gdal*` in `data/etl/`) |
| MapLibre GL JS | BSD-3-Clause | map (from the window) |
| Meterless agent engines (World Model, H-MEM) | as published by Meterless (H-MEM reference: Apache-2.0) | shared case state and memory (from the window; any copied code under `third_party/` with its licence and notice) |

Updated as dependencies are added; substantially adapted code is noted in the file header.

## Licence

Code: Apache-2.0 (see `LICENSE`). Data: each dataset keeps its own licence, listed in `data/sources.md`.

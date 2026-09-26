# Território Explicado — *Territory, Explained*

> **Status: pre-build.** Entry for the [Open Agent Hackathon 2026](https://hackathon.genai.works/event/open-agent-hackathon-2026)
> (GenAI.Works, build window 15–20 October 2026, track **The Agent That Can Explain Why**).
> The agent itself is written **inside the build window**. What exists here before 15 October is the
> data platform, the evaluation cases and the documentation, all declared in [`PRE-EXISTING.md`](PRE-EXISTING.md).

## The problem

Answering a simple territorial question in Portugal — *"can I build here?"*, *"what risks does this plot
have?"*, *"what am I actually buying?"* — means visiting five or six institutions (DGT, ICNF, APA, INE,
IPMA, the municipality), each with its own portal, format, coordinate system and update cycle. Citizens,
buyers, insurers and small municipal teams do it by hand, badly, or not at all.

## What the agent does

Given an address or coordinate plus a question, the agent **investigates fragmented open geodata**,
reasons over the relationships between layers (administrative unit → land cover → fire hazard → flood
zone → census context → today's fire risk) and returns an answer where **every claim is tied to its
evidence**: dataset, publisher, licence, reference date, the exact SQL that produced it and the
intersected geometry drawn on a map. It says explicitly what it does **not** know.

```
question + place ──▶ plan ──▶ discover data (MCP) ──▶ query & intersect ──▶ verify ──▶ answer + evidence + map
                                    ▲                                              │
                                    └──────────── memory of previous cases ◀───────┘
```

## Data (pre-existing, declared)

Open datasets under CC BY 4.0 or equivalent, loaded into a PostGIS database for **three pilot regions**
(CIM Região de Coimbra, Cávado, municipality of Lisbon); administrative boundaries are national.
Sources, licences and reference dates: [`data/sources.md`](data/sources.md). Load scripts: [`data/etl/`](data/etl/).

## Sponsor technology (planned use)

| Layer | Technology | Role in this project |
|---|---|---|
| Data | **Zetaris** (MCP endpoint over federated sources) | discovery, governed SQL and lineage across PostGIS + REST/CSV sources |
| Token | **NVIDIA Nemotron** via build.nvidia.com | reasoning router: large model plans, small model extracts/verifies; cost and latency measured in evals |
| Orchestration | **Meterless H-MEM** (reference implementation) | memory of previous cases with a trust ledger that audits where each recalled fact came from |

Details and honest limits: [`docs/sponsor-fit.md`](docs/sponsor-fit.md).

## Repository layout

| Path | Purpose |
|---|---|
| `PRE-EXISTING.md` | What existed before the build window and why it is allowed |
| `data/` | Sources, schema, views and ETL scripts for the PostGIS platform |
| `evals/` | Golden cases (data) and, from 15 Oct, the runner and dated results |
| `docs/` | Decisions, architecture, sponsor fit, failure modes, lessons |

## Running it

_To be written inside the build window. Target: `git clone` → `cp .env.example .env` → `docker compose up`
brings up the app, a PostGIS instance and a sample dataset for one municipality._

## Licence

Code: Apache-2.0 (see `LICENSE`). Data: each dataset keeps its own licence, listed in `data/sources.md`.

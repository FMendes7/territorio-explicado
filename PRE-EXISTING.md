# Pre-existing components (declaration)

The Open Agent Hackathon 2026 rules (section 4 and 5) say that work committed before the build window
(15 Oct 2026 00:00 UTC) is not eligible **except for clearly declared pre-existing components**, and
that pre-existing product code must be declared in the submission form. This file is that declaration,
kept current until submission.

## Declared as pre-existing (built before 15 Oct 2026)

| Component | What it is | Why it is not "the agent" |
|---|---|---|
| PostGIS data platform (`data/schema.sql`, `data/views.sql`, `data/etl/*`) | Open datasets (DGT, ICNF, APA, INE) downloaded, clipped to three pilot regions and loaded into PostGIS, with a `dataset_meta` provenance table | Data preparation. The agent could run against any other database with the same schema |
| Accounts and connections | NVIDIA build API key, Zetaris Cloud cluster with the PostGIS source registered and a semantic layer built, Meterless H-MEM reference vendored | Configuration of sponsor technology, done so the window is spent on the agent |
| Golden evaluation cases (`evals/cases/*.jsonl`) | Places, questions and expected facts, validated by hand | Test data, not code |
| Documentation (`docs/*.md`, `README.md`) | Architecture, decisions, lessons from a private rehearsal | Text |

## Explicitly NOT pre-existing (written inside the window)

Agent loop, tool definitions, MCP client wiring, LLM router, evidence schema, API, web UI, evaluation
runner, logs, Docker packaging, demo video.

## Rehearsal

Before the window a **private, throwaway prototype** was built to learn the sponsor stack and to find
failure modes early. **No file from it is copied into this repository.** Whatever was learned is written
down in `docs/lessons.md`. If, during the window, any file is copied verbatim from the rehearsal, it will
be listed here with its path.

_Last updated: 2026-09-26._

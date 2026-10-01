# Submission form — draft (final text on Mon 19 Oct; fields marked *(window)* are filled from real results)

Hard deadline **Wed 21 Oct 00:45 Lisbon** (Tue 20 23:45 UTC); target **Mon 19 by 22:00**, before judging opens (Tue 20
01:00). Ties are broken by Impact, then by submission timestamp. The submission can be updated until the deadline
(HackOS FAQ); the form's availability is announced in HackOS Announcements.

HackOS asks for: project name, description, team members, selected track; links to the GitHub repository, the live demo
and Google Drive where relevant; an uploaded short demo video; the problem, solution, technologies used and sponsor
technology. The Official Rules (§5–§6, re-read 2026-10-01) require: a **demo video of 1–4 minutes** showing the main
workflow, how the agent solves the challenge, its key features and **how Zetaris and Meterless are integrated**; a
**slide deck** (problem and users, solution, workflow or architecture, stack, how Zetaris and Meterless were used, what
was unique about the sponsor use, product visuals, future enhancements); the GitHub repository with a README covering
setup, usage and dependencies; **a clear explanation of how Zetaris and Meterless were integrated, how Cursor was used
during development, where NVIDIA contributes**; and the declaration of pre-existing product code. A public URL is not
required; the password-protected demo URL goes in with its access details (organizers, 1 Oct).

## Fields

- **Project name:** Território Explicado — Territory, Explained
- **Track (exactly one):** The Agent That Can Explain Why (second of the three challenge tracks on the event page) —
  selected 2026-09-27, confirmed 2026-10-01 after the organizers accepted declared pre-existing data components
  (`docs/decisions.md`, `PRE-EXISTING.md`). Selected in HackOS on Day 1.
- **Team members:** Fernando Mendes (solo)
- **One-liner (146 chars):** An agent that explains what constrains a plot in Portugal for what you want to do there,
  with every claim traced to the map, the data and the law.
- **One-liner, long form (273 chars):** Draw a plot in Portugal and say what you want to do there — build, farm, plant
  forest, go solar. The agent investigates open geodata and explains what constrains it and why: every claim traced to
  the map, the dataset and the law, every gap stated as unknown, never as free.

### Problem (≈ 80 words)

We are building an agent that helps someone about to buy or use a plot of land in Portugal understand what constrains
it for what they want to do. That depends on the municipal land-use plan (PDM), the ecological and agricultural reserves
(REN, RAN), flood and wildfire hazard, protected areas and terrain — published by five institutions in incompatible
formats. People pay consultants or guess; municipalities answer the same questions by hand. The information is public;
the explanation is not.

### Solution (≈ 110 words)

The person points at a place or draws a plot and chooses an intent. A Planner decides which relationships matter for
that intent; an Evidence Tracer queries the datasets through a governed data layer; a Challenger tests every link
between claim, evidence and rule and sends weak ones back for revision (at most three rounds — then the gap becomes an
explicit unknown); an Explainer answers in plain language, each sentence opening to its dataset, date, licence, query
and — for legal constraints — the diploma. It maps where constraints stop ("not here, but there"), never treats missing
data as free, and when the law decides, points to the municipality's formal answer (*Pedido de Informação Prévia*).

### Technologies

Node 20 + TypeScript agent roles and loop *(window)* · PostgreSQL 16 / PostGIS 3.4 data platform (pre-existing,
declared) · React + MapLibre *(window)* · Zetaris MCP data layer · NVIDIA Nemotron 3 Super (Planner, Explainer) +
Nemotron 3.5 Lightning (extraction, Challenger) · Meterless World Model (shared case state and explanation graph) + H-MEM (Memory keeper,
trust ledger — only if wired into the loop) · open data from DGT, ICNF, APA, INE, IPMA, Copernicus · AI-assisted development with Claude Code (all code
reviewed and tested by the author).

### Sponsor technology — where each is used

See `docs/sponsor-fit.md` (use, why it matters here, what was measured, limits found, what was not used).

### Links

- Repository (public): https://github.com/FMendes7/territorio-explicado
- Live demo: https://territorio.mvp.tugachain.com *(window — URL confirmed at deploy)*
- Video (≤ 3 min, uploaded to HackOS; YouTube unlisted mirror): *(window)*
- Google Drive: only if the sample extract is too large for the repository *(window)*
- Evals: `evals/results/` + summary in README *(window)*

### Failure modes found

`docs/failure-modes.md` — 21 entries before the window (data quality, geometry, legal vs technical thresholds, unknown
vs free) plus the dated section "Found inside the window", including the fallback drill *(window)*.

### Pre-existing components (rules 4 and 5)

`PRE-EXISTING.md`: the PostGIS data platform (ETL, schema, lookup functions), accounts and connections, golden cases,
intent profiles, documentation; the last pre-window commit is tagged `pre-window`. The agent roles and loop, tools,
router, evidence schema and explanation graph, UI, sample mode, evaluation runner, packaging and video are written inside
the window. A private rehearsal prototype existed; no file from it is in the repository.

### Evals (numbers) *(window)*

| Metric | Routed (Super + Lightning) | Super only |
|---|---|---|
| Task success (golden, fields set) | | |
| Evidence integrity (claims with ≥ 1 evidence) | | |
| Correct abstention (outside pilot regions) | | |
| Revision rounds / escalations per case | | |
| Median latency per case | | |
| Tokens per case | | |

## Before pressing submit

- [ ] Every link opens in a private window, off-VPN (phone on mobile data).
- [ ] `docker compose up` from a clean clone works, with keys and with an empty `.env` in `SAMPLE_MODE=true`.
- [ ] No secret in the repo, the logs, the screenshots or the video: `git log -p | grep -iE "api[_-]?key|token|password"`
      reviewed by eye.
- [ ] Outputs come from real agent runs, never from stored files; `SAMPLE_MODE` runs the same roles on the sample
      extract with deterministic stand-ins for the model calls, labelled; logs are unedited.
- [ ] The organizers' self-test runs verbatim: `docker build`/`docker run -p 8000:8000` (or the documented
      `docker compose up`), `curl -X POST http://localhost:8000/run -d @input_examples/example_1.json`, `example_2`,
      `example_3`, and again with no `.env` and `SAMPLE_MODE=true`.
- [ ] The roles interact more than once in a run (a revision round is visible in the logs of the demo cases).
- [ ] README, `sponsor-fit.md` and `PRE-EXISTING.md` claim nothing the code does not do; limitations are stated.
- [ ] `input_examples/` and `output_examples/` hold real, dated runs of more than one case.
- [ ] `PRE-EXISTING.md` dated and complete, with the organizers' answer on pre-existing code; video 1–4 min (60–240 s,
      `ffprobe`; Zetaris and Meterless shown) and its link opens logged out.
- [ ] Slide deck uploaded; the sponsor explanation (Zetaris, Meterless, Cursor, NVIDIA) filled from `docs/sponsor-fit.md`;
      the demo URL's access details in the form, never in the repository.

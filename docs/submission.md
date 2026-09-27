# Submission form — draft (final text on Mon 19 Oct; fields marked *(window)* are filled from real results)

Hard deadline **Wed 21 Oct 00:45 Lisbon** (Tue 20 23:45 UTC); target **Mon 19 by 22:00**, before judging opens (Tue 20
01:00). Ties are broken by Impact, then by submission timestamp. The submission can be updated until the deadline
(HackOS FAQ); the form's availability is announced in HackOS Announcements.

HackOS asks for: project name, description, team members, selected track; links to the GitHub repository, the live demo
and Google Drive where relevant; an uploaded short demo video; the problem, solution, technologies used and sponsor
technology. The Official Rules add a written description of the failure modes found and the declaration of
pre-existing components.

## Fields

- **Project name:** Território Explicado — Territory, Explained
- **Track (exactly one):** 3 — The Agent That Can Explain Why — **conditional:** if the organizers do not accept declared
  pre-existing code in the main tracks, the Tinkerer Track (`PRE-EXISTING.md`). Final by the end of Thu 15 Oct (UTC):
  the event-page rules allow changes until the deadline, the HackOS FAQ locks it then — the stricter one is planned.
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
Nemotron 3.5 Lightning (extraction, Challenger) · Meterless H-MEM (Memory keeper, trust ledger — only if wired into the
loop) · open data from DGT, ICNF, APA, INE, IPMA, Copernicus · AI-assisted development with Claude Code (all code
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
- [ ] Outputs come from real agent runs; replays exist only in `SAMPLE_MODE` and are labelled; logs are unedited.
- [ ] The roles interact more than once in a run (a revision round is visible in the logs of the demo cases).
- [ ] README, `sponsor-fit.md` and `PRE-EXISTING.md` claim nothing the code does not do; limitations are stated.
- [ ] `input_examples/` and `output_examples/` hold real, dated runs of more than one case.
- [ ] `PRE-EXISTING.md` dated and complete, with the organizers' answer on pre-existing code; video ≤ 180 s (`ffprobe`).

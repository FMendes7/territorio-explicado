# Submission form — draft (final text on Mon 19 Oct; fields marked *(window)* are filled from real results)

Hard deadline **Wed 21 Oct 00:45 Lisbon** (Tue 20 23:45 UTC); target **Mon 19 by 22:00**, before judging opens (Tue 20
01:00). Ties are broken by Impact, then by submission timestamp.

## Fields

- **Project name:** Território Explicado — Territory, Explained
- **Track (exactly one, primary):** 3 — The Agent That Can Explain Why
- **Team:** Fernando Mendes (solo)
- **One-liner:** An agent that answers territorial questions about a place or a plot in Portugal by investigating
  fragmented open geodata, and returns evidence-backed, map-drawn explanations — including what it does not know.

### Problem (≈ 70 words)

Deciding whether you can build, farm, plant forest or install solar panels on a plot in Portugal means consulting the
land-use plan (PDM), the ecological and agricultural reserves (REN, RAN), flood maps, fire hazard and burn history,
protected areas, terrain and prices — published by five institutions in incompatible formats. Citizens pay for
consultants or guess; municipalities answer the same questions by hand. The information is public; the explanation is not.

### Solution (≈ 90 words)

The user points at a place or draws a plot and says what they intend to do. The agent plans which evidence matters for
that intent, discovers and queries the datasets through a governed data layer, checks every claim against the evidence,
and answers in plain language: each sentence opens to its dataset, date, licence, SQL and — for legal constraints — the
diploma. It maps where constraints stop ("not here, but there"), treats missing data as unknown, never as free, and
remembers earlier cases with an audit trail.

### Technologies

Node 20 + TypeScript agent loop *(window)* · PostGIS 16 / PostGIS 3.4 data platform (pre-existing, declared) · React +
MapLibre *(window)* · Zetaris MCP data layer · NVIDIA Nemotron 3 Super (planner/composer) + Nemotron 3.5 Lightning (extractor/verifier) ·
Meterless H-MEM (memory + trust ledger) · open data from DGT, ICNF, APA, INE, IPMA, Copernicus.

### Sponsor technology — where each is used

See `docs/sponsor-fit.md` (use, why it matters here, what was measured, limits found, what was not used).

### Links

- Repository (public): https://github.com/FMendes7/territorio-explicado
- Live demo: https://territorio.mvp.tugachain.com *(window — URL confirmed at deploy)*
- Video (≤ 3 min): *(window)*
- Evals: `evals/results/` + summary in README *(window)*

### Failure modes found

`docs/failure-modes.md` — 21 entries before the window (data quality, geometry, legal vs technical thresholds, unknown
vs free) plus the dated section "Found inside the window" *(window)*.

### Pre-existing components (rule 4 / rule 5)

`PRE-EXISTING.md`: the PostGIS data platform (ETL, schema, lookup functions), accounts and connections, golden cases,
intent profiles, documentation. The agent loop, tools, router, evidence schema, UI, evaluation runner, packaging and
video are written inside the window. A private rehearsal prototype existed; no file from it is in the repository.

### Evals (numbers) *(window)*

| Metric | Routed (Super + Lightning) | Super only |
|---|---|---|
| Task success (golden, fields set) | | |
| Evidence integrity (claims with ≥ 1 evidence) | | |
| Correct abstention (outside pilot regions) | | |
| Median latency per case | | |
| Tokens per case | | |

## Before pressing submit

- [ ] Every link opens in a private window, off-VPN (phone on mobile data).
- [ ] `docker compose up` from a clean clone works (the "one command" in the README).
- [ ] No secret in the repo: `git log -p | grep -iE "api[_-]?key|token|password"` reviewed by eye.
- [ ] `PRE-EXISTING.md` dated and complete; video ≤ 180 s (`ffprobe`).

# Build-window script (15–20 Oct 2026) — hour by hour

All times Europe/Lisbon (WEST, UTC+1). Window: **Thu 15 Oct 01:00 → Wed 21 Oct 00:45** (hard). Judging opens
**Tue 20 01:00** → submit **Mon 19 by 22:00**; Tue 20 is buffer only. Solo.

**Availability is an assumption to confirm** (dossier decision §10.2 is still open): weekdays 19:00–01:00 (6 h),
Sat/Sun 09:30–01:00 with breaks (~12 h each) → ≈ 46 h. If the real number is lower, apply the cut list below in order
— never cut evals, failure modes or the video (they are 45 of the 130 points).

## What already exists (declared in PRE-EXISTING.md — do not rebuild)

PostGIS schema `open` with 20+ layers for 3 pilot regions and the lookup functions `facts_for` (point or plot, shares),
`constraints_grid` (facts per cell, no verdicts), `facts_at`; intent profiles `data/pretensoes.json` (LEGAL vs TECHNICAL
thresholds); ≥ 30 golden cases; lessons and failure modes; accounts (NVIDIA, Zetaris, H-MEM vendored) — **if F0/F2 are
done by 14 Oct**. The window builds the agent, not the data.

## Pre-flight (Wed 14 Oct, after the 17:00 onboarding) — 30 min

- [ ] `git status` clean on `main`; repo has **no `app/`** yet; `PRE-EXISTING.md` dated 14 Oct.
- [ ] `.env` on the laptop has `NVIDIA_API_KEY`, `ZETARIS_MCP_URL` + token, `PG_DSN` (read-only role) — values from Vaultwarden, never in git.
- [ ] Server DB answers: `psql "$PG_DSN_RO" -c "SELECT count(*) FROM open.facts_for('{\"type\":\"Point\",\"coordinates\":[-8.4244,40.2071]}')"`.
- [ ] Zetaris cluster **off** (starts on Thu evening); NVIDIA Super answers one prompt (403 → Nano as planner).
- [ ] Discord answers copied into `docs/lessons.md`; track 3 selected in the workspace.

## Thu 15 — skeleton and the first answer end to end (19:00–01:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–19:30 | `mvp new territorio -t node`; `app/` (Node 20 + TS + Express); first commit | server returns `/health` |
| 19:30–21:00 | tools: `geocode` (Nominatim, cached, 1 req/s), `pg.facts_for`, `pg.constraints_grid` — thin wrappers returning the evidence contract | a script prints facts for cbr-001 |
| 21:00–22:30 | agent loop v0 (plan → query → compose), bounded steps, JSONL log per step `{step, input, tool, tokens, ms}` | one question answered with raw evidence |
| 22:30–00:30 | Zetaris MCP client (`get_schema`, `run_sql`) behind the same tool interface; start the cluster, run 3 queries, stop it | same answer via Zetaris **or** decision logged to stay on `pg.*` (plan B) |
| 00:30–01:00 | commit, push, note tomorrow's first task in `docs/decisions.md` | pushed |

## Fri 16 — evidence, rules, routing (19:00–01:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–20:30 | evidence schema `{answer, claims[{text, evidence[{dataset, publisher, licence, date, sql, geom}]}], unknowns, confidence}`; composer may only write claims that cite evidence | JSON validates on 5 cases |
| 20:30–22:00 | rule engine over `pretensoes.json`: LEGAL thresholds only if `validado`, else "to confirm"; unknown (NULL) ≠ free | build intent on plot-cav-001 lists REN/RAN/PDM/flood with roles |
| 22:00–23:30 | LLM router: Super plans/composes, Nano extracts/verifies; verifier rejects unsupported claims | a planted wrong claim is rejected in the log |
| 23:30–00:30 | IPMA live tool (RCM by DICO) replacing the snapshot | live value + date in the answer |
| 00:30–01:00 | commit; `evals/run.ts` stub runs 3 cases | 3 results in `evals/results/` |

## Sat 17 — UI and the midpoint check (09:30–01:00)

| Time | Do | Done when |
|---|---|---|
| 09:30–12:30 | React + MapLibre: search box, draw a plot, intent picker; map shows each claim's geometry | a drawn plot returns an answer on the map |
| 12:30–13:00 | **Checkpoint: "if the deadline were tomorrow, what would fail?"** → write the answer in `docs/decisions.md`, re-order the rest of the plan | written |
| 14:00–17:00 | evidence panel (claim → datasets, date, licence, SQL, diploma link), step trace, unknowns block, PT/EN strings | a judge can click from a sentence to the SQL |
| 17:00–19:00 | "not here, but there": grid cells coloured by the rule engine, legend says unknown ≠ free | Santo Varão grid in < 2 s |
| 20:00–23:00 | H-MEM memory: mine each answered case, recall with trust-ledger origin shown as low-weight evidence | second Esposende query shows the recalled case and its origin |
| 23:00–01:00 | run all golden cases once; fix the worst failure; commit | first full `evals/results/<date>.json` |

## Sun 18 — evals, packaging, failure modes (09:30–01:00)

| Time | Do | Done when |
|---|---|---|
| 09:30–12:00 | `evals/run.ts` complete: task success, evidence integrity, abstention (out-00x), consistency (3×), tokens/latency; routed vs Super-only | summary table in `evals/results/README.md` |
| 12:00–14:00 | `docker compose up` from a clean clone with `data/sample/` (one municipality, dumped from `open`) | clean clone runs on the laptop in a temp dir |
| 15:00–17:00 | `docs/failure-modes.md` "Found inside the window" section; logs readable (`logs/*.jsonl` + how to read them) | ≥ 5 dated entries |
| 17:00–19:00 | public deploy (`mvp` → `territorio.mvp.tugachain.com`, auth off for judging), smoke test from the phone off-VPN | `curl -sSI` → 200 without `WWW-Authenticate` |
| 20:00–01:00 | second eval run with fixes; README numbers; freeze features at 01:00 | numbers in README |

## Mon 19 — video and submission (19:00–01:00; target: submitted by 22:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–20:30 | record the video per `docs/video.md` (live, with the pre-recorded fallback clip ready) | `ffprobe` ≤ 180 s |
| 20:30–21:30 | `docs/submission.md` → form; `docs/sponsor-fit.md` measured sections; `PRE-EXISTING.md` final | all fields filled |
| 21:30–22:00 | **submit**; screenshot the confirmation into `docs/decisions.md` | submitted (timestamp breaks ties) |
| 22:00–01:00 | only fixes that do not risk the deploy | — |

## Tue 20 — buffer (evening)

Re-submit only if strictly better (evals improved, video clearer). Nothing after 23:30. Hard close Wed 21 00:45.

## Cut list (apply in this order when behind)

1. H-MEM memory → keep a one-screen demo of `sleep --preview` + trust ledger, not wired into the loop.
2. PT/EN toggle → English UI only (the data values stay Portuguese, labelled).
3. Zetaris for every query → Zetaris for discovery + one governed query, `pg.*` for the rest (say so in sponsor-fit).
4. Grid colouring by rules → grid shows raw facts per cell.
5. Routed vs single-model comparison → single run with Super, token counts only.

Never cut: evidence on every claim, the abstention cases, evals committed, failure modes, the video, `PRE-EXISTING.md`.

## Fixed rituals

- Every block ends with a commit (timestamps matter for ties); every tool/model call logged; every eval run dated.
- Anything copied from outside the window → `PRE-EXISTING.md`, with its path.
- Morning/evening: read Discord announcements.

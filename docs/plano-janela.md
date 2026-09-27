# Build-window script (15–20 Oct 2026) — hour by hour

All times Europe/Lisbon (WEST, UTC+1). Window: **Thu 15 Oct 01:00 → Wed 21 Oct 00:45** (hard). Judging opens
**Tue 20 01:00** → submit **Mon 19 by 22:00**; Tue 20 is buffer only. Solo.

**The HackOS participant resources are binding** (read 2026-09-27, `docs/decisions.md`): agents must interact and revise
(no fixed chain presented as an agent system), the default mode runs real agent logic, a documented sample mode serves
reviewers without keys, logs match the run, README claims match the code, and the system degrades gracefully when a
service is down. Track: the binding rule on the event page (§3) allows changes until the deadline, but the HackOS FAQ
locks it at the end of Thu 15 (UTC) = **Fri 16 00:59 Lisbon** — plan on the stricter one.

**Availability is an assumption to confirm** (dossier decision §10.2 is still open): weekdays 19:00–01:00 (6 h),
Sat/Sun 09:30–01:00 with breaks (~12 h each) → ≈ 46 h. If the real number is lower, apply the cut list below in order
— never the items under "Never cut".

## What already exists (declared in PRE-EXISTING.md — do not rebuild)

PostGIS schema `open` with 20+ layers for 3 pilot regions and the lookup functions `facts_for` (point or plot, shares),
`constraints_grid` (facts per cell, no verdicts), `facts_at`; intent profiles `data/pretensoes.json` (LEGAL vs TECHNICAL
thresholds); ≥ 30 golden cases; lessons and failure modes; the NVIDIA key; Zetaris and the H-MEM reference **only if F0/F2
are done by 14 Oct** (otherwise they are window work and `PRE-EXISTING.md` says so). The window builds the agent, not the
data.

## Pre-flight (Wed 14 Oct, after the 17:00–18:30 onboarding) — 45 min

- [ ] Organizers' answers (HackOS Support / onboarding Q&A) copied into `docs/lessons.md`; **track decided** — 3, or the
      Tinkerer Track if declared pre-existing code is not accepted in the main tracks — and selected in HackOS.
- [ ] `git status` clean on `main`; no `app/` yet; `PRE-EXISTING.md` dated 14 Oct; **last commit tagged `pre-window`**
      (`git tag -a pre-window -m "last commit before the build window"`) and the tag published.
- [ ] `.env` on the laptop has `NVIDIA_API_KEY`, `ZETARIS_MCP_URL` + token, `PG_DSN` (read-only role) — values from
      Vaultwarden, never in git.
- [ ] Server DB answers: `psql "$PG_DSN_RO" -c "SELECT count(*) FROM open.facts_for('{\"type\":\"Point\",\"coordinates\":[-8.4244,40.2071]}')"`.
- [ ] Zetaris cluster **off** (starts on Thu evening); NVIDIA Super and Lightning answer a 1-token probe (403 → Lightning
      as planner; 404/410 → look the id up again).
- [ ] HackOS Announcements read (official source: submission form availability, office hours).

## Thu 15 — roles and the first answer end to end (19:00–01:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–19:30 | `mvp new territorio -t node`; `app/` (Node 20 + TS + Express) binding `0.0.0.0:8000`; `POST /run` and the CLI entry point stubbed with the JSON contract (architecture.md); first commit | `/health` and `POST /run` answer |
| 19:30–21:00 | tools with **timeouts and fallbacks** (architecture.md table): `geocode` (Nominatim, cached, 1 req/s), `pg.facts_for`, `pg.constraints_grid` — thin wrappers returning the evidence contract | a script prints facts for cbr-001; a killed DB call returns an unknown, not a crash |
| 21:00–22:30 | agent loop v0 **with roles** on a shared case state: Intake → Planner → Tracer → Challenger → Explainer, **one revision path** (Challenger → Planner) and the 3-round limit; JSONL log per hand-off in `logs/trace-<run_id>.jsonl` with the policy fields (`agent_name`, `action`, `input_summary`, `output_summary`, `target_agent`, `model`, `confidence`, `status`, `retry_count`) + `tool`, `tokens`, `ms`, and a readable line on stdout | one question answered; the log shows a revision request and its outcome |
| 22:30–00:30 | Zetaris MCP client (`get_schema`, `run_sql`) behind the same tool interface; start the cluster, run 3 queries, stop it | same answer via Zetaris **or** decision logged to stay on `pg.*` (plan B) |
| 00:30–00:59 | **track final in HackOS before 00:59** (end of Day 1 UTC); commit, push, next task in `docs/decisions.md` | pushed; track as decided |

## Fri 16 — evidence, graph, rules, routing (19:00–01:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–20:30 | evidence schema `{answer, claims[{text, evidence[…]}], graph, unknowns, revisions, confidence}` + **explanation graph** (conclusion ← link ← rule ← evidence ← dataset, Challenger verdict per link) | JSON validates on 5 cases; the graph has a node per accepted link |
| 20:30–22:00 | rule engine over `pretensoes.json`: LEGAL thresholds only if `validado`, else "to confirm"; unknown (NULL) ≠ free; LEGAL-decisive → PIP next step | build intent on plot-cav-001 lists REN/RAN/PDM/flood with roles and the PIP line |
| 22:00–23:30 | router: Super plans/explains, Lightning extracts/challenges; the Challenger rejects unsupported claims **and requests revisions**; after 3 rounds the gap escalates to an unknown | a planted wrong claim is rejected, and a missing blocking layer triggers a revision, both in the log |
| 23:30–00:30 | IPMA live tool (RCM by DICO) with timeout and the dated snapshot as fallback | live value + date in the answer; with IPMA blocked, the snapshot and its date |
| 00:30–01:00 | commit; `evals/run.ts` stub runs 3 cases | 3 results in `evals/results/` |

## Sat 17 — UI and the midpoint check (09:30–01:00)

| Time | Do | Done when |
|---|---|---|
| 09:30–12:30 | React + MapLibre: search box, draw a plot, intent picker; map shows each claim's geometry | a drawn plot returns an answer on the map |
| 12:30–13:00 | **Checkpoint (HackOS mid-build check-in): "if the deadline were tomorrow, what would fail?"** — roles and loop working, sponsor tech connected, logs on, first input/output examples → answer in `docs/decisions.md`, re-order the rest | written |
| 14:00–17:00 | evidence panel (claim → datasets, date, licence, SQL, diploma link) + **explanation-graph view** + step trace by role + unknowns with reasons; PT/EN strings | a judge can click from a sentence to the SQL and to the diploma |
| 17:00–19:00 | "not here, but there": grid cells coloured by the rule engine, legend says unknown ≠ free | Santo Varão grid in < 2 s |
| 20:00–23:00 | H-MEM as **Memory keeper**: the recall before planning changes the Planner's first plan (a similar coastal case → check REN and flood first), shown with its trust-ledger origin; store after the answer | the second Esposende query starts from the recalled plan — **or** cut list item 1 |
| 23:00–01:00 | run all golden cases once; fix the worst failure; commit | first full `evals/results/<date>.json` |

## Sun 18 — evals, reproducibility, failure modes (09:30–01:00)

| Time | Do | Done when |
|---|---|---|
| 09:30–12:00 | `evals/run.ts` complete: task success, evidence integrity, abstention (out-00x), consistency (3×), revision rounds and escalations per case, tokens/latency; routed vs Super-only | summary table in `evals/results/README.md` |
| 12:00–14:00 | **sample mode + clean clone:** `data/sample/` (the main demo municipality + golden-case areas, dumped from `open`, target < 50 MB); `SAMPLE_MODE=true` runs the same roles with deterministic implementations of the model calls (architecture.md), on any plot inside the sample; `docker compose up` from a clean clone with keys and with an empty `.env` | both runs work in a temp dir |
| 14:00–15:00 | **fallback drill:** block Zetaris, IPMA, Nominatim and the Lightning model one at a time → the answer degrades and says why | 4 dated entries in `docs/failure-modes.md` |
| 15:00–17:00 | `docs/failure-modes.md` "Found inside the window"; `input_examples/example_1..3.json` (+ one per golden case) and matching `output_examples/` from real, dated runs; logs readable (`logs/*.jsonl` + how to read them) | ≥ 5 dated entries; examples committed |
| 17:00–19:00 | public deploy (`mvp` → `territorio.mvp.tugachain.com`, auth off for judging), smoke test from the phone off-VPN | `curl -sSI` → 200 without `WWW-Authenticate` |
| 20:00–01:00 | second eval run with fixes; README numbers, "AI and model usage" and "Third-party code and licences" completed; **claims check:** every sentence in README, `sponsor-fit.md` and `PRE-EXISTING.md` matches the code; freeze features at 01:00 | numbers in README; claims check done |

## Mon 19 — video and submission (19:00–01:00; target: submitted by 22:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–20:30 | record the video per `docs/video.md` — including a plot drawn live outside the golden set (live, with the pre-recorded fallback clip ready) | `ffprobe` 120–180 s |
| 20:30–21:30 | `docs/submission.md` → HackOS form; upload the video; `docs/sponsor-fit.md` measured sections; `PRE-EXISTING.md` final | all fields filled |
| 21:30–22:00 | **submit**; screenshot the confirmation into `docs/decisions.md` | submitted (timestamp breaks ties) |
| 22:00–01:00 | only fixes that do not risk the deploy | — |

## Tue 20 — buffer (evening)

Judging is already open. Re-submit only if strictly better (evals improved, video clearer); the FAQ allows updates up to
the deadline. Nothing after 23:30. Hard close Wed 21 00:45. From Tue 20 to Fri 30: watch HackOS Announcements for
clarification requests from the judges.

## Cut list (apply in this order when behind)

1. H-MEM memory → **remove it** from README, `sponsor-fit.md` and the video rather than show a demo not wired into the
   loop (judges discount sponsor technology "bolted on at the end").
2. PT/EN toggle → English UI only (the data values stay Portuguese, labelled).
3. Zetaris for every query → Zetaris for discovery + one governed query, `pg.*` for the rest (say so in sponsor-fit).
4. Grid colouring by rules → grid shows raw facts per cell.
5. Explanation-graph view in the UI → the graph stays in the answer JSON and the evidence panel.
6. Routed vs single-model comparison → single run with Super, token counts only.

Never cut: the revision loop (roles that interact more than once), evidence on every claim, the abstention cases,
sample mode, structured logs, evals committed, failure modes, the video, `PRE-EXISTING.md`, README claims that match
the code.

## Fixed rituals

- Every block ends with a commit (timestamps matter for ties); every tool/model call logged; every eval run dated.
- Logs are never edited; sample-mode runs are always labelled as such; nothing is read from `output_examples/`.
- Anything copied from outside the window → `PRE-EXISTING.md`, with its path.
- Morning/evening: HackOS Announcements (official source) and the track room; Discord is community only.

# Build-window script (15–20 Oct 2026) — hour by hour

**Status: proposal of 2026-09-30, rewritten for site selection as the core (`docs/site-selection.md` §8). The author
approves it or changes it by 12 Oct; until then the previous plan (plot mode as the core) is in git history.**

All times Europe/Lisbon (WEST, UTC+1). Window: **Thu 15 Oct 01:00 → Wed 21 Oct 00:45** (hard). Judging opens
**Tue 20 01:00** → submit **Mon 19 by 22:00**; Tue 20 is buffer only. Solo.

**The HackOS participant resources are binding** (read 2026-09-27, `docs/decisions.md`): agents must interact and revise
(no fixed chain presented as an agent system), the default mode runs real agent logic, a documented sample mode serves
reviewers without keys, logs match the run, README claims match the code, and the system degrades gracefully when a
service is down. **The event-page rules re-read on 1 Oct are binding too** (`docs/decisions.md`, 2026-10-01): every
submission integrates **Zetaris and Meterless**, the code is developed in **Cursor**, NVIDIA where it contributes; the
submission adds a **slide deck** and a written account of how Zetaris, Meterless, Cursor and NVIDIA were used; video
1–4 min; no bonus points. Track **The Agent That Can Explain Why**, confirmed 1 Oct (pre-existing data components
accepted); §3 allows a change until the deadline, the HackOS FAQ locks it at the end of Thu 15 (UTC) = **Fri 16 00:59
Lisbon** — it is selected on Day 1 either way.

**Availability is an assumption to confirm** (dossier decision §10.2 is still open): weekdays 19:00–01:00 (6 h),
Sat/Sun 09:30–01:00 with breaks (~12 h each) → ≈ 46 h. If the real number is lower, apply the cut list below in order
— never the items under "Never cut".

## The product in one line

"What do you want to build, and where?" → a coverage line → the **three best candidate zones** on the map, each with
pros, cons, the LEGAL procedures it would trigger, what could not be assessed and its explanation graph → a why-not
layer whose every excluded cell names its rule. "Evaluate a place" (the plot mode) is the secondary button and the
deep-dive of each candidate.

## What already exists (declared in PRE-EXISTING.md — do not rebuild)

PostGIS schema `open` for **4 regions** (Coimbra, Cávado, Lisboa, and `lisboa_tejo`: the 29 other municipalities of the
Lisbon study area, 7 512 km² with Lisboa) — Tier 1 layers plus the 10 m relief from the DGT LiDAR 2024 terrain model;
Tier 2 (easements, networks, grid capacity, facilities, noise) **only if loaded by 14 Oct with the author's OK**. The
lookup functions `facts_for` / `facts_at` / `constraints_grid`; `data/pretensoes.json` (plot intents) and
`data/site_profiles.json` (15 requirement primitives, 7 type profiles, every threshold LEGAL or TECHNICAL);
golden cases for both modes (`evals/cases/golden.jsonl`, `evals/cases/site_golden.jsonl`); lessons and failure modes; the
NVIDIA key; Zetaris and the H-MEM reference **only if F0/F2 are done by 14 Oct**. The window builds the agent and the
site engine, not the data.

**Not pre-existing, built inside the window:** the screening grid and its cache, cell verdicts, footprint fit, zones and
ranking, the agent roles, the API, the UI, any new SQL function, the eval runner.

## Where the ≈ 46 h go (summed from the schedule below — estimate)

| Block | h |
|---|---|
| Site engine: profile + coverage, screening grid + cache, cell verdicts + why-not, footprint fit, zones + Pareto ranking (Thu, Fri) | 7.5 |
| Agent loop with roles and the World Model (Fri) | 2.5 |
| UI: main screen, graph + evidence panel, "Evaluate a place" (Sat) | 7 |
| Airport benchmark (Sat) | 2 |
| Zetaris / H-MEM (Sat) | 2 |
| Eval runs, sample mode, clean clone, fallback drill, failure modes, examples, second run, claims check (Fri–Sun) | 16 |
| Deploy (Sun) · video and submission (Mon) | 2 · 6 |
| Skeleton, track, checkpoint | 1.5 |

The site-specific part (engine, loop, main screen, graph, benchmark, site evals and cache) is ≈ 20 h against the
25–30 h estimated in `site-selection.md` §8: the engine blocks are the tightest in the plan. Overflow is absorbed by
cut items 2, 5 and 6, in that order — never by the "Never cut" list.

**Timing rehearsal (2026-10-01, private, declared in `PRE-EXISTING.md`):** a grid over the whole Lisbon study area
with per-cell facts and verdicts for the large-PV profile computed in ≈ 14 s at 500 m (30 045 cells) and 4 min 42 s at
100 m (751 251 cells) on the laptop — the screening is not the risk. The risks it surfaced: the generic binding of
`site_profiles.json` rules to facts, shares (not centroids) at airport scale, footprint fit (not rehearsed), and the
product question of the 21 % of cells that are unknown only because REN is not published in 12 municipalities
(`docs/failure-modes.md` 21). Estimate (I): grid + verdicts ≈ 2–3 h of the 7.5 h engine block.

## Pre-flight (Wed 14 Oct, after the 17:00–18:30 onboarding) — 45 min

- [ ] Organizers' answers still open (Zetaris access and push-down, NVIDIA credits — HackOS / onboarding Q&A) copied
      into `docs/lessons.md`; **track** The Agent That Can Explain Why (confirmed 1 Oct) selected in HackOS.
- [ ] **Cursor** installed and signed in on the laptop, the repository opened there, a test commit made from it — the
      window's code is written in Cursor (rules §5) and §6 asks how it was used: note the features used, per day, in
      `docs/sponsor-fit.md`.
- [ ] `git status` clean on `main`; no `app/` yet; `PRE-EXISTING.md` dated 14 Oct; **last commit tagged `pre-window`**
      (`git tag -a pre-window -m "last commit before the build window"`) and the tag published.
- [ ] `.env` on the laptop has `NVIDIA_API_KEY`, `ZETARIS_MCP_URL` + token, `PG_DSN` (read-only role) — values from
      Vaultwarden, never in git.
- [ ] Server DB answers for the new region: `facts_for` on the Samora Correia probe (`site-lx-005`) returns the RNET
      and Natura rows; counts equal to the local database.
- [ ] Zetaris cluster **off** (starts on Thu evening); NVIDIA Super and Lightning answer a 1-token probe (403 → Lightning
      as planner; 404/410 → look the id up again).
- [ ] HackOS Announcements read (official source: submission form availability, office hours).

## Thu 15 — skeleton, tools, profile and coverage, screening grid (19:00–01:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–19:30 | `app/` (Node 20 + TS + Express) binding `0.0.0.0:8000`; `POST /run` and the CLI entry point stubbed with the JSON contract (architecture.md), now with `input.mode = site \| plot`; first commit | `/health` and `POST /run` answer |
| 19:30–20:30 | tools with **timeouts and fallbacks**: `geocode`, `pg.facts_for`, `pg.constraints_grid`, and `site.profile` (type or free text → profile from `site_profiles.json`, conditions applied) with **coverage** computed from the layer states | `site.profile("fotovoltaico_grande")` prints the coverage line of `site-lx-013` |
| 20:30–23:30 | **screening grid**: cells over the study area (500 m everywhere; 100 m only inside admissible 500 m cells for footprints < 100 ha), per-cell facts from the loaded layers (grid helpers), cached per study area and layer set | airport grid (~30 000 cells) built once and read back from the cache in < 1 s |
| 23:30–00:30 | **cell verdicts**: exclusion → `excluded` + rule id; missing blocking layer → `unknown`; LEGAL → flagged with regime + procedure; TECHNICAL → score 0–3 | the 7 probe cells of `site_golden.jsonl` give the expected exclude / procedure / positive / unknown |
| 00:30–00:59 | **track final in HackOS before 00:59** (end of Day 1 UTC); commit, push, next task in `docs/decisions.md` | pushed; track as decided |

## Fri 16 — footprint, zones, ranking, the loop (19:00–01:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–20:30 | **footprint fit** on a rasterised mask (rectangle, 4 orientations; ≥ 95 % admissible); footprint indicators (hectares per LEGAL regime, residents under the surfaces as a named proxy, elevation range, distance to access) | airport and 30 ha PV footprints placed over the Lisbon study area |
| 20:30–21:30 | **zones + Pareto ranking**: merge footprints into zones; layer 1 = fewest LEGAL regimes / hectares, layer 2 = TECHNICAL scores; trade-off sentences, no weighted sum | top 3 with a stated trade-off between them |
| 21:30–00:00 | agent loop v0 **with roles** on a shared case state (World Model, `logs/world-<run_id>.jsonl`): Intake → Planner (profile, coverage, calls the screening tool) → Evidence Tracer (`facts_for(zone polygon)` per candidate) → Challenger (checks every pro/con and **samples excluded cells**, verifying the stated rule against the evidence) → Explainer; **one revision path** (Challenger → Planner), 3-round limit; JSONL log per hand-off with the policy fields | one site request answered; the log shows a revision request and its outcome |
| 00:00–01:00 | commit; `evals/run.ts` stub runs `site-lx-004`…`006` and one plot case | 4 results in `evals/results/` |

## Sat 17 — UI and the midpoint check (09:30–01:00)

| Time | Do | Done when |
|---|---|---|
| 09:30–12:30 | React + MapLibre **main screen**: request box (type or free text, conditions), coverage line, map with 3 candidates + why-not layer (cell → rule id), a card per candidate (pros, cons, procedures, unknowns) | a PV request returns 3 candidates on the map |
| 12:30–13:00 | **Checkpoint (HackOS mid-build check-in): "if the deadline were tomorrow, what would fail?"** — roles and loop working, sponsor tech connected, logs on, first input/output examples → answer in `docs/decisions.md`, re-order the rest | written |
| 14:00–16:00 | explanation-graph view per candidate + evidence panel (claim → datasets, date, licence, SQL, diploma link); PT/EN strings | a judge can click from a con to the SQL and the diploma |
| 16:00–18:00 | **"Evaluate a place"**: click/draw a plot or open a candidate → the plot loop with `pretensoes.json` (LEGAL only if `validado`, else "to confirm"; unknown ≠ free) | a candidate opens as a plot with its cards |
| 18:00–20:00 | **airport benchmark**: the same rules score the CTI options (reference geometries, if digitised pre-window); recall, reasons, honesty checks of `site-lx-001`…`003` | benchmark table in `evals/results/` with agreements and disagreements, each disagreement naming the missing data |
| 20:30–22:30 | Zetaris MCP client (`get_schema`, `run_sql`) behind the same tool interface — discovery + one governed query; H-MEM as Memory keeper **or** cut list item 1 | same answer via Zetaris or plan B logged |
| 22:30–01:00 | run all golden cases once (both files); fix the worst failure; commit | first full `evals/results/<date>.json` |

## Sun 18 — evals, reproducibility, failure modes (09:30–01:00)

| Time | Do | Done when |
|---|---|---|
| 09:30–11:30 | `evals/run.ts` complete: task success, evidence integrity, abstention (`out-00x`, `site-lx-012`), "cannot assess" (`site-lx-011`), coverage, consistency (3×), revision rounds, tokens/latency | summary table in `evals/results/README.md` |
| 11:30–14:00 | **sample mode + clean clone:** `data/sample/` = the cached screening grid of the Lisbon study area (~10–15 MB) + layers clipped to the CTI option footprints, the top zones and the golden-case areas (< 50 MB); `SAMPLE_MODE=true` runs the same roles with deterministic model stand-ins; `docker compose up` from a clean clone with keys and with an empty `.env` | both runs work in a temp dir |
| 14:00–15:00 | **fallback drill:** block Zetaris, IPMA, Nominatim and the Lightning model one at a time → the answer degrades and says why | 4 dated entries in `docs/failure-modes.md` |
| 15:00–17:00 | `docs/failure-modes.md` "Found inside the window"; `input_examples/` + `output_examples/` from real, dated runs (at least: airport, PV, data centre, one plot) | examples committed |
| 17:00–19:00 | public deploy (`mvp` → `territorio.mvp.tugachain.com`, auth off for judging), smoke test from the phone off-VPN | `curl -sSI` → 200 without `WWW-Authenticate` |
| 20:00–01:00 | second eval run with fixes; README numbers, "AI and model usage" and "Third-party code and licences"; **claims check**: every sentence in README, `sponsor-fit.md` and `PRE-EXISTING.md` matches the code; freeze features at 01:00 | numbers in README; claims check done |

## Mon 19 — video and submission (19:00–01:00; target: submitted by 22:00)

| Time | Do | Done when |
|---|---|---|
| 19:00–20:15 | record the video per `docs/video.md`: the airport benchmark, a PV request run live (with the pre-recorded fallback clip ready), the data centre "cannot assess", one candidate opened as a plot; Zetaris and Meterless named on screen | `ffprobe` 60–240 s (§6: 1–4 min; target ≈ 170 s) |
| 20:15–21:00 | **slide deck** (§6): the skeleton written before the window + the window's screenshots, eval numbers and the sponsor-use slide (Zetaris, Meterless, Cursor, NVIDIA) | deck exported, every number from `evals/results/` |
| 21:00–21:40 | `docs/submission.md` → HackOS form (incl. the sponsor-use explanation and the demo URL's access details); upload video and deck; `docs/sponsor-fit.md` measured sections; `PRE-EXISTING.md` final | all fields filled |
| 21:40–22:00 | **submit**; screenshot the confirmation into `docs/decisions.md` | submitted (timestamp breaks ties) |
| 22:00–01:00 | only fixes that do not risk the deploy | — |

## Tue 20 — buffer (evening)

Judging is already open. Re-submit only if strictly better (evals improved, video clearer); the FAQ allows updates up to
the deadline. Nothing after 23:30. Hard close Wed 21 00:45. From Tue 20 to Fri 30: watch HackOS Announcements for
clarification requests from the judges.

## Cut list (apply in this order when behind)

1. H-MEM memory → **remove it** from README, `sponsor-fit.md` and the video rather than show a demo not wired into the
   loop; the World Model stays.
2. High-speed rail corridor → not built (it needs a corridor engine); stays in `site-selection.md` as post-hackathon.
3. PT/EN toggle → English UI only (the data values stay Portuguese, labelled).
4. Zetaris for every query → Zetaris for discovery + one governed query, `pg.*` for the rest (say so in sponsor-fit).
5. Footprint orientations → N–S and E–W only; 100 m refinement → 500 m only for every type (say so).
6. Plot rule engine over `pretensoes.json` → "Evaluate a place" shows the facts and cards without intent verdicts.
7. Explanation-graph view in the UI → the graph stays in the answer JSON and the evidence panel.
8. Routed vs single-model comparison → single run with Super, token counts only.

**Never cut:** coverage first; unknown ≠ free; the why-not layer with a checkable rule id per excluded cell; three
candidates with pros, cons, procedures and unknowns; the airport benchmark (recall + reasons at least); the revision
loop (roles that interact more than once); the World Model (shared state and explanation graph); evidence on every
claim; the abstention and "cannot assess" cases; sample mode; structured logs; evals committed; failure modes; the
video; the slide deck; `PRE-EXISTING.md`; README claims that match the code; **Zetaris in the agent's path (discovery + at
least one governed query) and the Meterless World Model — both required by the rules (§5)**; development in Cursor.

## Before 14 Oct (data and docs only — each item needs its own OK where marked)

| Item | By | Needs |
|---|---|---|
| Tier 2 layers for the Lisbon study area | 2 Oct target | author's OK |
| LEGAL thresholds of `site_profiles.json` and `pretensoes.json` validated | 8 Oct | author |
| Server DB with the 4 regions (restore) | 9 Oct | author's OK at the moment |
| Site golden cases validated; REN/RAN/slope filled | 11 Oct | author |
| CTI option footprints digitised as reference data (tier 3, labelled approximate) | 11 Oct | author's OK (reuse terms of the CTI material to confirm) |
| This plan and `docs/ux.md` §0 (main screen, proposal of 30 Sep) approved; README and `docs/video.md` rewritten | 12 Oct | author |
| Cursor installed, signed in, repository opened; Zetaris + Cursor workshop (Mon 12 Oct, 23:00 Lisbon) attended or its recording noted | 12 Oct | author |
| Slide-deck skeleton (§6: problem and users, solution, architecture, stack, sponsor use, future work — text only; visuals and numbers from the window) — drafted 2026-10-01 in `docs/deck.md` | 13 Oct | author reviews |

## Fixed rituals

- Every block ends with a commit (timestamps matter for ties); every tool/model call logged; every eval run dated.
- Logs are never edited; sample-mode runs are always labelled as such; nothing is read from `output_examples/`.
- Anything copied from outside the window → `PRE-EXISTING.md`, with its path.
- Morning/evening: HackOS Announcements (official source) and the track room; Discord is community only.

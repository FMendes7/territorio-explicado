# Demo video — storyboard and script (1–4 min by the rules; target 2:50; English, screen capture + voice)

Scored under **Demo (15)** and read by every judge first. One take per scene, cut together; the live app on the
demo URL, never localhost. Target 2:50 (the rules allow 1–4 minutes, §6, re-read 2026-10-01; the extra time is not
used unless a scene needs it). §6 also asks the video to show **how Zetaris and Meterless are integrated** — both are
named on screen where they act (scenes 0:35 and 1:05). Judges discount hardcoded demo paths
and single agents presented as agent systems (HackOS, read 2026-09-27): the video shows the roles challenging each
other in the real trace, and one request typed live that is not a golden case.

**Rewritten 2026-09-30 for site selection as the core** (`docs/decisions.md`, `docs/site-selection.md`, `docs/ux.md` §0):
the video opens on "Onde construir?" — the three candidates and the why-not map — and uses the plot mode only as the
deep-dive of one candidate. The previous plot-first script is in git history. Every number below is a placeholder until
the Sun 18 run: **no number is typed by hand**; each one on screen comes from the run that is recorded.

## Scenes

| t | Scene (what is on screen) | Voice (draft) | Must show |
|---|---|---|---|
| 0:00–0:08 | Cold open on the why-not map: one hatched cell is tapped → "excluded — {rule in plain words}" → its evidence chip → the source record (dataset, publisher, date) | "Every place this agent rules out tells you why." | the why-not chain, first |
| 0:08–0:20 | A dozen publisher logos/tabs fade in: DGT, ICNF, APA, IP, E-REDES, LNEG, INE, municipalities | "Where could a solar park, a school or an airport go? In Portugal the answer is spread over a dozen institutions — and the law rarely says no: it says which procedure." | the fragmentation; LEGAL = procedure |
| 0:20–0:35 | "Onde construir?": pick *Large PV plant*, 30 ha, "near Samora Correia" (`site-lx-005`) → the **coverage line appears before anything else** ("{ok} of {n} requirements can be assessed") and expands to the missing ones with their reasons | "I say what I want and where. Before any answer, it tells me what it can and cannot assess with open data." | coverage first; not assessable ≠ fine |
| 0:35–1:05 | Step trace by role, each step written to the **Meterless World Model** (shared case state, labelled): Planner composes the profile → Evidence Tracer screens the grid (**Zetaris** `get_schema` / `run_sql`, or PostGIS, labelled) → Challenger samples excluded cells and **rejects one claim** → Planner revises → Challenger accepts; the grid fills state by state | "The Challenger checks the reasons behind the map; when one doesn't hold, the Planner changes the plan — only accepted links reach the answer." | a real revision round from the log; Nemotron Super/Lightning labels per role |
| 1:05–1:35 | The **three candidate cards**: pros, cons, *procedures it would trigger* (hectares per regime, diploma chip, "to confirm" where not validated), *could not assess*; the trade-off sentence between candidates. Click one claim → evidence panel: dataset, publisher, licence, date, the query (via Zetaris) and the explanation graph read from the World Model | "Three candidates, not one score: what each gains, what it costs, which procedures it would start — and what nobody can know yet from open data." | cards; no single score; LEGAL vs TECHNICAL labels |
| 1:35–1:50 | Why-not layer toggled: the four states (excluded · legal regime · unknown · admissible) told apart by pattern + word; a **grey cell** tapped → "unknown — {layer} not published for {municipality}" | "Grey means unknown, with the reason — never free." | unknown ≠ free, with its reason |
| 1:50–2:10 | "See what constrains this position" on candidate 1 → **Avaliar um sítio** opens with the candidate as a plot: shares of the plot per constraint, the law behind each, the PIP line when a LEGAL constraint decides | "Any candidate — or any plot you draw — opens to a full explained assessment." | plot mode as the deep-dive; PIP |
| 2:10–2:30 | A request typed live that is **not** a golden case (e.g. a logistics park elsewhere in the study area); then the data-centre example: **"I don't rank candidates for this type"** with the decisive requirement that has no open data | "Not a rehearsed path. And when the decisive data isn't open, it says it can't rank — and why." | not hardcoded; honest abstention |
| 2:30–2:50 | Evals table (site and plot golden cases: coverage correct, excluded-cell reasons verified, abstentions, revision rounds, tokens, latency) → the airport benchmark line (agreement/disagreement with the published candidate sites, each disagreement naming missing data) → one failure mode → repo, `docker compose up`, `SAMPLE_MODE` | "Golden cases and evals in the repo, the failure modes written down, one command to run it — and a sample mode for reviewers without keys." | numbers, not adjectives |

## Rules for the recording

- Real answers only — no edited output; the trace on screen is the real log of that run. If a live call fails during
  recording, re-take; the fallback clip (recorded Sun 18 evening from the same build) is used only if the public deploy
  is down, and the voice says so.
- The answer text must match what the evals measure (same build, same date on screen).
- **Never on screen:** a single suitability score or percentage per candidate; "licensable" / "forbidden"; green for
  unknown; a candidate without the coverage line above it; data from a source whose licence is "not stated"
  (`data/sources.md`) — those layers stay off in the demo until confirmed.
- Say "screening, not a decision" once; say "to confirm" for any LEGAL threshold not yet validated; say "the Lisbon
  study area" (30 municipalities) — the site mode does not claim the rest of the country.
- Say "declared pre-existing" once for the data platform, and "built in the window" for the agent and the site engine.
- Captions on (judges watch muted); font ≥ 18 px; browser zoom 125 %; no personal data, no secrets, no bookmarks bar.
- Attribution visible on the map: "© OpenStreetMap contributors" whenever an OSM layer is drawn.

## Production

- Capture: OBS (1920×1080, 30 fps) or `ffmpeg -f x11grab -video_size 1920x1080 -i :0.0 -f pulse -i default out.mkv`.
- Voice: recorded separately, then `ffmpeg` mix; normalise with `loudnorm`.
- Check before upload: `ffprobe -v error -show_entries format=duration -of csv=p=0 video.mp4` between 60 and 240 (target ≈ 170); the
  link opens in a private window, logged out.
- Upload to HackOS (the submission asks for an uploaded video); YouTube unlisted as a mirror; link in
  `docs/submission.md` and README.

## Open questions (answer before Mon 19)

- Which revision round is the clearest on screen in 30 s? Pick it from the Sun 18 logs, on real outputs.
- Is the screening fast enough to show live on the public server, or does the cached grid carry it (and the voice say
  "cached")? Decide from the Sat 17 timings.
- Airport or solar park as the opening request? Solar (`site-lx-005`) is the default: the airport benchmark needs the
  CTI comparison on screen and only fits the last scene. Switch only if the airport run is clearly the stronger one.
- Is the Zetaris step fast enough to show live? If not, show it once in the trace and say where it is used.
- If H-MEM is cut (window plan, cut list), it stays out of the video and the voice.

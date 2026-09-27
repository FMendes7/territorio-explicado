# Demo video — storyboard and script (2–3 min, English, screen capture + voice)

Scored under **Demo (15)** and read by every judge first. One take per scene, cut together; the live app on the
public URL, never localhost. Target 2:50 (10 s margin under the 180 s limit). Judges discount hardcoded demo paths
and single agents presented as agent systems (HackOS, read 2026-09-27): the video shows the roles challenging each
other in the real trace, and one plot drawn live outside the golden cases.

## Scenes

| t | Scene (what is on screen) | Voice (draft) | Must show |
|---|---|---|---|
| 0:00–0:05 | Cold open: a sentence of an answer is clicked → the official diploma PDF opens on the right page | "Every sentence this agent writes can show you the law behind it." | the legal evidence chain, first |
| 0:05–0:15 | Five browser tabs: DGT, ICNF, APA, INE, a municipal PDM PDF | "In Portugal, one question about a plot of land means five institutions, five formats and a planning lawyer." | the fragmentation, in one glance |
| 0:15–0:30 | Draw a ~5 ha plot in Santo Varão (Baixo Mondego); pick the intent "farm" | "I draw the plot and say what I want to do. The agents decide which relationships matter for *that* intent." | plot + intent picker |
| 0:30–1:00 | Step trace by role: Planner → Evidence Tracer (Zetaris `get_schema` / `run_sql`) → Challenger **requests a revision** (e.g. a blocking layer without evidence) → Planner revises → Tracer → Challenger accepts; the map fills layer by layer | "The Challenger refuses a link it cannot back, the Planner changes the plan, and only accepted links reach the answer." | a real revision round from the log; Zetaris call; Nemotron Super/Lightning labels per role |
| 1:00–1:30 | Answer with shares of the plot (RAN, flood zone, slope class, land cover 1995 → 2025 — the real numbers from the Sun 18 run, none typed by hand) — click a claim → dataset, date, licence, SQL, **the diploma's PDF**; the explanation graph behind it | "Every sentence opens to its evidence: which dataset, which date, which query, which law." | claim → evidence panel → official PDF; graph |
| 1:30–1:45 | Same plot, intent switched to "solar": the conclusion changes and the explanation says why (a LEGAL limit vs a TECHNICAL rule of thumb) | "Same land, different intent, different answer — and it tells you which part is law and which is a rule of thumb." | intent → relationships → conclusion |
| 1:45–2:05 | "Not here, but there": the grid around the plot, cells coloured by the rules; hover shows the facts per cell; one grey cell opened → its reason (layer not published for that municipality) | "It also says where the constraints stop — and grey means *unknown*, with the reason, never *free*." | unknown ≠ free, with a reason |
| 2:05–2:25 | A plot drawn live elsewhere in a pilot region (not a golden case), intent "build" → answer ends with the PIP line when a LEGAL constraint decides; memory recall with its trust-ledger origin **only if H-MEM is wired** | "Any plot in the pilot regions, not a rehearsed one. When the law decides, it points to the municipality's formal answer." | not a hardcoded path; PIP; memory (conditional) |
| 2:25–2:50 | Evals table (success, evidence integrity, abstention, revision rounds, tokens, latency, routed vs single model) → one domain failure mode ("a flood hazard map is not a safety certificate") → repo, `docker compose up`, `SAMPLE_MODE` | "Golden cases, evals in the repo, failure modes written down, one command to run it — and a sample mode for reviewers without keys." | numbers, not adjectives |

## Rules for the recording

- Real answers only — no edited output; the trace on screen is the real log of that run. If a live call fails during
  recording, re-take; the fallback clip (recorded Sun 18 evening from the same build) is used only if the public deploy
  is down, and the voice says so.
- The answer text must match what the evals measure (same build, same date on screen).
- Captions on (judges watch muted); font ≥ 18 px; browser zoom 125 %; no personal data, no secrets, no bookmarks bar.
- Say "surface model" when slope appears, and "to confirm" for any LEGAL threshold not yet validated.
- Say "declared pre-existing" once for the data platform, and "built in the window" for the agent.

## Production

- Capture: OBS (1920×1080, 30 fps) or `ffmpeg -f x11grab -video_size 1920x1080 -i :0.0 -f pulse -i default out.mkv`.
- Voice: recorded separately, then `ffmpeg` mix; normalise with `loudnorm`.
- Check before upload: `ffprobe -v error -show_entries format=duration -of csv=p=0 video.mp4` between 120 and 180; the
  link opens in a private window, logged out.
- Upload to HackOS (the submission asks for an uploaded video); YouTube unlisted as a mirror; link in
  `docs/submission.md` and README.

## Open questions (answer before Mon 19)

- Which revision round is the clearest on screen in 30 s? Pick it from the Sun 18 logs, on real outputs.
- Is the Zetaris step fast enough to show live? If not, show it once in the trace and say where it is used.
- If H-MEM is cut (window plan, cut list 1), drop the memory from scene 2:05–2:25 and from the voice.

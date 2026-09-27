# Demo video — storyboard and script (≤ 3 min, English, screen capture + voice)

Scored under **Demo (15)** and read by every judge first. One take per scene, cut together; the live app on the
public URL, never localhost. Target 2:50 (10 s margin under the 180 s limit).

## Scenes

| t | Scene (what is on screen) | Voice (draft) | Must show |
|---|---|---|---|
| 0:00–0:15 | Title card → five browser tabs: DGT, ICNF, APA, INE, a municipal PDM PDF | "In Portugal, one question about a plot of land means five institutions, five formats and a planning lawyer." | the fragmentation, in one glance |
| 0:15–0:35 | Draw a ~5 ha plot in Santo Varão (Baixo Mondego); pick the intent "farm"; ask "Is this good land to farm?" | "I draw the plot and say what I want to do. The agent decides which evidence matters for *that* intent." | plot + intent picker |
| 0:35–1:20 | Step trace streams: plan → discover (Zetaris `get_schema`) → query → verify → compose; the map fills layer by layer | "It discovers the datasets through Zetaris, queries them, and each fact arrives with its source." | Zetaris call visible; Nemotron Super/Nano labels on steps |
| 1:20–1:50 | Answer with shares of the plot (RAN, flood zone, slope class, land cover 1995 → 2025 — the real numbers from the Sun 18 run, none typed by hand) — click a claim → dataset, date, licence, SQL, **the diploma's PDF** | "Every sentence opens to its evidence: which dataset, which date, which query, which law." | claim → evidence panel → official PDF |
| 1:50–2:10 | "Not here, but there": the grid around the plot, cells coloured by the rules; hover shows the facts per cell; grey cells = no data | "It also says where the constraints stop — and grey means *unknown*, never *free*." | unknown ≠ free |
| 2:10–2:30 | Second question in Esposende (Pinhal de Ofir, build intent): memory recalls the earlier coastal case, shown with its trust-ledger origin; the verifier rejects one unsupported claim in the trace | "It remembers similar cases, shows where the memory came from, and refuses claims it cannot back." | H-MEM recall + trust ledger; a rejected claim |
| 2:30–2:50 | Evals table (success, evidence integrity, abstention, tokens, latency, routed vs single model) → `docs/failure-modes.md` → repo + `docker compose up` | "Thirty golden cases, evals in the repo, failure modes documented, one command to run it." | numbers, not adjectives |

## Rules for the recording

- Real answers only — no edited output. If a live call fails during recording, re-take; the fallback clip (recorded
  Sun 18 evening from the same build) is used only if the public deploy is down, and the voice says so.
- The answer text must match what the evals measure (same build, same date on screen).
- Captions on (judges watch muted); font ≥ 18 px; browser zoom 125 %; no personal data, no bookmarks bar.
- Say "surface model" when slope appears, and "to confirm" for any LEGAL threshold not yet validated.

## Production

- Capture: OBS (1920×1080, 30 fps) or `ffmpeg -f x11grab -video_size 1920x1080 -i :0.0 -f pulse -i default out.mkv`.
- Voice: recorded separately, then `ffmpeg` mix; normalise with `loudnorm`.
- Check before upload: `ffprobe -v error -show_entries format=duration -of csv=p=0 video.mp4` ≤ 180.
- Upload: YouTube unlisted (or the platform's upload); link in `docs/submission.md` and README.

## Open questions (answer before Mon 19)

- Which case gives the clearest "explain why" in 40 s — Santo Varão (farm) or Pinhal de Ofir (build)? Decide after the
  Sun 18 eval run, on real outputs.
- Is the Zetaris step fast enough to show live? If not, show it once in the trace and say where it is used.

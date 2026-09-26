# Demo video storyboard (≤ 3 min, English, screen capture + voice)

| t | Scene | Says |
|---|---|---|
| 0:00–0:20 | Title + the problem: five portals, five formats, no answer | "In Portugal a simple question about a plot means visiting five institutions…" |
| 0:20–2:00 | Live demo: type an address in Coimbra → agent plans → discovers data through Zetaris → queries → map fills with evidence → answer with claims, each expandable to dataset/date/SQL/geometry; second query in Esposende shows memory recall with trust-ledger origin | narrate the *why* at each step |
| 2:00–2:40 | Explain-why panel: unknowns (PDM not loaded, outside regions), verifier rejecting an unsupported claim | "It says what it does not know" |
| 2:40–3:00 | Evals table (success, tokens, latency, routed vs single model), failure modes, repo + one-command run | "Open source, evals shipped, failure modes documented" |

Record with OBS or `ffmpeg -f x11grab`; check `ffprobe` duration ≤ 180 s.

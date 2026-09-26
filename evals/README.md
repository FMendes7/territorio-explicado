# Evaluations

The hackathon awards bonus points for **shipping evals**, and Impact (30) and Technical (20) are easier
to argue with numbers than with a video. This directory holds the cases now and, from 15 October, the
runner and dated results.

## Layout

```
evals/
├── cases/golden.jsonl   # one JSON object per line — a place, a question, the expected facts (pre-existing: data)
├── run.ts               # written inside the build window: runs every case against the API, writes results/
└── results/             # dated JSON + a summary table; committed
```

## Case format (`cases/golden.jsonl`)

```json
{"id":"cbr-001","region":"coimbra","name":"Paço das Escolas","lon":-8.4244,"lat":40.2071,
 "question":"What are the territorial constraints and risks at this location?",
 "expected":{"concelho":"Coimbra","freguesia":"?","land_cover":"?","fire_hazard":"?","flood_zone":"?"},
 "must_cite":["caop2025"],"status":"unvalidated","notes":""}
```

`expected` values start as `?` and are filled by querying the loaded database and **checking by hand**
(the author knows these places). `status` becomes `validated` only after that check. A case with `?`
fields is still useful: the runner scores only the fields that are set.

## What the runner measures (per case, per model configuration)

- **Task success** — every set `expected` field matched, and every `must_cite` dataset present in evidence.
- **Evidence integrity** — each claim has ≥1 evidence item with dataset, date and SQL; no claim without evidence.
- **Abstention** — for cases outside the pilot regions the agent must say it has no data, not guess.
- **Steps, tokens, latency, cost** — per run; planner vs worker model split (NVIDIA token layer).
- **Consistency** — same case 3×, same conclusion.

Runs are sequential (NVIDIA free tier ≈ 40 req/min).

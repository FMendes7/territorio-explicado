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

Optional keys: `intent` — an id from `data/pretensoes.json` (what the person wants to do; it decides which evidence
matters and the rules applied); `geometry` — a GeoJSON Polygon in WGS84 for a drawn plot (then `lon`/`lat` are absent,
the facts come from `facts_for()` with the share of the plot per value, and `expected` values may be shares, e.g.
`share_in_flood_zone`).

`expected` keys map to `facts_at()` datasets: `concelho`/`freguesia` (caop2025), `land_cover` (cos2023),
`fire_hazard` (icnf_perigosidade), `flood_zone` (apa_*), `census` (ine_bgri2021), `burned` (icnf_areas_ardidas:
years), `protected_area` (icnf_areas_protegidas: name), `pdm_class` (dgt_crus: class — category), `price_eur_m2`
(ine_precos_habitacao: parish or municipality value, level stated), `slope` (mdt_lidar2024, or cop_dem30 where the MDT has no tile: class or %), `aspect` (same sources:
compass sector or share per sector), `ren` / `ran` (dgt_ren / dgt_ran: inside · excluded · outside · not available — the
last two are different answers), `buildings` (mconst_lidar2024: on a footprint / count nearby / built share of the plot);
`tier`/`worldcover_class` for the global fallback.
`data/etl/golden_fill.sh` prints every case's facts to `cases/golden_facts_<date>.txt`; since 2026-09-28 each line
carries the fact's status `level` (hi · md · lo · na · in) before the English `value`, so a status can be validated
too (e.g. REN "na" in Condeixa-a-Nova, never "lo").
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

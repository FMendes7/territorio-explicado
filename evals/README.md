# Evaluations

The current rules (re-read 2026-10-01) no longer award bonus points for evals, but Impact (30), Technical (20)
and Demo (15) are easier to argue with numbers than with adjectives. This directory holds the cases now and, from 15 October, the
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

## Site-selection cases (`cases/site_golden.jsonl`, since 2026-09-30)

One JSON object per line for the site-selection mode (`docs/site-selection.md`) on the Lisbon study area. `profile` is a
profile id from `data/site_profiles.json`; every rule id in `expected` is a rule of that file (checked when the file is
written). `check` says what is scored:

| `check` | Pass when |
|---|---|
| `benchmark_recall` | the reference areas in `must_include_reference` fall inside the agent's `top_k` zones (airport vs the CTI options) |
| `benchmark_reason` | at the `probe`, the first failing criterion belongs to `first_failing_family` and the listed rules are named |
| `probe` | the why-not answer for the cell holding `probe` (lon/lat, WGS84) gives exactly the `exclude` rules, and names every `procedure`, `positive` and `unknown_at_tier1` rule; the `facts` agree with the layers |
| `honesty` | every `unknown_not_open` / `unknown_at_tier1` item is named as not assessed and nothing in `must_not` is said |
| `abstain` | outside the loaded regions: no ranking, says why |
| `coverage` | the answer opens with how many requirements can be assessed and names the `unknown_at_tier1` rules |
| `backtest_dgeg` *(cases to write pre-window, 2026-10-02)* | for a licensed PV park (DGEG `processo`, operating licence; UPAC and storage left out), no cell under its footprint is screened *excluded* by the PV profile; legal regimes are named with their procedure; every disagreement names the rule id and the layer |
| `counterfactual` *(window)* | for a probe that is not admissible, the "would be a candidate if" list names exactly the failing rules of the verdict, physical exclusions marked as not relaxable |

**Blind rule (2026-10-02):** reference geometries (the CTI options) are read only by the runner, after the agent has
answered; no tool of the agent can read them. A run that touched them is invalid.

`facts` were read from the loaded layers (field `checked` says when); `?` = filled after the layer is loaded, as in
`golden.jsonl`. `layers_state` records which tiers were loaded when the expected unknowns were set: after Tier 2
those lists shrink and are recomputed from `data/site_profiles.json`. `blocked_by` names what the case still needs
(e.g. the CTI reference geometries). `status` stays `unvalidated` until the author checks the case by hand.

## What the runner measures (per case, per model configuration)

- **Task success** — every set `expected` field matched, and every `must_cite` dataset present in evidence.
- **Evidence integrity** — each claim has ≥1 evidence item with dataset, date and SQL; no claim without evidence.
- **Abstention** — for cases outside the pilot regions the agent must say it has no data, not guess.
- **Steps, tokens, latency, cost** — per run; planner vs worker model split (NVIDIA token layer).
- **Consistency** — same case 3×, same conclusion.

Runs are sequential (NVIDIA free tier ≈ 40 req/min).

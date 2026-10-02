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
| `backtest_dgeg` *(cases written 2026-10-02: `cases/site_backtest_dgeg.jsonl`)* | for a licensed PV park (DGEG `processo`, operating licence; UPAC and storage left out), no cell under its footprint is screened *excluded* by the PV profile; legal regimes are named with their procedure; every disagreement names the rule id and the layer |
| `counterfactual` *(window)* | for a probe that is not admissible, the "would be a candidate if" list names exactly the failing rules of the verdict, physical exclusions marked as not relaxable |

**Blind rule (2026-10-02):** reference geometries (the CTI options) are read only by the runner, after the agent has
answered; no tool of the agent can read them. A run that touched them is invalid.

`facts` were read from the loaded layers (field `checked` says when); `?` = filled after the layer is loaded, as in
`golden.jsonl`. `layers_state` records which tiers were loaded when the expected unknowns were set: after Tier 2
those lists shrink and are recomputed from `data/site_profiles.json`. `blocked_by` names what the case still needs
(e.g. the CTI reference geometries). `status` stays `unvalidated` until the author checks the case by hand.

## DGEG backtest cases (`cases/site_backtest_dgeg.jsonl`, 2026-10-02)

One case per photovoltaic park with an **operating licence** in the DGEG register inside the study area
(`open.dgeg_centrais_solares`: `tipo_central = CS`, `subtipo_instalacao = Solar fotovoltaico`, `lic_exploracao` set —
UPAC, storage and the plants still being licensed are left out): **29 parks**. Each case references the park by
`processo` and one point; the footprint is **read from the database at run time and never copied** (the register's
terms conflict: CC BY 4.0 on dados.gov.pt vs CC BY-NC 4.0 on the service).

| `scope` | Cases | Scored on | Why |
|---|---:|---|---|
| `footprint` | 18 | the 100 m cells whose centroid lies in the footprint (4.0–133.1 ha; 3–133 cells) | the primary metric |
| `point_only` | 6 | the 100 m cell holding the point | the register gives a 5 m placeholder circle, no footprint (1.5–6.3 MVA) |
| `small` | 5 | not scored | < 100 kVA or no power, placeholder circle only: rooftop or microgeneration-size installations registered as autonomous, not parks (the 100 kVA cut is the author's to confirm) |

`expected` (scored cases): `excluded_cells: 0`; `legal_regimes` = the LEGAL rules that hit at least one cell centroid,
each to be named with its procedure (`must_name_procedure`); `unknown_not_published` = rules whose layer the source does
not publish for that municipality (REN of Coruche, Salvaterra de Magos, Chamusca, Loures) — named as not assessed,
never *excluded*; `legal_facts: ["L.aia_pv"]`; `known_disagreements` lists any disagreement already visible in the facts
(none). `facts` hold what was measured: cells per rule, exclusion-class share in COS 2018 / 2023 / 2025, COS 2025 and
2018 shares, REN, RAN, protected areas, montado, PDM class (pre-DR 15/2015 designation where the PDM is older), T100,
high / very high fire hazard, SRUP families, slope at the cells.

Measured on the local database (2026-10-02; facts, not verdicts):

- **0** cells in an exclusion class (water, salt marsh, intertidal, continuous residential fabric) under the 18 footprints
  and the 6 points, in COS 2025 **and** in COS 2018. COS 2023/2025 map most footprints as the plant itself (1.4.1.2
  solar), so COS 2018 is kept: for 13 of the 18 it is the land **before** construction (eucalyptus, pine, annual
  crops, olive grove, scrub, pasture).
- LEGAL regimes at the cell centroids of the 18 footprints: REN in 10 (up to 100 % of the footprint), montado (COS
  proxy) 4, RAN 3, aeronautical easement 3, abstraction perimeter 1 — consistent with "LEGAL means procedure, not forbidden"
  (`docs/site-selection.md` §3). Slope: 5 parks have cells above 15 % (max 29 %) — `PV.declive` scores, never excludes.
- The one *small* case whose cell falls in continuous residential fabric (`site-bt-821`, 5 kVA, COS 1.1.1.2) shows why
  the small scope is not scored: the profile is for parks, not roofs.

The cell grid and facts follow the screening the window builds (100 m cells aligned to the EPSG:3763 origin, facts at
the cell centroid, `docs/site-selection.md` §2 and §10); the measuring script lives outside this repository with the
private grid rehearsal (`PRE-EXISTING.md`). `status` stays `unvalidated` until the author checks the cases.

## What the runner measures (per case, per model configuration)

- **Task success** — every set `expected` field matched, and every `must_cite` dataset present in evidence.
- **Evidence integrity** — each claim has ≥1 evidence item with dataset, date and SQL; no claim without evidence.
- **Abstention** — for cases outside the pilot regions the agent must say it has no data, not guess.
- **Steps, tokens, latency, cost** — per run; planner vs worker model split (NVIDIA token layer).
- **Consistency** — same case 3×, same conclusion.

Runs are sequential (NVIDIA free tier ≈ 40 req/min).

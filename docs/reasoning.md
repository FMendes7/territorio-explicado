# Reasoning model — from facts to an explained assessment (design; code is written inside the window)

The data platform answers *"what touches this point?"* (`facts_at()`). The agent's job is the step after:
**combine** the facts, **derive** findings that no single layer states, **verify** each claim against evidence,
and **say what it cannot know**. This document fixes that design so the window is spent implementing it.

## 1. Agent loop — roles that challenge and revise (not a pipeline)

The HackOS judging guides (read 2026-09-27) discount linear pipelines ("Agent A → B → C") and single agents presented as
agent systems, and the AI Usage Policy treats presenting a fixed chain as something else as misrepresentation. The design
is therefore a loop over one shared case state, with distinct roles that hand work back to each other. The track-3
pattern the organizers describe — relationship mapper → evidence tracer → challenger that tests each link → tracer
strengthens or drops it → explainer — maps onto these roles.

| Role | Does | Model | Reads → writes (shared case state) |
|---|---|---|---|
| Intake | the person **chooses the intent** (pretensão, `data/pretensoes.json`: build a house, farm building, farming, forestry, solar PV, buy, risks, describe); if not chosen, the small model proposes one and asks; resolves the place — geocode, coordinates **or a drawn plot (polygon)** — and asks for a map click instead of guessing when it is ambiguous | small | intent profile, point or polygon + geocoding evidence + confidence |
| Planner (relationship mapper) | from the intent profile, lists the relationships that matter (plot ↔ PDM class, plot ↔ REN/RAN, plot ↔ flood extent, plot ↔ fire hazard and history, …) and delegates each to the Tracer; on a revision request it changes the plan | large | plan `P[]` (relationship, layers, why) |
| Evidence Tracer | runs the tools for each relationship — `facts_for(geojson)` (point → per-feature facts; plot → share of the area per value), `constraints_grid()` when the intent needs alternatives, live IPMA fire risk (by DICO) — through Zetaris or direct PG | tools + small for extraction | evidence `E[]`, unknown layers `U[]` |
| Rule engine | applies the relationship rules (§2) and the intent's LEGAL / TECHNICAL thresholds to `E[]`; every finding cites the evidence ids and the rule | deterministic | findings `F[]` with scores and refs |
| Challenger | tests each link claim ↔ evidence ↔ rule: does the cited evidence support it? contradictions? is a layer the intent marks *bloqueante* unknown here? → accept, reject, or **revision request** with a reason | small, adversarial prompt | verdict per link, revision requests `R[]` |
| Explainer | writes the answer for the intent from accepted links only: sections, per-section confidence, unknowns with reasons, next steps; builds the explanation graph | large | final answer + graph |
| Memory keeper | before planning, recalls similar earlier cases (low weight, shown with their trust-ledger origin) so the Planner can start from what mattered there; after the answer, stores the case | H-MEM | memory ids |

### 1.1 Revision loop, branching and escalation

- **Triggers for a revision request:** a claim without supporting evidence; a *bloqueante* layer unknown for this place;
  two sources that disagree (§2 consistency checks); a share too small to state without saying where it is (failure
  mode 15).
- **The Planner answers by changing the plan, never the evidence:** another layer that answers the same relationship, a
  wider grid, a live source instead of a snapshot, or a question to the person (map click, intent).
- **Bounded:** at most **3 revision rounds** per run. A gap still open after that is **escalated** to an explicit unknown
  with its reason ("REN delimitation not published for this municipality — not consulted"), never dropped silently.
- **Branching on confidence:** a low-confidence section is written as "to confirm". When a LEGAL constraint decides the
  answer, the Explainer ends with the formal route — ask the municipality for a *Pedido de Informação Prévia* (RJUE,
  art. 14.º). The agent informs; it does not license.
- **Challenger rubric, per link (0–3 each):** accuracy (the evidence supports it), appropriateness (right layer and
  threshold for this intent), actionability (the person can act on it). Below 7/9 → a revision request naming one fix.
- **Every hand-off is logged** (`agent_name`, `action`, `target_agent`, `status`, `retry_count` — architecture.md), so the
  trace a judge reads is the run that happened.

Rule: a claim without an evidence id and a Challenger's *accept* never reaches the Explainer. Memory is *context*, never
a source of facts.

### 1.2 Agent loop spec (the eight lines the organizers' learning session asks for)

1. **Goal:** explain what constrains this point or plot for this intent, with the evidence path and the unknowns.
2. **Plan (≤ 5 steps):** intake → plan the relationships → trace the evidence → challenge each link → explain.
3. **Tools (name → input → output → fail mode):** `facts_for` → GeoJSON → facts with shares → timeout: layer unknown ·
   `constraints_grid` → GeoJSON, radius, cell → facts per cell → timeout: grid omitted and said · `zetaris.run_sql` →
   SQL → rows → error: `pg.*` · `ipma.fire_risk` → DICO → index and date → down: dated snapshot · `geocode` → text →
   candidates → ambiguous or down: ask for a map click.
4. **Memory to keep:** the case state (plan, evidence, verdicts, revisions) for the run; earlier cases (H-MEM) as
   low-weight context.
5. **Rubric (0–3 × 3):** accuracy · appropriateness · actionability, per link.
6. **Stop conditions:** every link ≥ 7/9 → explain; after 3 rounds → escalate the rest to unknowns; ambiguous place →
   ask the person; a LEGAL constraint decides → point to the PIP.
7. **Run log:** one line per hand-off, stdout + `logs/trace-<run_id>.jsonl` (architecture.md).
8. **Guardrails:** ≤ 3 rounds, ≤ 20 tool calls, 120 s cap; no claim without evidence; never "free" for missing data;
   never a licensing verdict; always log why.

## 2. Relationship rules (the "conjugação")

Derived findings are scored 0–3 (none / low / medium / high) with the rule that produced them. Draft:

### Wildfire exposure
| Inputs | Rule |
|---|---|
| ICNF hazard class · COS land cover · distance to built-up COS class · burned-area history · IPMA RCM today | hazard ≥ alta **and** land cover forest/shrub → 3; hazard média → 2; hazard baixa/muito baixa → 1; `sem perigosidade` → 0. +1 if burned in the last 10 years (cap 3). Built-up within 100 m of hazard ≥ alta → flag "interface urbano-florestal". Today's RCM shown as *current condition*, not structural risk |

### Flood exposure
| Inputs | Rule |
|---|---|
| APA perigo class · inside T100 extent (+ `nivel_max`) · ARPSI · flood marks ≤ 1 km · COS residential · BGRI residents | inside T100 → ≥ 2 (3 if perigo Alto or residential with residents > 0); in ARPSI but outside T100 → 1 ("studied area, not in the 100-year extent"); flood mark ≤ 500 m → +1 (cap 3). **Outside every layer → "not mapped", score `unknown`, never 0** |

### Regulatory constraints (what a licence would hit)
| Inputs | Rule |
|---|---|
| protected areas (RNAP / Natura 2000) · REN / RAN · PDM class (where loaded) · servidões · flood/hazard classes | any protected/REN/RAN/PDM non-urban → "building unlikely without specific licensing", list which; PDM urban class → "compatible in principle, subject to PDM rules"; PDM not loaded → **explicit unknown** (this is the question people ask most) |

### Human context
| Inputs | Rule |
|---|---|
| BGRI residents, buildings, dwellings, 65+ · INE median €/m² (where available) | density class; ageing share; vacancy hint (dwellings ≫ residents); price context with the INE caveat (parish level only in large cities) |

### Consistency checks (data disagreeing with data)
- COS says urban **and** BGRI says 0 buildings → flag "layers disagree (different dates or non-residential)".
- COS forest **and** hazard `sem perigosidade` → flag; cite both dates.
- Geocoder confidence low **and** findings change within 200 m → ask for a map click instead of answering.

## 3. Answer shape

```
{ intent, place: {input, resolved, confidence},
  sections: [ {name: "Situação" | "Riscos" | "Condicionantes" | "Contexto" | "O que não sabemos",
               findings: [{text, score, rule, evidence: [ids]}], confidence} ],
  evidence: [{id, dataset, publisher, licence, reference_date, retrieved_at, sql, geom_ref}],
  unknowns: [{layer, why}], memory: [{id, origin, trust}],
  graph: {nodes, edges},              # conclusion ← link ← rule ← evidence ← dataset, Challenger verdict per link
  revisions: [{round, requested_by, reason, outcome}] }   # at most 3 rounds; escalations end as unknowns
```

## 4. Why this scores well on the rubric

- **Explain why (track 3):** every finding names its rule and evidence; the explanation graph shows conclusion ← link ←
  rule ← evidence ← dataset with the Challenger's verdict on each link; the map draws exactly those geometries.
- **Impact:** one user (someone about to buy or use a plot) and one decision (what constrains it for this intent); the
  answer is organised by the intent, not by dataset.
- **Agent design:** roles that challenge and revise each other, bounded rounds, escalation to unknown, fallbacks per
  service — not a fixed chain.
- **Failure modes:** unknowns and disagreements are first-class output, not silence.
- **Evals:** rules are deterministic → golden cases can assert scores, not just facts; revision rounds and escalations
  are counted per case.

## 5. Layer registry by tier — national precision where it exists, a global fallback everywhere

The agent never answers "no data" for a valid place. It answers with the **best available tier** and the
provenance names the tier; tiers are never mixed silently, and legal questions (zoning, protected status
with legal effect) are only answerable at tiers A/B.

| Tier | Scope | Sources | Status |
|---|---|---|---|
| **A — national, Portugal** | 3 pilot regions (CAOP national) | DGT CAOP/COS, ICNF hazard (+ burned areas, RNAP/Natura in backlog), APA PGRI, INE BGRI (+ €/m²), IPMA live; PDM where open | **loaded** |
| **B — national adapters, other countries** | per country, added one at a time | Spain first: IGN/CNIG (boundaries, BTN), SIOSE (land use), **Catastro INSPIRE WFS (parcels, open)**, MITECO SNCZI (flood zones), Natura 2000 ES; Madrid: `datos.madrid.es`, `datos.comunidad.madrid` (urban planning, noise, green areas) | design only; formats/licences to confirm |
| **C — European** | EU | Copernicus CLC+/CORINE, EFFIS (daily fire danger, burned areas), EEA Natura 2000, Eurostat GISCO NUTS/LAU (non-commercial clause) | design only |
| **D — global** | anywhere | **ESA WorldCover 10 m (proven: live pixel read from the public COG in < 1 s, no download)**, JRC Global Flood Hazard (COG per return period — URL pattern TBD), GHSL population, NASA FIRMS active fires, WDPA (non-commercial licence — flag) | WorldCover proven 2026-09-26 |

Mechanics: tier D/C rasters are read at query time with GDAL over HTTP range requests
(`gdallocationinfo -wgs84 /vsicurl/<COG> lon lat`, `GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR`), so they cost
zero storage and appear in the evidence list like any other fact (`dataset`, value, source URL, tile,
retrieved_at). The registry is a table (`layer_registry`: tier, dataset, coverage geometry or "global",
resolution, licence, how-to-query) that step 2 consults to decide what to ask; the answer's *unknowns*
list what higher tiers would have added (e.g. in Madrid: "Tier A/B zoning not connected; Spanish
Catastro/SIOSE/SNCZI exist as open data and are the next adapter").

Why it matters for the rubric: the demo can go from a Coimbra plot (tier A, legal detail) to Madrid
(tier D, physical context only) and the answer *explains the difference in what it can say*.

## 6. From an answer to a decision — capabilities added 2026-09-26 (data ready; reasoning written inside the window)

| Capability | What the person sees | Data platform (pre-existing, declared) | Agent side (inside the window) |
|---|---|---|---|
| **Point or plot** | click a point *or* draw the plot; the answer speaks in shares ("62 % of the plot is in a flood zone") | `open.facts_for(geojson)` → `facts_at` for points, `facts_in` for polygons (share_pct, area_ha, the part of the plot each value covers); census and flood marks are explicitly *not* area-weighted | rules read shares, not just presence (e.g. "a small corner in REN" ≠ "the whole plot in REN") |
| **Intent (pretensão)** | chooses what they want to do; the answer is organised by what matters for that intent | `data/pretensoes.json`: per intent the evidence, its role (bloqueante / condicionante / contexto) and thresholds typed **LEGAL** (cited, human-validated) or **TECHNICAL** (rule of thumb, said as such) | rule engine applies the profile; a LEGAL threshold whose status is not `validado` is shown as "to confirm", never as a finding |
| **Not here — but there** | a map of cells around the place: free / conditioned / blocked / unknown, and the nearest cells that clear the blockers, each with its why | `open.constraints_grid(geojson, radius, cell)`: facts per cell (worst fire class, flood extent/hazard, ARPSI, protected areas, dominant PDM class, fire years, land cover, pilot coverage); no verdicts in SQL | cell verdicts from the intent's rules; "unknown" outside the pilot regions or where a blocking layer is not loaded (REN/RAN) — never "free" |
| **Explanation graph** | a navigable graph: conclusion ← findings ← rules ← evidence ← datasets; contested claims highlighted | evidence rows already carry dataset, SQL hint and geometry; `dataset_meta` carries publisher, licence, dates | graph built from the ledger of the run; a second model tries to **refute** each claim from the same evidence (adversarial verifier); disagreements between sources become explicit nodes; export as W3C PROV (JSON-LD) |
| **Why it changed** | "pine forest until the 2017 fire, shrubland since; hazard rose" | `open.v_cos_serie` (1995 S1 · 2018 · 2023 · 2025 S2) + burned areas 1975–2025 | trajectory reasoning; across Série 1 → 2 only level-1 classes are compared |
| **Relief** | slope classes of the plot, elevation, contour lines on the map | `open.dem_elev` / `open.dem_slope` (Copernicus GLO-30 → 25 m, EPSG:3763); contours on demand with `ST_Contour` | slope thresholds per intent; the DSM bias (canopy, buildings) is always stated; DGT LiDAR 2024 MDT (2 m, true terrain) replaces it when the account exists |

Order of implementation in the window: point/plot + intent, the Challenger loop and the explanation graph (days 1–2 — they shape every answer and are the core of track 3) → alternatives map (day 3, the demo's strongest moment) → temporal and relief reasoning (day 4, data already there).

# Reasoning model — from facts to an explained assessment (design; code is written inside the window)

The data platform answers *"what touches this point?"* (`facts_at()`). The agent's job is the step after:
**combine** the facts, **derive** findings that no single layer states, **verify** each claim against evidence,
and **say what it cannot know**. This document fixes that design so the window is spent implementing it.

## 1. Pipeline (bounded steps, explicit carry-over)

| Step | Does | Model | Output carried forward |
|---|---|---|---|
| 0 Intent | classify the question: `build` / `risk` / `buy` / `describe` / other; extract place | small | intent, place text |
| 1 Locate | geocode or accept coordinates; detect ambiguity (several candidates, generic names) | — | point + geocoding evidence + confidence |
| 2 Facts | `facts_at()` through Zetaris (or direct PG), live IPMA fire risk (by DICO), memory recall (H-MEM, low weight) | — | evidence list `E[]`, unknown layers `U[]` |
| 3 Derive | apply the **relationship rules** (§2) to `E[]`; every derived finding cites the evidence ids it used | deterministic + small model for text | findings `F[]` with scores and refs |
| 4 Verify | for each finding/claim: do the cited evidence items really support it? contradictions? anything without evidence? | small | verified `F[]`, rejected list |
| 5 Compose | write the answer for the intent: sections, per-section confidence, unknowns, next steps | large | final answer |
| 6 Remember | store the case (place, findings, feedback) in H-MEM with its ledger entry | — | memory id |

Rule: a claim without an evidence id never reaches step 5. Memory is *context*, never a source of facts.

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
  unknowns: [{layer, why}], memory: [{id, origin, trust}] }
```

## 4. Why this scores well on the rubric

- **Explain why:** every finding names its rule and evidence; the map draws exactly those geometries.
- **Impact:** the answer is organised by the question asked (build / risk / buy), not by dataset.
- **Failure modes:** unknowns and disagreements are first-class output, not silence.
- **Evals:** rules are deterministic → golden cases can assert scores, not just facts.

# Site selection — "where could this go?" (design only; nothing here is built)

**Status (2026-09-30):** design note. No code, no SQL function and no data load exists for this mode yet. The data
listed in §6 is a *plan*; each load needs the author's go-ahead (disk and time). Anything built from this note is
window work (15–20 Oct) and appears in `PRE-EXISTING.md` only as this document.

## 1. The inverse question

Today the agent answers **"what constrains this plot for what I want to do?"** — a place in, an explained assessment
out (`reasoning.md`). Site selection asks the inverse: **"I want to build X under conditions Y — where in this region,
and why there and not elsewhere?"** The output is a short ranked list of **zones**, each with its explanation graph,
plus a map that says *why not* for everything that was left out.

It is the same reasoning run the other way round, so it reuses what exists:

| Piece | Plot mode (today's design) | Site mode (this note) |
|---|---|---|
| Intent | `data/pretensoes.json` profile | same file, plus a **site profile**: footprint, hard exclusions, weights |
| Facts | `facts_for(geojson)` on one plot; `constraints_grid` ≤ 3 km around it | the same facts, per cell, over a whole study area (tens of thousands of cells) |
| Rules | LEGAL (validated → stated; else "to confirm") vs TECHNICAL | same split, plus **hard exclusions** (physical infeasibility) |
| Output | one assessment + "not here, but there" nearby | top zones + why-not map; each zone then goes through the normal plot loop |
| Explain | conclusion ← link ← rule ← evidence ← dataset | zone ← criterion ← rule ← evidence ← dataset; every excluded cell keeps the id of the rule that excluded it |

## 2. Pipeline

1. **Intake → site profile.** The person picks a type (airport, large PV plant, logistics park, data centre, public
   facility) and sets conditions (size, max distance to a place, "avoid cork-oak montado", …). The profile fixes the
   footprint (shape, area, allowed orientations), the cell size, the hard exclusions, the LEGAL regimes to report and
   the TECHNICAL criteria with thresholds and weights. Every value names its source and status (`proposta` /
   `validado`), exactly like the plot-mode thresholds.
2. **Screening grid.** Square cells over the study area (cell size from the footprint: 500 m for an airport,
   50–100 m for a PV plant). Per cell: the facts `constraints_grid` already returns (fire hazard, flood extent, protected
   areas, PDM class, REN/RAN, land cover, slope, buildings, pilot coverage) plus the site-specific layers of §6. Facts
   only — no verdicts in SQL, as today. Computed once per study area and cached (a 7 500 km² area at 500 m is ~30 000
   cells; `constraints_grid` is capped at 2 500 cells / 3 km radius on purpose and is not the tool for this).
3. **Cell verdicts.** Hard exclusion (e.g. open water, continuous urban fabric) → `excluded`, with the rule id.
   Unknown blocking layer → `unknown`, never suitable (unknown ≠ free). LEGAL regimes → *flagged with the regime and the
   procedure it triggers*, not excluded (see §3). TECHNICAL criteria → score 0–3 per criterion.
4. **Footprint fit.** Slide the footprint (rectangle, several orientations) over the admissible cells; keep positions
   where ≥ 95 % of the footprint is admissible; compute footprint-level indicators (hectares in each LEGAL regime,
   population under the approach/take-off surfaces, elevation range along the runway axis, distance to access, wind
   usability for that orientation).
5. **Zones and ranking.** Merge overlapping footprints into zones. Rank by **Pareto layers**, not one weighted sum:
   first "fewest LEGAL regimes touched / fewest hectares under them", then the TECHNICAL scores. The answer shows the
   trade-off ("zone A avoids the ZPE but has 3× more cork oak than zone B") instead of hiding it in a weight.
6. **Explain.** The top zones (3 by default) go through the normal loop: `facts_for(zone polygon)` → Planner → Tracer →
   Challenger → Explainer, with the explanation graph. The *why-not* map is also checkable: the Challenger samples
   excluded cells and verifies the stated reason against the evidence ("excluded — inside ZPE PTZPE0010" must match an
   `icnf_areas_protegidas` row).
7. **Benchmark (airport only, §5).** The same rules score the published candidate sites; agreement and disagreement
   with the published study are findings, and every disagreement names the data we lack.

What it never does: pick "the" site, state that something is licensable, or turn a missing layer into "free".

## 3. Rules for national infrastructure — LEGAL means "procedure", not "forbidden"

For a house, a REN or RAN polygon usually ends the question. For a project of national interest it rarely does: most
regimes have a route (Natura 2000 derogation for imperative reasons of overriding public interest with compensation;
REN/RAN "relevant public interest"; cork-oak conversion for "indispensable public utility"; PDM amendment or
suspension). So in site mode:

- **Hard exclusions** (physical) exclude: open water and estuary, continuous urban fabric, slopes that make the footprint
  impossible. TECHNICAL, stated as such.
- **LEGAL regimes** are *counted and measured*, never silently excluded: which regime, how many hectares, which diploma,
  which procedure it triggers. A regime becomes an exclusion only when the author validates it as absolute for that
  intent (`status: validado`).
- **TECHNICAL criteria** score. They are engineering and planning rules of thumb, and the answer says so.

### Airport profile (hub, two parallel runways) — draft, all `proposta`

| Id | Kind | Rule | Source (to confirm in the official text) | Data |
|---|---|---|---|---|
| footprint | TECHNICAL | ≈ 4.6 × 2.5 km (4 000 m runways + strips/RESA; independent parallel approaches ≥ 1 035 m apart) ≈ 1 150 ha; the published study used ≥ 1 000 ha of expansion area as a viability criterion | ICAO Annex 14 Vol. I ch. 3; CTI viability criteria (2023) | — |
| gradient | TECHNICAL | elevation range along the runway axis ≤ 1 % of its length (≤ 40 m over 4 km) before earthworks; earthworks proxy = range and std of elevation in the footprint | ICAO Annex 14 Vol. I §3.1.13 | `mdt_lidar2024` |
| wind | TECHNICAL | usability ≥ 95 % with crosswind ≤ 37 km/h (10.28 m/s) | ICAO Annex 14 §3.1.1–3.1.3; ICAO Doc 9157 (the limit the CTI used) | ERA5 (§6) |
| access | TECHNICAL | straight-line distance to central Lisbon (the CTI used ~22 km, the European average, as a proximity reference); distance to motorway junction and to the rail network | CTI viability criteria | OSM |
| exposure | TECHNICAL (proxy) | residents under simplified approach/take-off surfaces (15 km, 15 % divergence) — **a proxy for noise, never a noise contour** | ICAO Annex 14 ch. 4 (surface dimensions to confirm) | BGRI 2021 |
| birds | TECHNICAL | ZPE/ZEC/Ramsar and wetland land cover within the surfaces and within a reference radius | ICAO Annex 14 §9.4 (wildlife hazard; radius to confirm) | ICNF, COS |
| natura | LEGAL (procedure) | hectares of ZPE/ZEC in footprint and surfaces → appropriate assessment; derogation only for imperative reasons of overriding public interest | DL 140/99 (as amended by DL 49/2005); Directive 92/43/EEC art. 6(3)–(4) | ICNF |
| rnap | LEGAL (procedure) | hectares of protected area (e.g. Reserva Natural do Estuário do Tejo) | DL 142/2008 + the area's own regulation | ICNF |
| ren / ran | LEGAL (procedure) | hectares in REN (incl. aquifer-recharge and flood typologies where delimited) / RAN → relevant-public-interest route | DL 166/2008; DL 73/2009 | DGT SRUP |
| montado | LEGAL (procedure) | hectares of cork-oak / holm-oak stands (COS classes 5.1.1.1 and the cork-oak agro-forestry classes, as the CTI did) → cutting needs authorisation, conversion only for indispensable public utility | DL 169/2001 (as amended by DL 155/2004) | COS 2023 (2018 for comparability) |
| pdm | LEGAL (procedure) | CRUS class/category in the footprint → compatibility, or amendment/suspension | RJIGT, DL 80/2015; DR 15/2015 | `dgt_crus` |
| easements | LEGAL | existing aeronautical and military easements, heritage protection zones, water-abstraction protection perimeters | SRUP (DGT); Lei 107/2001; DL 382/99 | §6 |
| eia | LEGAL (fact) | an airport with a runway ≥ 2 100 m is subject to EIA — always true, stated once | DL 151-B/2013, Annex I | — |
| flood / fire / seismic / geology / aquifer / seveso | TECHNICAL | T100 extent; fire hazard class; EC8 zone; soft alluvium; overlap with the Tejo-Sado groundwater body; Seveso sites within 1.5 km (the CTI's buffer) | APA, ICNF, NP EN 1998-1, LNEG, APA, APA | §6 |

## 4. Other intents

| Intent | Footprint / cell | Decisive layers | Data today | When |
|---|---|---|---|---|
| Large PV plant | 5–50 ha / 50–100 m | slope + aspect (`mdt_lidar2024`), CRUS, REN/RAN, Natura, flood, fire; grid connection capacity | all loaded in the pilot regions except grid capacity (E-REDES open data — to check) | cheapest; can run on the pilot regions with no new data |
| Logistics / industrial park | 10–100 ha / 100 m | CRUS "espaços de atividades económicas", slope ≤ 5 %, flood, motorway access | OSM missing | after OSM is loaded |
| Data centre | 2–20 ha / 50 m | power (substation capacity), water, fibre, flood, seismic | power and fibre mostly not open → many unknowns | post-hackathon; honest "unknown" is the demo |
| Public facility (school, health centre, fire station) | plot / 50 m | population served (BGRI) within a travel time, CRUS, hazards | needs a routing engine (OSM + pgRouting/OSRM) | post-hackathon |

## 5. Airport benchmark — checked against the public record, not deciding anything

Facts (checked 2026-09-30, sources in §9):

- The **Comissão Técnica Independente** (CTI, RCM 89/2022) narrowed 17 hypotheses to **9 strategic options** (Apr 2023):
  Portela + Montijo, Montijo + Portela, Alcochete (CTA), Portela + Santarém, Santarém, Portela + Alcochete, Pegões/Vendas
  Novas, Portela + Pegões/Vendas Novas, Rio Frio + Poceirão. Five critical decision factors: aeronautical safety;
  accessibility and territory; human health and environmental viability; connectivity and economic development; public
  investment and financing.
- Final report delivered **11 Mar 2024**: Alcochete (Campo de Tiro) and Vendas Novas as the most favourable single-airport
  options; both Montijo options ruled out (largest environmental impacts, expired 2019 EIA decision); Santarém only as a
  complement to Portela; Rio Frio + Poceirão excluded and left out of the environmental GIS.
- Government decision **14 May 2024** (RCM 66/2024): new airport "Luís de Camões" at the **Campo de Tiro de Alcochete**,
  fully replacing Humberto Delgado. **20 Mar 2026:** the Government validated the site after ANA's selected-site report
  (Jan 2026); the EIA was due at APA in July 2026.
- The CTI wind annex (PT2, Annex 1) gives runway orientations and crosswind usability from local measurements (not
  published as data): Alcochete 180°–360°, 92.75 %; Vendas Novas 180°–360°, 92.70 %; Santarém 120°–300°, 88.80 %;
  Lisboa 20°–200°, 85.94 %; limit 37 km/h. Montijo data was discarded (mean, not peak, winds).
- The CTI environmental GIS (PT4, Annex 5) lists its indicators and sources — mostly the same open layers this
  project loads (BGRI, ICNF protected areas, COS cork-oak classes, REN, RAN, APA floods and aquifers, ICNF fire hazard,
  a 25 m DEM). Its **site polygons, approach cones and noise contours were not published as data** (PDF maps only).

Framing: the agent **reproduces a public screening from open data and explains each exclusion** — a test with a known
answer. It does not re-open the decision and does not claim the site is right or wrong.

Benchmark checks (they become eval cases):

| Check | Pass when |
|---|---|
| recall | the CTA and Vendas Novas areas are inside the agent's top-5 zones |
| reasons | for each option the CTI dropped, the agent's first failing criterion matches the CTI's stated main reason (Montijo → birds/ZPE; Rio Frio + Poceirão → environment (montado/aquifer — to confirm in the Environmental Report ch. 3); Santarém single → distance/capacity) |
| wind | ERA5 gust-based usability ranks the sites in the same order as the CTI table (values will differ: reanalysis ≠ local peak measurements — said as such) |
| honesty | every criterion the agent cannot compute (noise contours, airspace, bird corridors) appears as an unknown with its reason |

The 9 options enter as **reference geometries** digitised approximately from the CTI's PDF layouts (PT2, Annex 12,
86 MB) and labelled as such; reuse terms of the CTI material to be confirmed.

## 6. Data plan — airport study area

Study area: AML (18 municipalities) + Lezíria do Tejo (11) + Vendas Novas = **30 municipalities, 7 512 km²** (CAOP
2025, NUTS III 1A0 + 1B0 + 1D3 + DICO 0712). Lisboa (1106) is already loaded → a new region `lisboa_tejo` with the
other 29. It contains all nine CTI options. Sizes are **estimates** scaled by area from today's per-km² table sizes
(current regions: 5 681 km², DB 1 983 MB) — measured after loading.

| Dataset | Publisher | Licence | URL | Coverage | Est. size | Load effort | Role | Open |
|---|---|---|---|---|---|---|---|---|
| COS 2023 (+ grid helper) | DGT | CC BY 4.0 | geo2.dgterritorio.gov.pt/cos/S2/COS2023/ (national file already downloaded) | national → clip | +360 MB (+160) | config | TECHNICAL (water/urban exclusions) · LEGAL proxy (cork oak) | Y |
| COS 2018 (optional) | DGT | CC BY 4.0 | geo2.dgterritorio.gov.pt/cos/S2/COS2018/ | national → clip | +180 MB | config | comparability with the CTI's cork-oak figures | Y |
| Fire hazard | ICNF via DGT | CC BY 4.0 (licence conflict noted in sources.md) | snit-mais.dgterritorio.gov.pt/…/PERIGOSIDADE_INCENDIO_RURAL.zip (downloaded) | national → clip | +170 MB | config | TECHNICAL | Y |
| Flood T100 + ARPSI (PGRI 2C) | APA | APA terms (to confirm) | SNIAmb ArcGIS REST (as today) | by bbox | +20 MB | config | TECHNICAL | Y |
| RNAP + Natura 2000 (ZPE/ZEC Estuário do Tejo) | ICNF | CC BY 4.0 | si.icnf.pt/wfs/{rnap,zec,zpe} | national | +5 MB | config | LEGAL (procedure) | Y |
| CRUS / PDM classes (29 municipalities) | DGT | CC BY 4.0 | servicos.dgterritorio.pt/SDISNITWFSCRUS_<DICO>_1 | per municipality | +250 MB | config (slow WFS) | LEGAL (procedure) | Y |
| REN (+ watercourses) | DGT / CCDR LVT, Alentejo | CC BY 4.0 | SDISNITWFSSRUP_REN_LVT and SDISNITWFSSRUP_REN_ALENTEJO (feature types `REN_LVT`/`REN_Alentejo` + `Linhas_de_Agua_*` — both checked 30 Sep) | per municipality (gaps possible) | +165 MB | config | LEGAL (procedure) | Y |
| RAN | DGT | CC BY 4.0 | SDISNITWFSSRUP_RAN_PT1 | per municipality | +45 MB | config | LEGAL (procedure) | Y |
| BGRI 2021 | INE | open ("sem condições") | mapas.ine.pt/download/filesGPG/2021/municipios/BGRI2021_<DICO>.zip | 29 municipalities | +90 MB | config | TECHNICAL (exposure proxy) | Y |
| LiDAR MDT 2 m → 10 m elevation + slope | DGT | CC BY 4.0 | STAC cdd.dgterritorio.gov.pt (free account) | **7 885 tiles found for the area (30 Sep)** | 7.9 GB raw on the laptop; +200 MB in DB (aspect skipped) | 2–4 h download + 1 h | TECHNICAL (gradient, earthworks) | Y |
| Copernicus GLO-30 (fallback) | ESA / Copernicus | Copernicus DEM licence | copernicus-dem-30m.s3.amazonaws.com (3 tiles) | global | +120 MB raw | config | fallback only | Y |
| LiDAR building footprints (optional) | DGT | CC BY 4.0 | national GPKG (downloaded) | clip | +300 MB | config | context | Y |
| SRUP Aeroportos e Aeródromos | DGT | CC BY 4.0 (dados.gov.pt, updated 2026-03-06) | SNIT SRUP WFS (endpoint from GetCapabilities) | national | < 10 MB | new stage, REN/RAN pattern | LEGAL (existing easements) | Y |
| SRUP Defesa Nacional | DGT | to confirm | SDISNITWMSSRUP_DN_PT1 (WMS seen; WFS to confirm) | national | < 10 MB | new stage | LEGAL (military easements; the CTA is still a firing range) | Y (WFS to confirm) |
| SRUP Imóveis Classificados / Atlas do Património | DGT / Património Cultural | CC BY 4.0 (SRUP); Atlas to confirm | dados.gov.pt `srup-imoveis-classificados`; geo.patrimoniocultural.gov.pt WFS | national | < 20 MB | new stage | LEGAL (ZGP/ZEP) | Y |
| Groundwater bodies (PGRH 3rd cycle, Tejo-Sado) | APA | open (dados.gov.pt) | SNIAmb REST/WFS | national | < 10 MB | new stage, APA pattern | TECHNICAL | Y |
| Water-abstraction protection perimeters | APA | open (to confirm) | SNIAmb | national | < 5 MB | new stage | LEGAL | Y (service to confirm) |
| Seveso establishments (DL 150/2015) | APA | to confirm | SNIG record "Seveso" | national points | < 1 MB | new stage | TECHNICAL (1.5 km) | to confirm (the CTI got it from APA) |
| Geological map 1:500 000 | LNEG | LNEG property, attribution required (terms to confirm) | geoportal.lneg.pt/pt/dados_abertos/cartografia_geologica/cgp500k | national | < 40 MB raw | new stage | TECHNICAL (foundations) | Y |
| OSM roads + rail | OpenStreetMap contributors (Geofabrik extract) | ODbL | download.geofabrik.de/europe/portugal-latest.osm.pbf (424 MB, 30 Sep) | national → clip, motorway/trunk/primary + rail | +60 MB | new stage | TECHNICAL (access) | Y |
| ERA5 hourly 10 m wind + gust, 2015–2024 | ECMWF / Copernicus C3S | Licence to use Copernicus Products (free, attribution) | cds.climate.copernicus.eu (free account + API token → vault) | 0.25° grid (~30 points) | 50–150 MB raw; < 1 MB in DB (wind rose per point) | new script + queue | TECHNICAL (orientation, usability) | Y |
| Station winds (METAR/ISD: Portela, Montijo, Alverca) | NOAA NCEI | free (WMO terms apply) | ncei.noaa.gov (global-hourly) | points | ~10 MB | low | TECHNICAL (validates ERA5) | Y (terms to confirm) |
| EC8 seismic zone per municipality | IPQ (NP EN 1998-1, National Annex) | standard (copyright) | table | 30 rows | tiny | manual | TECHNICAL | partial |
| CTI options (reference geometries) | CTI | public report, reuse terms to confirm | aeroparticipa.pt/relatorios/ (PT2 Annex 12 layouts) | 9 options | < 1 MB | 2–3 h digitising | benchmark reference, not a layer | N as data → digitise |
| Noise contours (Lden/Ln) | ANA | not published | — | — | — | — | — | N → BGRI under surfaces (proxy) |
| Approach cones, bird-migration corridors, IBA | CTI / SPEA / BirdLife | not published / on request | — | — | — | — | — | N → ZPE/ZEC + wetlands + distance (proxy) |
| Airspace (restricted/danger areas, TMA) | NAV Portugal (eAIP) | public, not open data | — | — | — | manual | — | N → unknown |
| Obstacle surfaces vs terrain and buildings | derived: DGT LiDAR MDS 2 m | CC BY 4.0 | same data centre | area | ~8 GB more raw | high | TECHNICAL | Y, post-hackathon |

Totals (estimates): **downloads ≈ 9 GB** on the laptop (7.9 GB of it the 2 m terrain tiles); **database +2.3–2.8 GB**
with every current layer, or **+1.4–1.8 GB** with a lean set (no COS 1995/2018/2025 series, no building footprints, no
aspect). The server database (1.57 GB today) would roughly double; its free disk is checked before any restore.

## 7. Scale, speed and sample mode

- Screening grid for the airport area: ~30 000 cells at 500 m; per-cell facts computed once (minutes) and cached;
  re-scoring with changed conditions ("avoid montado") is arithmetic on the cached grid (< 1 s). Footprint fit on a
  rasterised mask (numpy or equivalent): seconds.
- The live part of a run is the explanation of the top zones — the normal loop, same budget (≤ 3 rounds, ≤ 20 tool
  calls, 120 s).
- Sample mode: the cached screening grid for the study area (~10–15 MB) + the layers clipped to the 9 CTI option
  footprints and the top zones — inside the < 50 MB target.

## 8. Hackathon fit

| Part | Where | Condition |
|---|---|---|
| Plot mode (one user, one decision) | **core** — unchanged, never cut | — |
| "Not here, but there" (local grid, rule-coloured) | core day 3 — becomes the first use of the cell-verdict code above | — |
| Site mode, **airport benchmark only** (top-3 zones, why-not map, CTI options scored, benchmark evals) | **gated stretch** — Sat 17 midpoint checkpoint | build only if the loop with revisions, the graph and ≥ 5 golden cases run; otherwise it stays a design note and nothing about it is claimed |
| Large PV in the pilot regions | stretch after the airport | ≤ 1 h left |
| Logistics, data centre, public facility; noise modelling; airspace; obstacle surfaces | post-hackathon | — |

Window cost (estimate): 10–12 h — screening grid 2 h, footprint fit and zones 3 h, rules 1 h, explanation reuse
1.5 h, benchmark evals 1.5 h, map layer 2 h, video/README 1 h. Room comes from cut-list items 1 (H-MEM), 2 (PT/EN) and
6 (routed vs single-model) applied up front, plus sharing the Sat 17:00–19:00 grid block. **Proposed changes to
`docs/plano-janela.md` are not applied** — they wait for the pre-window data to land.

## 9. Sources

- CTI final report and annexes: https://aeroparticipa.pt/relatorios/ (PT2 Annex 1 wind analysis; PT2 Annex 12 layouts;
  PT4 Annex 5 GIS structure and sources)
- Nine options and viability criteria (27 Apr 2023): https://www.publituris.pt/2023/04/27/de-17-ficam-9-pegoes-vendas-novas-rio-frio-e-poceirao-entram-em-jogo-para-o-novo-aeroporto-de-lisboa
- Final report (11 Mar 2024): https://observador.pt/2024/03/11/relatorio-final-da-comissao-tecnica-so-afasta-opcoes-para-o-montijo-e-santarem-como-aeroporto-unico/
- Council of Ministers, 14 May 2024: https://portugal.gov.pt/pt/gc24/governo/comunicados-do-conselho-de-ministros/612
- Site validated, 20 Mar 2026: https://portugal.gov.pt/pt/gc25/comunicacao/noticias/localizacao-do-novo-aeroporto-validada-no-campo-de-tiro-de-alcochete
- SRUP Aeroportos e Aeródromos: https://dados.gov.pt/pt/datasets/srup-aeroportos-e-aerodromos/ · SRUP Defesa Nacional:
  https://dados.gov.pt/en/datasets/srup-defesa-nacional/ · SRUP Imóveis Classificados:
  https://dados.gov.pt/pt/datasets/srup-imoveis-classificados/
- Groundwater bodies: https://dados.gov.pt/pt/datasets/massas-de-agua-subterraneas-de-portugal-continental-conjunto-de-dados-geografico-sniamb-2/
- LNEG geological map 1:500 000: https://geoportal.lneg.pt/pt/dados_abertos/cartografia_geologica/cgp500k

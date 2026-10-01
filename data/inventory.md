# Open-data inventory — Lisbon and surroundings (site-selection mode)

**What this is.** Every open dataset found (30 Sep 2026) that could feed the site-selection mode
(`docs/site-selection.md`) for the study area AML + Lezíria do Tejo + Vendas Novas (30 municipalities, 7 512 km²).
Status updated 2026-09-30 evening: Tier 1 and most of Tier 2 are loaded locally (**L**; OK given 2026-09-30); what is
loaded, with row counts and licences, is in `data/sources.md`. 2026-10-01: LNEG geology 1:500 000 and DGEG solar plants loaded; still to load: transit timetables (licence), Tier 3.

**How it was built.** dados.gov.pt API queried with 110 siting-related terms (1 210 datasets returned, filtered to
national, metropolitan and AML-municipal publishers); the E-REDES and SNS open-data catalogues (Opendatasoft API);
endpoints checked live where it mattered (DGT SRUP/CRUS WFS, LNEG MapServer, IP files, DGT STAC, Geofabrik); the CTI
report annexes for what the airport study used.

Status: **L** loaded in the pilot regions (extend to the study area) · **N** new, open, access checked · **W** open but
view-only, third-party host or licence not stated · **X** not open → proxy or manual reference.
Sizes are database estimates for the study area (order of magnitude).

## 1. Planning and legal constraints

| Dataset | Publisher | Licence | Access | Coverage | Est. size | Status | Feeds |
|---|---|---|---|---|---|---|---|
| CAOP 2025 | DGT | CC BY 4.0 | GPKG | national | loaded | L | all |
| CRUS (PDM land-use classes) | DGT | CC BY 4.0 | **one national WFS** `servicos.dgterritorio.pt/SDISNITWFSCRUS` (per-municipality services also exist) | national | 250 MB | L | all (LEGAL) |
| PDM Lisboa 2022, PDM Oeiras 2022, planos de pormenor, ARU | CM Lisboa / CM Oeiras | CC0 / CC BY 4.0 | GeoJSON / WFS (dados.gov.pt) | 2 municipalities | < 20 MB | N (optional; CRUS covers) | housing, school/health |
| REN (+ watercourses) | DGT / CCDR LVT, Alentejo | CC BY 4.0 | WFS `SRUP_REN_LVT`, `SRUP_REN_ALENTEJO` | per municipality | 165 MB | L | all (LEGAL) |
| RAN | DGT | CC BY 4.0 | WFS `SRUP_RAN_PT1` | per municipality | 45 MB | L | all (LEGAL) |
| RNAP, Natura 2000 ZPE/ZEC | ICNF | CC BY 4.0 | WFS si.icnf.pt | national | 5 MB | L | all (LEGAL) |
| SRUP — Aeroportos e Aeródromos | DGT | CC BY 4.0 | WFS/WMS (updated 2026-03-06) | national | < 10 MB | L | airport, all (LEGAL) |
| SRUP — Defesa Nacional | DGT | CC BY 4.0 | WFS/WMS | national | < 10 MB | L | airport, all (LEGAL) |
| SRUP — Imóveis Classificados; Edifícios de Interesse Público; Árvores de Interesse Público | DGT | CC BY 4.0 | WFS/WMS | national | < 20 MB | L | all (LEGAL) |
| SRUP — Captações de Águas Subterrâneas para Abastecimento Público; Domínio Público Hídrico | DGT | CC BY 4.0 | WFS/WMS | national | < 30 MB | L | all (LEGAL) |
| SRUP — Gasodutos e Oleodutos; Telecomunicações; Instalações com Produtos Explosivos | DGT | CC BY 4.0 | WFS/WMS | national | < 10 MB | L | all (LEGAL) |
| SRUP — Regime Florestal; Recursos Geológicos; Obras de Aproveitamento Hidroagrícola (Lezíria) | DGT | CC BY 4.0 | WFS/WMS | national | < 20 MB | L | all (LEGAL) |
| SRUP — Espécies Agrícolas e Florestais (cork/holm oak?) | DGT | not stated | WFS/WMS | national | small | W (content to check) | airport, PV (montado) |
| Water-abstraction protection perimeters (immediate/intermediate/extended) | APA | not stated | WFS/WMS/zip | national | < 10 MB | L (licence not stated — not shown) | all (LEGAL) |
| Mineral-water protection perimeters | DGEG | CC BY 4.0 | WFS/WMS | national | small | N | all |
| Renewable acceleration areas (PAER, scenarios A–E) | LNEG | not stated | ArcGIS MapServer with **Query** (`sig.lneg.pt/server/rest/services/AreasAceleracaoEnergiasRenovaveis`) | national | < 20 MB | X → view-only (the service returns no geometry, 2026-09-30) | PV (positive LEGAL factor) |
| Less-sensitive areas for solar/wind (+ scenarios 1–4) | LNEG | not stated | MapServer with Query (`AreasCandidatasRenovaveis`) | national | < 20 MB | L (licence not stated — not shown) | PV |
| Cadastro Predial (parcels where the cadastre exists) | DGT | CC BY 4.0 | WFS/WMS | partial | to measure | N | candidate parcels |
| BUPi georeferenced parcels (RGG) | eBUPi | CC BY 4.0 | GPKG (670 MB national) / WFS | partial (little in AML) | to measure | N (optional) | candidate parcels |

## 2. Hazards and environment

| Dataset | Publisher | Licence | Access | Coverage | Est. size | Status | Feeds |
|---|---|---|---|---|---|---|---|
| Rural fire hazard | ICNF / DGT | CC BY 4.0 | zip (downloaded) | national | 170 MB | L | all |
| Burned areas 1975–2025 | ICNF | CC BY 4.0 | WFS | national | 10 MB | L | all |
| Flood extents (T20/T100/T1000, depth, velocity), ARPSI | APA | not stated | WFS/zip (updated 2026-04-13) | national | 20 MB | L | all |
| AML floods and sea level (telemetry) | AML (host greenmetrics.ai) | CC BY 4.0 | WFS/WMS (updated 2026-09-01) | AML | to measure | W (third-party host) | all coastal/riverside |
| Civil-protection risk layers (river floods, coastal erosion, overtopping, strong winds, hazmat on rail) | ANEPC | not stated | WFS | national | small | W | all |
| Active Quaternary faults (QAFI) | LNEG | not stated | WMS | Iberia | — | W | airport, all |
| Soil seismic behaviour; soil types | CM Lisboa | CC0 | GeoJSON | Lisboa | small | N | all (Lisboa) |
| Groundwater bodies (PGRH), incl. Tejo-Sado | APA | not stated | WFS/zip | national | < 10 MB | L (licence not stated — not shown) | airport, logistics |
| Hydrogeological resources; boreholes (SONDABASE) | LNEG | not stated | WFS | national | small | W | airport, logistics (foundations) |
| Habitats and species incl. birds (PSRN2000) | ICNF | not stated | WFS | national | to measure | W | airport (bird strike), all |
| Regional forest programmes PROF (ecological corridors) | ICNF | not stated | WFS | national | to measure | W | all |
| Seveso establishments | APA | to confirm | SNIG record | national | < 1 MB | to confirm | all (1.5 km) |

## 3. Terrain, geology, land cover, buildings

| Dataset | Publisher | Licence | Access | Coverage | Est. size | Status | Feeds |
|---|---|---|---|---|---|---|---|
| LiDAR 2024 terrain model 2 m → 10 m elevation/slope | DGT | CC BY 4.0 | STAC (account) — **7 885 tiles, 7.9 GB found for the area** | study area | 200 MB | L | all |
| Geological map of the AML 1:100 000 | LNEG | CC BY 4.0 (dados.gov.pt, checked 2026-10-01) | two sheet images (JPG, PDF) — no vector | AML | small | X → 1:500 000 instead | airport, logistics |
| Geological map 1:500 000; continuous geology 1:200 000 (prototype) | LNEG | CC BY 4.0 (dados.gov.pt; geoPortal notice: non-commercial) | ArcGIS REST / WFS (1:500 000); REST (1:200 000) | national (the 1:200 000 prototype covers 1 km² of the study area) | small | L (1:500 000, 2026-10-01) | all |
| COS 2023 / 2025 (+ 2018 for comparability) | DGT | CC BY 4.0 | GPKG (downloaded) | national | 360 MB (+180) | L | all |
| Annual land cover COSc 2018–2025 | DGT | CC BY 4.0 | zip/WMS | national | to measure | N (optional) | change checks |
| Built-up interface map (structural 2018, conjunctural) | DGT | CC BY 4.0 | zip/WMS | national | to measure | N | housing, fire interface |
| LiDAR 2024 building footprints | DGT | CC BY 4.0 | GPKG (downloaded) | national | 300 MB | L | all |
| Urban Atlas 2006/2012 | DGT (Copernicus) | CC BY 4.0 | zip | Lisbon FUA | to measure | N (old; optional) | housing |
| ESA WorldCover 10 m | ESA | CC BY 4.0 | COG, read live | global | 0 | L (tier D) | fallback |
| Orthophotos 25 cm 2025 | DGT | CC BY 4.0 | WMS | national | 0 (service) | N | map background |

## 4. People and services

| Dataset | Publisher | Licence | Access | Coverage | Est. size | Status | Feeds |
|---|---|---|---|---|---|---|---|
| BGRI 2021 (census subsections) | INE | open | GPKG per municipality | study area | 90 MB | L | all |
| Median housing €/m² | INE | CC BY 4.0 | JSON API | national | small | L | housing |
| Primary-care functional units (location) + registered users | ACSS / SNS | CC BY 4.0 | CSV/JSON/SHP | national | small | X → aggregated per ACES; TML health centres (AML) loaded instead | health centre |
| Hospital emergency departments (characterisation, geo) | SNS Transparência | not stated | Opendatasoft API | national | small | W | health, all |
| Schools of the AML | TML | not stated | CSV | AML | small | L (ODbL per the source repository) | school |
| Public and private schools (all levels), health centres, fire stations, civil protection, metro and rail | CM Lisboa | CC0 | GeoJSON | Lisboa | small | N | school, health, housing |
| Collective-use facilities (education, civil protection), school catchments, fire-brigade areas | CM Oeiras | CC BY 4.0 | WFS/GeoJSON | Oeiras | small | N | school, health |
| Higher-education establishments | DGEEC | CC BY 4.0 | WMS | national | — | W | school |

## 5. Transport

| Dataset | Publisher | Licence | Access | Coverage | Est. size | Status | Feeds |
|---|---|---|---|---|---|---|---|
| National rail network (in operation) | Infraestruturas de Portugal | CC BY 4.0 | SHP zip (0.7 MB, 2026-04-15) | national | small | L | airport, logistics, HSR |
| National road network; motorways 1:10 000 | Infraestruturas de Portugal | CC BY 4.0 | SHP zip (15 MB) / WFS | national | < 50 MB | L (SHP; the 1:10 000 WFS not used) | airport, logistics, all |
| OSM roads, rail, POIs, power lines and substations | OpenStreetMap (Geofabrik) | ODbL | PBF 424 MB (30 Sep) | national | 150–250 MB (filtered) | L | all (network, travel time) |
| GTFS Carris Metropolitana; stops, shapes, cycle network | TML | CC BY 4.0 (GTFS: not stated) | GTFS/GeoJSON | AML | small | L (stops + route patterns via the TML OGC API, CC BY; timetables not — GTFS licence not stated) | housing, school, health |
| GTFS Metropolitano de Lisboa | Metro de Lisboa | not stated | GTFS zip | Lisboa | small | L (CC BY 4.0 on dados.gov.pt since the feed of 2026-01-14) | housing, school, health |
| GTFS CP, Fertagus, Transtejo | operators | to confirm | — | — | — | to confirm | transit time |
| High-speed rail Porto–Lisboa and the airport link | IP / Government | — | **no GIS published**; phase Carregado–Lisboa and the link to the new airport not yet routed | — | — | X → reference routes digitised from public maps | HSR corridor benchmark |

## 6. Energy, telecom, climate, noise

| Dataset | Publisher | Licence | Access | Coverage | Est. size | Status | Feeds |
|---|---|---|---|---|---|---|---|
| Reception capacity of the distribution network (per substation) | E-REDES | CC BY 4.0 | Opendatasoft API (2026-07-11) | national | small | L | PV, data centre |
| Secondary substations (PTD, geo); substation load | E-REDES | CC BY 4.0 | Opendatasoft API | national | to measure | L | PV, data centre, logistics |
| Existing solar plants | DGEG | CC BY 4.0 (dados.gov.pt) vs CC BY-NC 4.0 (service) | ArcGIS REST / WFS / WMS | national | small | L (2026-10-01) | PV |
| Solar GHI/DNI and wind NEPS maps | LNEG | not stated | MapServer (Data) | national | small | W | PV |
| Solar irradiation per point (PVGIS) | JRC | free API | REST | global | 0 (live) | N | PV |
| Hourly wind 10 m + gusts, 1940– (ERA5 / ERA5-Land reanalysis) | Open-Meteo (ECMWF data) | CC BY 4.0, free non-commercial API, no key | REST `archive-api.open-meteo.com` | global | < 1 MB (wind rose per point) | N | airport (runway orientation) |
| Future climate (CMIP6, 1950–2050) | Open-Meteo | CC BY 4.0 | REST | global | small | N (optional) | all (heat, rain) |
| Daily climate (radiation, wind) | NASA POWER | free, no key | REST | global | small | N (cross-check) | PV, airport |
| Fixed and mobile network coverage | ANACOM | not stated | dados.gov.pt | national | — | W | data centre |
| Strategic noise map of Lisbon (all sources, incl. the airport) | CM Lisboa | CC BY 4.0 | SHP/PDF | Lisboa | small | X → JS challenge (403 to scripts); not loaded | housing, school/health |
| Strategic noise map 2022 | CM Oeiras | CC BY 4.0 | WFS | Oeiras | small | L | housing, school/health |
| Humberto Delgado airport Lden/Ln 2021 | ANA / APA | — | **PDF only** | — | — | X → Lisbon's municipal map covers the city | airport context |

## 7. Not open (the system says "unknown")

Aircraft noise contours for new sites, approach cones and bird-migration corridors (CTI/SPEA), airspace (eAIP),
transmission-grid capacity for consumption (data centres), water supply capacity, fibre routes, geotechnical
surveys beyond LNEG boreholes, land prices per parcel, land ownership (outside cadastre/BUPi).

## 8. Requirements → data, per structure type

Every request is broken into a small set of **requirement primitives**; each primitive reads specific layers.
● needed · ○ useful · — not needed.

| Primitive | Layers | Airport | Large PV | Logistics | School / health | Housing | HSR corridor | Data centre |
|---|---|---|---|---|---|---|---|---|
| area / shape / orientation | footprint only | ● | ● | ● | ● | ● | (band width) | ● |
| slope, elevation range | MDT | ● ≤ 1 % axis | ● ≤ 10 % + aspect | ● ≤ 5 % | ● | ● ≤ 15 % | ● gradient ≤ 25–35 ‰ | ○ |
| hard exclusion | COS water/urban | ● | ● | ● | ● | ● | ● (cost) | ● |
| LEGAL regimes (measured) | CRUS, REN, RAN, Natura, RNAP, SRUP pack | ● | ● | ● | ● | ● | ● (cost) | ● |
| positive zoning | CRUS classes, PAER / less-sensitive areas | ○ | ● | ● | ● | ● | — | ● |
| distance to network | IP rail/roads, OSM | ● | ○ | ● | ● | ● | ● (endpoints) | ○ |
| travel time | OSM network (+ GTFS) | ● to Lisbon | — | ● to port/motorway | ● walk/transit | ● transit | — | — |
| population served / exposed | BGRI 2021 | ● under surfaces | — | ○ workforce | ● catchment + gap vs existing | ○ | ● band | — |
| existing services | schools, health units | — | — | — | ● | ● | — | — |
| hazards | fire, flood, sea level, seismic | ● | ● | ● | ● | ● | ● | ● |
| climate | wind history; GHI | ● wind | ● GHI | — | — | — | — | — |
| grid capacity | E-REDES | — | ● injection | ○ | — | — | — | ✗ consumption not open |
| noise | Lisbon/Oeiras maps | ○ | — | — | ● | ● | ● | — |
| geology / foundations | LNEG AML 1:100k, boreholes | ● | — | ● | — | ○ | ● | ○ |

Reading: the layers already loaded answer the LEGAL and physical screening for every type; the SRUP pack, IP/OSM
networks, E-REDES and the service locations unlock the rest; the airport alone adds wind; the data centre stays the
honest example of what cannot be assessed with open data.

## 9. Load order (proposed; each tier needs a go-ahead)

1. **Tier 1 — extend what exists** to the 29 new municipalities (config only): CRUS (national WFS), REN, RAN, ICNF,
   APA floods, fire hazard, COS 2023, BGRI, MDT (elevation + slope), building footprints. ≈ +1.4–1.8 GB (lean set).
2. **Tier 2 — shared new layers** (one loader pattern each): SRUP pack (≈ 14 typologies, same WFS family), IP rail +
   roads, OSM network and power, E-REDES capacity + PTD, LNEG PAER / less-sensitive areas, APA protection perimeters and
   groundwater, LNEG geology AML 1:100k, Lisbon and Oeiras noise, schools and health units, TML/Metro GTFS. ≈ +0.5–0.8 GB.
3. **Tier 3 — type-specific:** Open-Meteo wind (airport), ICNF birds (PSRN2000), LNEG boreholes, AML sea level, ANEPC
   risks, cadastre parcels; manual references (CTI options, HSR route alternatives).

Downloads ≈ 8.5 GB on the laptop (7.9 GB are the 2 m terrain tiles). Licences marked "not stated" are asked or
confirmed before anything from them is shown in the public demo.

## 10. Gaps in the study area after Tier 2 (checked 2026-10-01)

Measured on the local database, then searched for elsewhere (dados.gov.pt by publisher and by title, the SNIG
catalogue, the DGT services, the SNIT-SGT REN portal, CCDR LVT). **F** = checked; nothing below is loaded unless the
last column says so.

| Layer | Gap (F) | What exists elsewhere (F) | Terms (F) | Status · action |
|---|---|---|---|---|
| REN | No polygons in the DGT REN WFS for **12 of 30 municipalities — 3 636 of 7 512 km² (48 %)** | **Loures:** the full current delimitation as vector (one shapefile per typology + exclusions; 3rd amendment, Aviso 30872/2025/2; 88.1 km² of 167.2) in the deposit files of the SNIT-SGT portal (`snit-sgt.dgterritorio.gov.pt/ren`, API `api/Easement/GetEasementsAsync`, files `SNIT/Ficheiros/AcessoSimples/1107_PLANTA_TEMA_*.zip`) · **Amadora, Alpiarça, Coruche, Salvaterra de Magos, Sesimbra (and Loures):** the REN chart as a georeferenced image (WMS `SDISNITWMSREN_<DICO>_1`; Alpiarça and Salvaterra also have vector files of recent exclusions only) · **Chamusca, Rio Maior, Barreiro:** only the diplomas (RCM/Portaria/Aviso PDFs) · **Azambuja, Alcochete, Montijo:** no REN entry in SNIT at all · CCDR LVT: copies or extracts of REN charts on written request, with fees | SNIT (SNIG records of the REN charts): «destina-se à consulta e visualização, sendo interdita a sua comercialização»; not for administrative procedures. SNIT-SGT printouts: «© DGT — Todos os direitos reservados» | **X** for data (not open); **W** view-only for the 6 charts — **author's option B (2026-10-01): shown as a backdrop "REN chart (image) — not measured"** (`snit_ren_carta`; images by `etl/ren_cartas.sh`, Loures and Salvaterra georeferenced, the DGT WMS GetMap did not answer on 2026-10-01). Loures vector not loaded |
| REN watercourse lines | Published for 9 of 30 municipalities | — | — | partial; "not published" stays distinguishable from "none" |
| RAN | Not published for Lisboa and Amadora | Amadora: PDM 1994 constraints chart (SNIG, «sob consulta, com restrições») | not open | unknown there |
| CRUS | None real: the 34.3 km² of Alcochete without CRUS are 33.7 km² of estuary water | — | — | — |
| Noise | Oeiras only before 2026-10-01; now also Amadora and Odivelas (whole agglomerations) and 156 km² of major-road corridors (EEA, `ruido_end`, **L** 2026-10-01) — 27 municipalities still unknown away from the major roads | Lisboa (CC BY, `.7z` on dados.cm-lisboa.pt): still behind a Cloudflare challenge (HTTP 403 "Just a moment…", 2026-10-01) — not bypassed; no other municipality publishes one on dados.gov.pt | CC BY (Lisboa) | Lisboa only by a manual browser download into `data/raw/ruido/` (author) |
| Public transport | No stops for the 11 Lezíria municipalities (Azambuja, Almeirim, Alpiarça, Benavente, Cartaxo, Chamusca, Coruche, Golegã, Rio Maior, Salvaterra de Magos, Santarém); no timetables anywhere | No open GTFS for CP, Rodoviária do Tejo or Fertagus on dados.gov.pt; the Carris Metropolitana full GTFS has no licence | — | rail stations and bus stations from OSM only (failure mode 24) |
| Schools, health units | Lezíria and Vendas Novas from OSM only | CM Lisboa (CC0) and Oeiras (CC BY) points, AML only | open | optional |
| E-REDES substations | 24 of 128 known by municipality only | — | — | failure mode 25 |
| Seveso establishments (DL 150/2015) | Not loaded | APA SNIAmb zip `vw_d308_apa_pag_pub.zip` + INSPIRE WFS (points, upper/lower tier) | not stated (dados.gov.pt) | Tier 3 in `site_profiles.json` → needs its own OK; would load as "not stated", off screen |
| Boreholes (SONDABASE) | Not loaded | LNEG, dados.gov.pt `base-de-dados-de-sondagens-geologicas-sondabase` | CC BY 4.0 (dados.gov.pt) | Tier 3 → needs its own OK |
| Renewable acceleration areas (PAER) | View-only | LNEG service without geometry | — | failure mode 30 |

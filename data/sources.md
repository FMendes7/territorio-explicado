# Data sources

All datasets are open data. Each row is what the agent cites. `reference date` is the data's own
reference, `retrieved` is when we downloaded it (filled by `etl/download.sh` into `data/raw/MANIFEST.tsv`).
**Download URLs marked TODO are confirmed at download time and recorded in the manifest.**

| id | Dataset | Publisher | Licence | CRS | Scope loaded | Reference | Download |
|---|---|---|---|---|---|---|---|
| caop2025 | Carta Administrativa Oficial de Portugal 2025 (Continente) — GPKG layers `cont_freguesias` (3 049, fields `dtmnfr, freguesia, municipio, distrito_ilha, nuts3_cod, nuts3, area_ha`), `cont_municipios` (278, `dtmn, municipio, …`), `cont_distritos`, NUTS | DGT | CC BY 4.0 | EPSG:3763 | national | 2025 (published 2026-02-18) | `https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip` (111 MB, confirmed 2026-09-26; SNIG record `198497815bf647ecaa990c34c42e932e`; also OGC API `ogcapi.dgterritorio.gov.pt`) |
| cos2023 | Carta de Uso e Ocupação do Solo 2023 (vector, MMU 0.5 ha, 1:25k) | DGT / SMOS | CC BY 4.0 | EPSG:3763 | 3 pilot regions | 2023 | `https://geo2.dgterritorio.gov.pt/cos/S2/COS2023/COS2023v1-S2-gpkg.zip` (COS2023v1 Série 2, national GPKG; SNIG record `9a9c5548-eb27-48a2-b850-09d3c9069b2d`, confirmed 2026-09-26) |
| icnf_perigosidade | Carta de Perigosidade de Incêndio Rural (SRUP), 5 classes, vector from 25 m raster | ICNF via DGT / dados.gov.pt | CC BY 4.0 | EPSG:3763 | 3 pilot regions | 2022-03-28 (Aviso 6345/2022); check newer edition in ICNF geocatalog | **Official zip (SNIT, listed on dados.gov.pt):** `https://snit-mais.dgterritorio.gov.pt/SNIT/DOWNLOAD/SRUP/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip` (295 MB shapefile, 2022-04-08, 1 754 093 polygons, field `gridcode` 0–5, EPSG:3763; confirmed 2026-09-26). The zip advertised on the DGT page returned **404** and the WFS `servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1` answers `GetFeature` with an exception (both 2026-09-26). ⚠️ Licence conflict: dados.gov.pt says CC BY 4.0; the ICNF geocatalogue metadata says consultation only / other uses need DGT authorisation → we use it non-commercially with attribution and state the conflict |
| apa_perigo | Perigo de inundação para IGT (PGRI 2.º ciclo, costeiras e fluviais) — `perigo` class, `local`, `designa` (ARPSI code) | APA (SNIAmb) | open (APA terms; confirm) | EPSG:3763 | 3 pilot regions (22+18+6 polygons) | PGRI 2022–2027 | ArcGIS REST `Visualizador/PGRI_2C_Perigo_IGT/MapServer/0`, GeoJSON export by bbox |
| apa_zonas_inundaveis | Zonas inundáveis por período de retorno (`pretorno` T0020/T0100/T1000) com `nivel_max` (m) | APA (SNIAmb) | open (APA terms; confirm) | EPSG:3763 | 3 pilot regions (3 372+526+381) | PGRI 2022–2027 | `Visualizador/PGRI_2C_Perigo_IGT/MapServer/1` |
| apa_arpsi | Zonas com risco potencial significativo de inundação (ARPSI) — `name`, `local` (ARH), `uomname` | APA (SNIAmb) | open (APA terms; confirm) | EPSG:3763 | 3 pilot regions (2+4+1) | Diretiva 2007/60/CE | `SNIAmb/Risco_Inundacao_Potencialmente_Significativas/MapServer/0` (the `Dashboard/pgri_med2c/2` ARPSI layer exports **no geometry**) |
| apa_marcas_cheia | Marcas de cheia históricas (SNIRH): `descricao`, `data`, `cota_inundacao`, `fonte` — points | APA (SNIAmb/SNIRH) | open (APA terms; confirm) | EPSG:3763 | 3 pilot regions (5+2+7 points) | historical | `SNIAmb/Marcas_cheias/MapServer/0` |
| ine_bgri2021 | BGRI 2021 (subsecções estatísticas) + Censos 2021 synthesis variables — one GPKG per municipality (`BGRI2021_<DICO>.gpkg`, layer `BGRI2021_<DICO>`, fields `BGRI2021, DTMN21, DTMNFR21, N_INDIVIDUOS, N_EDIFICIOS_CLASSICOS, N_ALOJAMENTOS_TOTAL, N_INDIVIDUOS_65_OU_MAIS, …`; dictionary `C2021_FSINTESE_VARIAVEIS.csv`) | INE | open data (INE terms) | EPSG:3763 | 3 pilot regions | Censos 2021 | per municipality: `https://mapas.ine.pt/download/filesGPG/2021/municipios/BGRI2021_<DICO>.zip` (confirmed 2026-09-26, e.g. Lisboa 1106 = 1.9 MB); metadata: `mapas.ine.pt/download/metadados/bgri.html` ("acesso e uso sem condições") |
| icnf_areas_ardidas | Áreas ardidas 1975–2025 — fire perimeters: `ano`, `area_ha` (whole fire, `AreaHaSIG`), from 2014 also start/end time, cause, parish of ignition | ICNF | CC BY 4.0 (dados.gov.pt `areas-ardidas-desde-1975`) | EPSG:3763 | 3 pilot regions (Cávado 2 876 · Coimbra 2 026 · Lisboa 15 polygons) | 1975–2025 (20 layers: `ardida_1975_1989`, `ardida_1990_1999`, `ardida_2000_2008`, `ardida_2009` … `ardida_2025`) | GeoServer WFS `https://si.icnf.pt/wfs/areas_ardidas` — `GetFeature&typeNames=BDG:<layer>&outputFormat=application/json&bbox=<region bbox>,urn:ogc:def:crs:EPSG::3763` (native EPSG:3763, no paging needed; confirmed 2026-09-26). The `si.icnf.pt/wfs/bdg` path in the backlog does not exist as such |
| icnf_areas_protegidas | Áreas protegidas: RNAP (`nome_ap`, `classifica`, `sigla`, diplomas `publica1/2`) + Rede Natura 2000 ZEC and ZPE (`site_code`, `site_name`) in one table (`rede`, `categoria`, `nome`, `codigo`, `diploma`) | ICNF | CC BY 4.0 (dados.gov.pt `rede-nacional-de-areas-protegidas-rnap`, `zonas-especiais-de-conservacao-sitios-da-diretiva-habitats-zec-sic-rn2000`, `zonas-de-protecao-especial-da-diretiva-aves-zpe-rn2000`) | EPSG:3763 | 3 pilot regions (Cávado 6 · Coimbra 17 · Lisboa 2 — RNAP 7, ZEC 12, ZPE 6) | limits in force, retrieved 2026-09-26 | WFS `https://si.icnf.pt/wfs/{rnap,zec,zpe}` (`BDG:rnap`, `BDG:zec`, `BDG:zpe`), same request pattern; `wfs/sic` = national SIC/ZEC list (not loaded) |
| dgt_crus | **Carta do Regime de Uso do Solo (CRUS)** — each PDM's ordinance plan re-coded to DR 15/2015: `classe` (Solo Urbano/Rústico), `categoria`, original PDM designation, scale, PDM publication date, source | DGT (from the municipal PDM) | CC BY 4.0 (dados.gov.pt `carta-do-regime-de-uso-do-solo-<município>`, 282 records) | EPSG:3763 | 26 pilot municipalities (25 of 26: Cávado 7 522 · Coimbra 11 950 · Lisboa 861 polygons; Mortágua missing — its WFS fails server-side; 6 PDMs not re-coded to DR 15/2015 (designation only, `esquema`)) | per municipality (`data_publicacao_pdm`) | GeoMedia WFS per municipality `https://servicos.dgterritorio.pt/SDISNITWFSCRUS_<DICO>_1/WFService.aspx`, feature type `gmgml:CRUS_<Name>_V` (read from GetCapabilities), GML 3.1.1 only; 8–60 s per call; cached in `data/raw/crus/` |
| ine_precos_habitacao | Valor mediano das vendas de alojamentos familiares nos últimos 12 meses (Metodologia 2022, €/m²), category Total — **municipality and parish rows** (`nivel`), `eur_m2` NULL where INE does not publish | INE | CC BY 4.0 (dados.gov.pt) | EPSG:3763 (geometry derived: CAOP municipality / union of BGRI 2021 subsections for the parish) | 3 pilot regions (166 rows: 26 municipalities + 140 parishes, 55 with a published value — Cávado 20/98, Coimbra 11/18, Lisboa 24/24) | 12 months to 1.º Trimestre de 2026 (INE update 2026-07-17) | INE JSON API indicator **0012234** (NUTS 2024): `https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2&varcd=0012234&Dim1=S5A20261&lang=PT` (quarter pinned); metadata `pindicaMeta.jsp?varcd=0012234`. `geocod` = NUTS III prefix + DICO/DICOFRE (2013 parishes) |
| ipma_rcm | Risco de incêndio rural (RCM) 1–5 per municipality: **live** in the agent; `open.ipma_rcm_snapshot` keeps dated forecasts (d0–d2 per run) as fallback/history | IPMA | open data (IPMA API, attribution) | — (joined to CAOP by `dico`) | pilot municipalities (26/day) | daily (`dataPrev`, `dataRun`) | `https://api.ipma.pt/open-data/forecast/meteorology/rcm/rcm-d{0,1,2}.json` — `.local[<DICO>].data.rcm`; DICO = CAOP `dtmn`. Codes per api.ipma.pt: 1 reduzido, 2 moderado, 3 elevado, 4 muito elevado, 5 máximo |
| osm_nominatim | Geocoding of addresses | OpenStreetMap contributors | ODbL (attribution) | EPSG:4326 | live | live | `https://nominatim.openstreetmap.org` (1 req/s, identify with User-Agent) |

## Optional (only if a vector download exists and time allows)

| id | Dataset | Publisher | Note |
|---|---|---|---|
| pdm_lisboa / pdm_coimbra | PDM ordinance plans | municipalities | **superseded by `dgt_crus`** (loaded 2026-09-26 for 25 pilot municipalities). The dados.gov.pt record `pdm-planta-de-qualificacao-do-solo-ordenamento` is **Cascais's**, not Lisbon's; Lisbon's hub lists no PDM vector |
| ren_ran | Reserva Ecológica / Agrícola Nacional | DGT (SNIT) / DGADR | check download vs WMS-only |

## Provenance in the database

Every loaded dataset gets one row in `open.dataset_meta` (id, title, publisher, licence, source_url,
reference_date, srid, retrieved_at, checksum, row_count). Every fact the agent returns carries the
`meta_id` it came from. That row is what the answer cites.

> First attempt used `Visualizador/parh/MapServer` layers 28/27: only 5 coarse ARPSI blocks in the pilot regions and no attributes. Replaced on 2026-09-26 by the four PGRI 2nd-cycle layers above (found by scanning the SNIAmb REST catalogue). `SNIAmb/ZonasAdjacentes_PubDR` has 0 features in the pilot regions.

## Backlog — candidate datasets, ranked (availability checked 2026-09-26 unless noted)

| Tier | Dataset | Why it matters | Source / format | Effort |
|---|---|---|---|---|
| 1 ✅ | **Áreas ardidas 1975–2025** (ICNF) — loaded as `icnf_areas_ardidas` | "did this burn, when, how often" — the strongest wildfire evidence | dados.gov.pt `areas-ardidas-desde-1975`; ICNF WFS `si.icnf.pt/wfs/bdg` (2020–2024 and older periods); geocatalogo `area_ardida` | low (polygons, clip per region) |
| 1 ✅ | **RNAP + Rede Natura 2000** (ICNF) — loaded as `icnf_areas_protegidas` | protected-area constraints (e.g. Pinhal de Ofir = Parque Natural do Litoral Norte) | geocatalogo `rnap`, `sig.icnf.pt` items; shapefile | low |
| 1 ✅ | **IPMA live** (RCM fire risk by DICO, weather warnings) — RCM join documented, snapshot `ipma_rcm_snapshot`; warnings not yet | today's condition, live REST | `api.ipma.pt/open-data/…` (already planned) | low |
| 1 ✅ | **INE median €/m² (12 months)** — loaded as `ine_precos_habitacao` | "what am I buying" context | dados.gov.pt / INE; freguesia level only for Grande Lisboa, Porto, Algarve and cities > 100k (Coimbra, Braga yes; Esposende municipality only) | low (table, join by DICOFRE) |
| 2 ✅ | **PDM classes (all pilot municipalities, via DGT CRUS)**; condicionantes still missing | the buildability question, at least in one region | dados.gov.pt `pdm-planta-de-qualificacao-do-solo-ordenamento`; `geodados-cml.hub.arcgis.com` (GeoJSON/SHP) | medium (nomenclature) |
| 2 ✅ | PDM Coimbra / Esposende / Braga | same, other regions | covered by `dgt_crus` (CRUS WFS per municipality); Mortágua's WFS fails | done |
| 2 | **REN / RAN** | legal constraints on building | CCDR / DGADR — **to check** (WFS vs WMS-only) | unknown |
| 2 | **OSM extract** (buildings, roads, water lines, POIs) for the 3 regions | distances to water/roads/services; building footprints | Geofabrik PBF → ogr2ogr/osm2pgsql; ODbL | medium |
| 2 | **DGT MDT / slopes** | slope classes for construction and fire; raster | DGT Centro de Dados (MDT), or Copernicus EU-DEM | medium (raster or precomputed classes) |
| 2 | **Cadastro predial (BUPi / DGT)** | parcel boundary and area | DGT OGC API collection "Cadastro Predial" — API timed out from our network 2026-09-26; coverage partial | uncertain |
| 3 | Zonamento sísmico (EC8 by concelho) | one more risk dimension, trivially joinable | table (Anexo Nacional NP EN 1998-1) | low |
| 3 | Servidões (aeroportuárias, linhas elétricas, gasodutos) | licensing constraints | ANAC / REN / operators — spotty | unknown |
| 3 | Geologia (LNEG), ruído, património (DGPC) | niche | mostly WMS | high |

Order of work if time allows before the window: ~~Tier 1 (all four)~~ and ~~PDM~~ done 2026-09-26 (CRUS for the pilot municipalities) → next REN/RAN, then OSM.

## International tiers (design; see docs/reasoning.md §5)

| Tier | Dataset | Access | Licence | Status |
|---|---|---|---|---|
| D | ESA WorldCover 2021 v200 (10 m land cover) | public COGs `https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_<N39W009>_Map.tif` (3°×3° tiles named by SW corner); live pixel via `gdallocationinfo -wgs84 /vsicurl/…` | CC BY 4.0 | **proven 2026-09-26** (Madrid/Coimbra/Esposende = 50 built-up; Guadarrama = 30) |
| D | JRC Global Flood Hazard maps (return periods 10–500 y, ~90 m) | JRC Data Catalogue, COG tiles — URL pattern TBD (guessed path returned 404) | open (JRC) | to confirm |
| D | GHSL population / built-up (100 m–1 km) | JRC, COG/GeoTIFF | open | design |
| D | NASA FIRMS active fires (375 m, near-real-time) | API (key) | open | design |
| D | WDPA / Protected Planet | download/API | **non-commercial without licence** | flag |
| C | Copernicus CLC+ / CORINE; EFFIS fire danger + burned areas; EEA Natura 2000; GISCO NUTS/LAU | downloads / WMS-WFS / COGs | open; GISCO non-commercial clause | design |
| B (Spain) | IGN/CNIG boundaries & BTN; SIOSE land use; **Catastro INSPIRE WFS (cadastral parcels)**; MITECO SNCZI flood zones; Natura 2000 ES | WFS / downloads | open (CC BY 4.0 / IGN terms) | design — first adapter after PT |
| B (Madrid) | `datos.madrid.es` (urban planning, green areas, noise…), `datos.comunidad.madrid` | portals, GeoJSON/SHP/WFS | open (check per dataset) | design |

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
| apa_arpsi | Áreas de Risco Potencial Significativo de Inundação, 2.º ciclo | APA (SNIAmb) | open (APA terms; confirm) | EPSG:3763 | 3 pilot regions (8+6+2) | PGRI 2022–2027 | `Dashboard/pgri_med2c/MapServer/2` |
| apa_marcas_cheia | Marcas de cheia históricas (SNIRH): `descricao`, `data`, `cota_inundacao`, `fonte` — points | APA (SNIAmb/SNIRH) | open (APA terms; confirm) | EPSG:3763 | 3 pilot regions (5+2+7 points) | historical | `SNIAmb/Marcas_cheias/MapServer/0` |
| ine_bgri2021 | BGRI 2021 (subsecções estatísticas) + Censos 2021 synthesis variables — one GPKG per municipality (`BGRI2021_<DICO>.gpkg`, layer `BGRI2021_<DICO>`, fields `BGRI2021, DTMN21, DTMNFR21, N_INDIVIDUOS, N_EDIFICIOS_CLASSICOS, N_ALOJAMENTOS_TOTAL, N_INDIVIDUOS_65_OU_MAIS, …`; dictionary `C2021_FSINTESE_VARIAVEIS.csv`) | INE | open data (INE terms) | EPSG:3763 | 3 pilot regions | Censos 2021 | per municipality: `https://mapas.ine.pt/download/filesGPG/2021/municipios/BGRI2021_<DICO>.zip` (confirmed 2026-09-26, e.g. Lisboa 1106 = 1.9 MB); metadata: `mapas.ine.pt/download/metadados/bgri.html` ("acesso e uso sem condições") |
| ipma_rcm | Daily rural fire risk index by municipality (RCM) | IPMA | open data (IPMA API) | — | live, national | daily | `https://api.ipma.pt/open-data/forecast/meteorology/rcm/rcm-d0.json` |
| osm_nominatim | Geocoding of addresses | OpenStreetMap contributors | ODbL (attribution) | EPSG:4326 | live | live | `https://nominatim.openstreetmap.org` (1 req/s, identify with User-Agent) |

## Optional (only if a vector download exists and time allows)

| id | Dataset | Publisher | Note |
|---|---|---|---|
| pdm_lisboa | PDM Lisboa — qualificação do espaço | CM Lisboa (Lisboa Aberta) | check open vector availability |
| pdm_coimbra | PDM Coimbra — planta de ordenamento | CM Coimbra | check open vector availability |
| ren_ran | Reserva Ecológica / Agrícola Nacional | DGT (SNIT) / DGADR | check download vs WMS-only |

## Provenance in the database

Every loaded dataset gets one row in `open.dataset_meta` (id, title, publisher, licence, source_url,
reference_date, srid, retrieved_at, checksum, row_count). Every fact the agent returns carries the
`meta_id` it came from. That row is what the answer cites.

> First attempt used `Visualizador/parh/MapServer` layers 28/27: only 5 coarse ARPSI blocks in the pilot regions and no attributes. Replaced on 2026-09-26 by the four PGRI 2nd-cycle layers above (found by scanning the SNIAmb REST catalogue). `SNIAmb/ZonasAdjacentes_PubDR` has 0 features in the pilot regions.

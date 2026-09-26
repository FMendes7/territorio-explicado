# Data sources

All datasets are open data. Each row is what the agent cites. `reference date` is the data's own
reference, `retrieved` is when we downloaded it (filled by `etl/download.sh` into `data/raw/MANIFEST.tsv`).
**Download URLs marked TODO are confirmed at download time and recorded in the manifest.**

| id | Dataset | Publisher | Licence | CRS | Scope loaded | Reference | Download |
|---|---|---|---|---|---|---|---|
| caop2025 | Carta Administrativa Oficial de Portugal 2025 (Continente) — GPKG layers `cont_freguesias` (3 049, fields `dtmnfr, freguesia, municipio, distrito_ilha, nuts3_cod, nuts3, area_ha`), `cont_municipios` (278, `dtmn, municipio, …`), `cont_distritos`, NUTS | DGT | CC BY 4.0 | EPSG:3763 | national | 2025 (published 2026-02-18) | `https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip` (111 MB, confirmed 2026-09-26; SNIG record `198497815bf647ecaa990c34c42e932e`; also OGC API `ogcapi.dgterritorio.gov.pt`) |
| cos2023 | Carta de Uso e Ocupação do Solo 2023 (vector, MMU 0.5 ha, 1:25k) | DGT / SMOS | CC BY 4.0 | EPSG:3763 | 3 pilot regions | 2023 | `https://geo2.dgterritorio.gov.pt/cos/S2/COS2023/COS2023v1-S2-gpkg.zip` (COS2023v1 Série 2, national GPKG; SNIG record `9a9c5548-eb27-48a2-b850-09d3c9069b2d`, confirmed 2026-09-26) |
| icnf_perigosidade | Carta de Perigosidade de Incêndio Rural (SRUP), 5 classes, vector from 25 m raster | ICNF via DGT / dados.gov.pt | CC BY 4.0 | EPSG:3763 | 3 pilot regions | 2022-03-28 (Aviso 6345/2022); check newer edition in ICNF geocatalog | **WFS** `https://servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1/WFService.aspx` (2.0.0, confirmed 2026-09-26; download by bbox with ogr2ogr). The zip advertised on the DGT page (`/download/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip`) returned **404** on 2026-09-26. ⚠️ Licence conflict: dados.gov.pt says CC BY 4.0; the ICNF geocatalogue metadata says consultation only / other uses need DGT authorisation → we use it non-commercially with attribution and state the conflict |
| apa_cheias | Zonas ameaçadas pelas cheias / áreas inundáveis (Diretiva 2007/60/CE) and zonas adjacentes | APA (SNIAmb) | open (APA terms; confirm) | EPSG:3857 (service) → 3763 | 3 pilot regions | PGRI 2022–2027 | ArcGIS REST `sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/parh/MapServer` layers 28 (Inundações) and 27 (Zonas adjacentes), GeoJSON export |
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

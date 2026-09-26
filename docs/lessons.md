# Lessons (pre-window rehearsal)

Non-obvious things learned while preparing data, connecting sponsor technology and building a private
throwaway prototype. **No code from the rehearsal is reused; this text is.**
Format: **observed → cause → what we do about it**. Short and specific.

## Data

- **INE BGRI zips are not directly readable by GDAL via `/vsizip/<zip>`** → each zip holds `BGRI2021_<DICO>.gpkg` **plus** a CSV dictionary, so GDAL cannot pick a driver for the archive root → open the inner file explicitly: `/vsizip/<zip>/BGRI2021_<DICO>.gpkg` (layer has the same name). Fields are uppercase (`N_INDIVIDUOS`, `N_EDIFICIOS_CLASSICOS`, `N_ALOJAMENTOS_TOTAL`); DICO is `DTMN21`.
- **The advertised fire-hazard zip is a 404** (`dgterritorio.gov.pt/download/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip`, 2026-09-26) → the WFS works and is better anyway (bbox download) → `WFS:https://servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1/WFService.aspx`.
- **The DGT SRUP WFS is unusable in practice (2026-09-26):** `GetFeature` with a bbox returns an OWS `ExceptionReport` ("An unexpected error occurred"), `resultType=hits` too, and GDAL's WFS driver hangs >3 min on a 12×13 km bbox; `-sql` on a WFS layer additionally disables the server-side BBOX filter (GDAL warning "layer names ignored in combination with -sql") → never use `-sql` with WFS. **Use the official zip instead**: `https://snit-mais.dgterritorio.gov.pt/SNIT/DOWNLOAD/SRUP/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip` (295 MB, 2022-04-08, listed as a resource on dados.gov.pt under `cc-by`), clipped per region locally. The ICNF ArcGIS service `sigservices.icnf.pt/server/rest/services/BDG/perigosidade_estrutural/MapServer` exposes only a **raster** layer 6 ("Perigosidade estrutural 2020-2030") — no feature queries; usable at most via `identify` for a single point, so it is not a bulk source.
- **That WFS publishes one feature type per hazard class** (`gmgml:Classe_de_Perigosidade_{Nula,Muito_Baixa,Baixa,Média,Alta,Muito_Alta}`), not one layer with a class attribute → loop the six, tag each with its class, merge; class order 0–5 is ours.
- **Licence texts disagree for the fire-hazard map**: dados.gov.pt says CC BY 4.0, the ICNF geocatalogue metadata says consultation-only/authorisation for other uses → cite both, use non-commercially with attribution, say so in the answer's provenance.
- **DGT OGC API (`ogcapi.dgterritorio.gov.pt`) timed out from our network** (60 s, twice) → do not depend on it; the static zips on `geo2.dgterritorio.gov.pt` are fast (CAOP 111 MB, COS2023v1 S2 898 MB).
- **Never read a large GeoPackage through `/vsizip/`** — with the 898 MB COS2023 zip, ogr2ogr sat at 100 % CPU decompressing sequentially and the GPKG R-tree was useless (2 373 features in 3 min); extracted to disk (1.5 GB, R-tree present, 783 760 multipolygons, fields `cos23_n4_c`, `cos23_n4_l`, `area_ha`) the per-region clip is a spatial-index lookup. Same for shapefiles: build a `.qix` (`ogrinfo … -sql "CREATE SPATIAL INDEX ON …"`, 2 s for 1.75 M polygons) before any `-spat`.
- **`-clipsrc` at region borders produces GeometryCollections** (polygon + sliver lines) that a MultiPolygon column rejects — GDAL warns "Insertion is likely to fail" and rows vanish silently inside a COPY batch → filter by bbox at the source (`-spat`), load whole features, then `DELETE … WHERE NOT ST_Intersects(pilot_regions)` in PostGIS. Faster too (no clipping arithmetic).
- **INE GeoPackages contain MultiSurface (curved) geometries** although the layer says MultiPolygon → `COPY` fails with "Geometry type (MultiSurface) does not match column type" → add `-nlt CONVERT_TO_LINEAR` next to `PROMOTE_TO_MULTI`.
- **PL/pgSQL `RETURN QUERY` is strict about `varchar` vs `text`** → cast every column of the evidence contract explicitly in `facts_at()`.
- **CAOP 2025 GPKG layer/field names** (not documented on the page): `cont_freguesias(dtmnfr, freguesia, municipio, distrito_ilha, nuts3_cod, nuts3, area_ha)`, `cont_municipios(dtmn, municipio, …)`. `dtmn` = INE DICO → the same code keys CAOP, INE files and IPMA RCM (`dico`).
- **The obvious APA layer is not the flood map.** `Visualizador/parh/MapServer/28` ("Inundações Diretiva 2007/60CE") gave 5 coarse ARPSI blocks with an opaque field name — nothing near Belém or the Choupal. Scanning the REST catalogue (`/rest/services?f=json`, then each folder) found the real thing: `Visualizador/PGRI_2C_Perigo_IGT` (layer 0 `perigo` classes; layer 1 flood extents per return period T20/T100/T1000 with `nivel_max`), `Dashboard/pgri_med2c/2` (ARPSI 2nd cycle) and `SNIAmb/Marcas_cheias` (historical flood marks with date and level). Lesson: list the catalogue before trusting a layer name; check counts in your bboxes before loading.
- **GDAL's GeoJSON driver sniffs field types from values**: the return-period code `T0100` became a `time` column (`01:00:00`) → open with `-oo DATE_AS_STRING=YES` (and check every code-like column after a load). Also: GDAL's HTTP reader hung >10 min on the SNIAmb ArcGIS export while `curl` got the same 1.2 MB in 1 s → download with curl, load from file.
- **APA flood layer 28 has opaque field names** (`geoapaouro_geoapaourodata_d312_`) and only 4 polygons in the Coimbra bbox → treat as "designated flood-risk areas (ARPSI)", not a flood-extent map; say that in the evidence.
- **Nominatim geocodes "Paço das Escolas, Coimbra" to the Porta Férrea** (40.2071, −8.4244), 200 m from where a human would click → geocoding is an evidence item with its own uncertainty, not ground truth.

## Global tier (live rasters)

- **Reading one pixel of a public COG is cheap enough to do at query time**: `GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR gdallocationinfo -valonly -wgs84 /vsicurl/<WorldCover tile> lon lat` answered in < 1 s for Madrid, Coimbra and Esposende (all 50 = built-up) and Guadarrama — zero storage, full provenance (URL + tile + date). The JRC flood-hazard COG path I guessed was a 404 → look the tile URLs up in the JRC Data Catalogue before relying on them.

## Zetaris

- **The self-hosted Freemium stack ships an MCP server**: `github.com/zetaris/Freemium` `docker-compose.yml` has `zetaris/genz-mcp:latest` (container `tools`, port 4200) next to `lightning-server` (Spark, ports 10000/9998/4040), `lightning-api` (8888/8889), `lightning-gui` (9001), Postgres 15, OpenSearch, `privateai` (Flask, 3001) and an Ollama image. Images live in a private registry → `docker login` with an account Zetaris activates within ~24 h (knowledge base) → **request access early**. Heavy (Spark + OpenSearch + Ollama): a laptop with ≥16 GB, not the 7.6 GB server. Fallback #2 after Zetaris Cloud Hobby.
- **The Claude Code plugin `aidg` is not on GitHub under `zetaris/`** (404 on 2026-09-26); the marketplace name in the guide is `zetaris/aidg` → probably a private/other-org marketplace; the tools-only route (`claude mcp add zetaris --transport http <url> --header "Authorization: Bearer <token>"`) does not need it.
- **Public Zetaris repos worth knowing:** `lightning-catalog` (open-source data catalog, updated 2026-09) — the catalog/metadata side of the platform.

## NVIDIA / Nemotron

- **Model ids on `integrate.api.nvidia.com/v1`** (confirmed 2026-09-26): `nvidia/nemotron-3-super-120b-a12b` (planner), `nvidia/nemotron-3-nano-30b-a3b` (worker), `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`; reasoning models take `enable_thinking` / `reasoning_budget` via `extra_body`.
- **Known pitfall (forum, 2026):** a personal organization on build.nvidia.com can lack the "Public API Endpoints" permission → 403 on Nemotron 3 Super even with a valid key → test Super on day one, keep Nano as the fallback planner.

## Meterless / H-MEM

- **The H-MEM reference has zero runtime dependencies** (only `tsx`/`vitest` for dev); `vendor/hmem` after `npm run setup` is 38 MB because of its own dev `node_modules` → vendor only `reference/src/*.ts` (10 files) into the app.
- **Wiring is small:** `new HMEM({ persistDir })`, `hmem.mine("chat_message", text)` (model-free mining path), `hmem.add({content, type, source})`, retrieval returns items with relevance + provenance ids; the trust ledger records `create` (confidence 0.7 default) and every `read` with timestamps → exactly the audit trail we want to show per recalled fact.
- **Relevance scores are weak on a tiny corpus** (top hit 0.14, off-topic hits 0.12) → in the agent, memory recall is an *evidence item with low weight*, never a fact source; require a live query to confirm.
- **`sleep --preview` is safe** (plans consolidation, applies nothing) → run it in the demo to show the memory lifecycle without risk.

## Agent design

- _(pending)_

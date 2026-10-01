# Lessons (pre-window rehearsal)

Non-obvious things learned while preparing data, connecting sponsor technology and building a private
throwaway prototype. **No code from the rehearsal is reused; this text is.**
Format: **observed → cause → what we do about it**. Short and specific.

## Rules and organizers' answers

- **Organizers' answers, 2026-10-01** (Discord, organizer `izzyOAP`, reply to our setup questions —
  `docs/discord-perguntas.md` §2): (1) Zetaris access — still being confirmed with Zetaris (hosted sandbox / MCP endpoint
  vs own Cloud account; whether the Hobby tier exposes MCP); answer to come on HackOS and in the Zetaris folder of
  Resources; the **Zetaris + Cursor workshop is on 12 Oct, 22:00 UTC (23:00 Lisbon)**. (2) Spatial push-down through
  Zetaris — passed to the Zetaris team; "flat views or precomputed tables as a fallback is a safe choice". (3) NVIDIA
  event credits and recommended Nemotron ids — being checked; NVIDIA is **not mandatory** (integrate it where it
  contributes). (4) The GenAI Agentic Protocol / AgentOS is not required; any language, framework, model or cloud;
  **every submission must integrate Zetaris and Meterless, and Cursor must be used for development**. (5) **Pre-existing
  components: our reading is right** — loading open geodata into PostGIS before the window and declaring it as a
  pre-existing data component in the submission form is fine; the agent must be built in the window and only window work
  is judged. (6) **A public URL is not required**: a GitHub repository with a README covering setup, usage and
  dependencies (a container image with one-command instructions works); a password-protected URL is fine if the access
  details go in the submission. Technical questions: the `#help-desk` channel on HackOS.
- **The binding rules changed after we read them on 27 Sep** (event page re-read 2026-10-01, text quoted in
  `docs/decisions.md`): three challenge tracks — Solving Fragmented Intelligence, **The Agent That Can Explain Why** (now
  listed second), Reasoning Architecture — plus the Wildcard [Tinkerer] bonus track (same criteria, must integrate
  Zetaris and Meterless, scored on the new work); "Connected Agent Context" is gone. §5 makes Zetaris **and** Meterless
  mandatory and Cursor mandatory for development; §6 adds a **slide deck** and a written explanation of how Zetaris and
  Meterless were integrated, how Cursor was used and where NVIDIA contributes, and sets the video at **1–4 minutes**
  (it must show the Zetaris and Meterless integration); §7 scores out of 100 with **no bonus points** (Impact 30,
  Technical 20, Innovation 15, Demo 15, Product & UX 10, Sponsor tech 10); §3 allows a track change any time before the
  deadline. Dates: registration closes 13 Oct 00:00 UTC, judging opens 20 Oct 00:00 UTC, submissions close 20 Oct
  23:45 UTC, results 30 Oct 16:00 UTC. → Re-read the event page before every plan change; the page, not our notes, is
  the rule.

## Data

- **INE BGRI zips are not directly readable by GDAL via `/vsizip/<zip>`** → each zip holds `BGRI2021_<DICO>.gpkg` **plus** a CSV dictionary, so GDAL cannot pick a driver for the archive root → open the inner file explicitly: `/vsizip/<zip>/BGRI2021_<DICO>.gpkg` (layer has the same name). Fields are uppercase (`N_INDIVIDUOS`, `N_EDIFICIOS_CLASSICOS`, `N_ALOJAMENTOS_TOTAL`); DICO is `DTMN21`.
- **The advertised fire-hazard zip is a 404** (`dgterritorio.gov.pt/download/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip`, 2026-09-26) → the WFS works and is better anyway (bbox download) → `WFS:https://servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1/WFService.aspx`.
- **The DGT SRUP WFS looked unusable (2026-09-26) — it was the request, not the server:** `GetFeature` with a bbox returns an OWS `ExceptionReport` ("An unexpected error occurred"), `resultType=hits` too, and GDAL's WFS driver hangs >3 min on a 12×13 km bbox; `-sql` on a WFS layer additionally disables the server-side BBOX filter (GDAL warning "layer names ignored in combination with -sql") → never use `-sql` with WFS. **Cause found 2026-09-27:** the server rejects the WFS 2.0.0 CRS form `urn:ogc:def:crs:EPSG::3763` ("GetCSFForEPSG: Invalid inputs"); the same request with `version=1.1.0` and `bbox=…,EPSG:3763` answers in 1.7 s (see "DGT GeoMedia WFS" below). **The zip stays the source** (complete, reproducible): `https://snit-mais.dgterritorio.gov.pt/SNIT/DOWNLOAD/SRUP/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip` (295 MB, 2022-04-08, listed as a resource on dados.gov.pt under `cc-by`), clipped per region locally. The ICNF ArcGIS service `sigservices.icnf.pt/server/rest/services/BDG/perigosidade_estrutural/MapServer` exposes only a **raster** layer 6 ("Perigosidade estrutural 2020-2030") — no feature queries; usable at most via `identify` for a single point, so it is not a bulk source.
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
- **The ICNF GeoServer WFS is the reliable one** (`si.icnf.pt/wfs/<service>`, 2026-09-26): answers in < 1 s, supports `resultType=hits`, a bbox in EPSG:3763 and `outputFormat=application/json` natively in EPSG:3763 — the opposite of the DGT SRUP WFS above. Services used: `areas_ardidas` (20 feature types: `ardida_1975_1989`, `ardida_1990_1999`, `ardida_2000_2008`, then one per year 2009–**2025**), `rnap`, `zec`, `zpe` (Natura 2000; `sic` is the national SIC/ZEC list). Same curl-then-ogr2ogr pattern as APA.
- **Burned-area layers do not share a schema**: the period layers and the yearly layers up to 2013 carry only `Ano` + `AreaHaSIG`; from 2014 they add start/end time, cause, parish of ignition, burned area by land type… → append with `ogr2ogr -addfields` into one raw table and select the common columns in PostGIS. The GeoJSON feature id (`ardida_2017.123`) does **not** survive — GDAL keeps only the numeric part in `id` → the source layer is derived from `Ano` (the period split is fixed), not parsed from the id.
- **The dados.gov.pt slug `pdm-planta-de-qualificacao-do-solo-ordenamento` is Cascais's PDM, not Lisbon's** (the backlog assumed Lisbon). Lisbon's hub (`geodados-cml.hub.arcgis.com`) lists no PDM layer and `dados.cm-lisboa.pt` sits behind a Cloudflare challenge. The national alternative is better anyway: **DGT's Carta do Regime de Uso do Solo (CRUS)** — the PDM *Planta de Ordenamento* re-coded into the classes/categories of DR 15/2015, keeping the original PDM designation, map scale and publication date — one WFS per municipality (`servicos.dgterritorio.pt/SDISNITWFSCRUS_<DICO>_1/WFService.aspx`), listed for 282 municipalities on dados.gov.pt (CC BY). Loaded for 25 of the 26 pilot municipalities instead of Lisbon only (Mortágua's WFS fails server-side, below).
- **CRUS WFS quirks (GeoMedia server)**: the feature type name changes per municipality (`CRUS_Lisboa_V`, `CRUS_Terras_de_Bouro_V`, accents stripped) → read it from `GetCapabilities`; GML only (no JSON); a whole municipality comes back in one `GetFeature` (Barcelos: 3 070 polygons, 11 MB, 12 s); each call takes 8–16 s and a municipality (capabilities + features) up to ~1 min, so the exports are cached in `data/raw/crus/`. The code field `DTCC` can be sniffed as an integer by the GML reader → `lpad(…, 4, '0')`. **Two schemas coexist**: PDMs already re-coded to DR 15/2015 carry `Classe`/`Categoria`/`Designacao_PlantaOrdenamento`/`Data_PublicacaoPDM`; older PDMs (6 of our 25: Barcelos, Esposende, Terras de Bouro, Vila Verde, Miranda do Corvo, Penela) only `Designacao_no_plano`/`Escala_origem`/`Data_Pub_Origem` — the first load left 36 % of polygons without a class because only one schema was selected → `-addfields` + `coalesce` over both, a `esquema` column, and the class is never inferred from the text. Per-municipality quirks inside the "same" schema: Figueira da Foz publishes class and category but **no** designation or PDM date; Cantanhede misspells the date field (`Data_PulicacaoPDM`) and uses `Area_HA` → check the field list of every file, not of one sample.
- **One municipality's CRUS WFS can be down while the other 25 answer**: Mortágua (`SDISNITWFSCRUS_1808_1`) returned an OWS `ExceptionReport` — *"Custom counters file view is out of memory"* (a server-side fault) — on GetCapabilities (2026-09-26, several tries); on 2026-09-27 it answered again (479 polygons, DR 15/2015 schema, 6.8 s) → cached and loaded: 26/26 municipalities. A server fault is a "retry later", not a gap to design around. And in our loader, `typ=$(curl … | grep … )` under `set -euo pipefail` **aborted the whole ETL silently** (exit 1, no WARN) because a failed command substitution in an assignment trips `set -e` → every "optional" network probe inside `$(…)` gets `|| true` and an explicit check after it.
- **INE parish codes are pre-2025**: indicator 0012234 (median €/m², 12 months, NUTS 2024) keys parishes by the 2013 map — `geocod` = NUTS III prefix (3 chars) + DICO (4) or DICOFRE (6, sometimes with letters such as `0302FG`). CAOP 2025 already has the 2025 parish split (138/140 codes match); BGRI 2021 `DTMNFR21` matches 140/140 → the parish price polygon is the union of its BGRI 2021 subsections, not a CAOP 2025 parish.
- **INE JSON API**: the metadata endpoint lists category codes as `H.1` but the data uses `H1` → a `Dim3=H.1` filter is rejected ("Code(s) in Dim3 not valid"); fetch the quarter (`Dim1=S5A20261`) and filter locally. Calls take 1–70 s and time out intermittently → `curl --retry`, pin the quarter for reproducibility. 238 of 931 values are suppressed ("Dado nulo ou não aplicável"); in the pilot regions only 55 of 140 published parishes have a value.
- **IPMA RCM** (`api.ipma.pt/open-data/forecast/meteorology/rcm/rcm-d{0,1,2}.json`) is keyed by DICO — the same code as CAOP `dtmn` — with `rcm` 1–5 (reduzido, moderado, elevado, muito elevado, máximo, per the API page). The agent must read it live; the database keeps only a dated snapshot as a fallback.
- **COS has a 2025 edition and two series** (checked 2026-09-26): dados.gov.pt `carta-de-uso-e-ocupacao-do-solo-cos-serie-2-2018v4-2025v1` (COS2018v4 and COS2025v1, Série 2, same nomenclature as COS2023, published July 2026) and `…-serie-1-1995v2-2018v2` (1995/2007/2010/2015/2018, older nomenclature). Zips are 0.6–0.9 GB; the level-1 class is the first segment of the n4 code in both series, so a 1995 → 2025 trajectory is only comparable at level 1. The `cos/S1/…` folders answer 403 (no listing) — take the file names from the dados.gov.pt record.
- **DGT flew a national LiDAR in 2024**: MDT/MDS at 50 cm and 2 m (CC BY), 1 km × 1 km tiles (~1 MB each at 2 m). The data-centre API is STAC-like: `POST https://cdd.dgterritorio.gov.pt/dgt-be/v1/search` with `{"collections":["MDT-2m"],"bbox":[…]}` answers without login (GET redirects to `/auth/login`), but every asset `…/dgt-be/v1/download/<hash>` needs an account (302 to the login) → the true-terrain slope waits for a (free) DGT account. Login is Keycloak (OpenID Connect, realm `dgterritorio`, client `aai-oidc-dgt`, authorization code + PKCE, checked 2026-09-27) — a scripted download has to walk the browser login with a cookie jar (password read from the vault, never on the command line); items added to the web "Downloads" list expire after 24 h. A search answers one page only (no paging links): Lisbon's bbox alone is 209 tiles of 1 km² (~1 MB each, Float32, nodata −999). The same flight produced a national **building footprint map** (`geo2.dgterritorio.gov.pt/lidar/MConst_LiDAR2024_PTcont-gpkg.zip`, 751 MB, open).
- **Copernicus DEM GLO-30 is a surface model**: public COGs on `copernicus-dem-30m.s3.amazonaws.com` (1° × 1° tiles, no login) — good as a global fallback and for elevation, but X-band radar sees canopy and roofs, so slope in forests and towns is biased → every slope fact says so; resampled to 25 m in EPSG:3763 a 0.4 ha plot is ~6 pixels → the pixel count travels with the answer.
- **One feature, three regions — a wrong region TAG, not a wrong geometry** (2026-09-27): some sources store a class as a few huge multipolygons — COS 1995 level-1 "Territórios artificializados" (`1.0.0.0`) is ONE feature of 22 parts from Lisbon to Braga (409 706 vertices, 1 481 holes); COS 2018/2023/2025 do the same for the road network (`1.5.1.1`) and estuary water (`9.3.4.1`), ICNF for "sem perigosidade" (9 features in 3 layers). Trimmed to the pilot municipalities that feature measured 110.5 km² = 63.4 (Lisboa) + 28.4 (Coimbra) + 18.7 (Cávado), and the loader stamped ONE region on it (Coimbra) → coverage per region showed 1995 Lisbon at 37 of 100 km², and QA reported ~111 km² "outside the region". A first diagnosis blamed GEOS 3.9.0 (clipping against Lisboa alone gave the "right" 63 km² — which is just the Lisbon part); it was wrong: a re-run with that "workaround" produced the identical 110.5 km² row, and `ST_Dump` + area per region explained it in one query. Point lookups were never affected (`facts_at` filters by geometry, not by region tag). Fix: `trim_to_regions` splits every feature that touches several regions into one copy per region. **Before blaming the engine, decompose the "wrong" geometry**; and check coverage per region and per edition after every load — counts alone would not show it. The same QA run found a real second defect: trimming only features that *touch* the pilot boundary misses a multipolygon whose separate island lies wholly outside (16 flood-extent and 3 burned-area features) → trim what is "not covered by its region", not what "touches the boundary". Pre-fix baseline (both defects mixed): 32 features in 6 layers, 213 km² outside their tagged region.
- **`ST_DWithin(a, b, 0)` is not a cheap `ST_Intersects`**: same answer, but on the 409 706-vertex polygon PostGIS's distance code ran > 120 s per municipality (cancelled; the cancel itself took 136 s to be honoured) while `ST_Intersects` answered for all 9 municipalities in 0.8 s → the loader keeps a feature with `ST_Intersects` and uses `ST_DWithin` only for points with a real margin. A `pg_cancel_backend` is only honoured between library calls — a backend stuck inside one long GEOS/liblwgeom call keeps running.
- **ogr2ogr writes source FIDs without advancing the sequence**: a GeoPackage's `fid` becomes the table's primary key with a sequence still at 1 → any later `INSERT` relying on the default collides ("duplicate key … cos2023_pkey"). Copies made by the loader set the key explicitly (`max(pk) + row_number()`).
- **A killed session can leave its query running**: when the editor restarted, the ETL's bash/psql died but the server backend kept executing the orphaned `DELETE` for 12+ min (a backend only notices a dead client when it next writes to it) → long ETL runs are started with `setsid nohup` so an editor restart does not kill them, and after a crash look at `pg_stat_activity` before re-running.
- **Locale bites numeric scripts**: under `pt_PT` `awk` printed `-57552,1` (decimal comma) and `gdalwarp -te` failed with "Too few arguments" → `LC_ALL=C` for every tool that formats numbers inside the ETL.
- **Same series, different generalisation**: COS2023 v1 (older release) has ~8.5 ha mean polygons, COS2018 v4 and COS2025 v1 (July 2026 release) ~6.1 ha, with identical coverage → comparing boundaries across releases invents changes; the trajectory compares the dominant class per plot or cell, and change detection prefers 2018v4 ↔ 2025v1 (same release).
- **DGT GeoMedia WFS (SNIT: CRUS, SRUP) — speak WFS 1.1.0**: `version=1.1.0&typeName=gmgml:<Type>&bbox=x0,y0,x1,y1,EPSG:3763` works; the 2.0.0 form with `urn:ogc:def:crs:EPSG::3763` (what GDAL's WFS driver sends) fails with "GetCSFForEPSG: Invalid inputs", also with `resultType=hits` or a FES filter. That is how **REN and RAN turned out to be open vector data** (dados.gov.pt `srup-reserva-ecologica-nacional`, `srup-reserva-agricola-nacional`, CC BY): REN has one WFS per CCDR (`SDISNITWFSSRUP_REN_{NORTE,CENTRO,LVT,ALENTEJO,ALGARVE}`, plus a `Linhas_de_Agua_*` line layer), RAN one national (`SDISNITWFSSRUP_RAN_PT1`). One feature = a municipality's whole REN (or its **"Exclusões"**, areas taken out of it) with the diploma (e.g. `AVISO 9514/2026/2`, DR `81 IIS`), deposit number, CCDR, map scale, geometry date and a link to the official PDF (`snit-mais.dgterritorio.gov.pt/SRUP/<diploma>.pdf` — the path has spaces, `%20` works, HTTP 200 checked). RAN carries only the municipality NAME in capitals (no DICO) and a date. Braga's REN geometry is dated 2026-09-09 → these are live, maintained layers. Caveats: "outside the REN polygons" ≠ "outside the REN" where the watercourse lines are not published; a neighbour's REN touches the shared border → keep only each pilot municipality's own features before trimming. Coverage of the 26 pilot municipalities (2026-09-27): REN 25 — **Condeixa-a-Nova (0604) is in neither the CCDR Centro WFS nor the national `REN_Nacional` one**, while all its neighbours are; RAN 25 — none for Lisboa. Watercourse lines exist only where the delimitation publishes them (e.g. Soure, Coimbra, Miranda do Corvo, Penela; not Montemor-o-Velho) → each of these gaps is answered "not available — not consulted", never "not in REN/RAN".
- **The `postgis/postgis` image has no `raster2pgsql`** (neither on PATH nor in `/usr/lib/postgresql/16/bin`; Debian ships it in the separate `postgis` client package) — the loader's `docker run … raster2pgsql` fallback had never run → rasters are loaded client-side: `\lo_import` the GeoTIFF, `ST_Tile(ST_FromGDALRaster(lo_get(oid), 3763), 100, 100, true, -32768)`, `lo_unlink` (needs `SET postgis.gdal_enabled_drivers = 'GTiff'`); 42 tiles in 0.22 s for Lisbon; `ST_Value` matched `gdallocationinfo` at the test point.
- **The LiDAR 2024 building map is footprints only**: 4 166 655 polygons for mainland Portugal in one 1.76 GB GeoPackage (`MConst_LiDAR_PT`, fields `id`, `area_m2`; the zip's `…_secciona.gpkg` is the sheet index) — no height, use or date per building → it answers "is there a building here / how built-up is it / how far to the nearest one", not "how tall" (height would come from the LiDAR MDS − MDT, which needs the DGT account).
- **A computed argument can switch an index off**: the raster `ST_Intersects(rast, geom)` is a SQL function that PostgreSQL inlines (and then uses the tile index) only if each argument is simple; `ST_Intersects(d.rast, ST_Centroid(c.geom))` was not inlined, every cell scanned the aspect tiles and the Santo Varão grid (349 cells) took 3.4–4.5 s. Computing the centroid once as a column (`c.ctr`) restored the index (that join 1.9 s → 0.1 s; whole grid 0.39–0.49 s, measured 2026-09-27) → pass columns, not expressions, to raster predicates, and `EXPLAIN` any new lateral join (a `count(*)` probe lies: the planner drops a LEFT JOIN LATERAL it does not need).
- **Area questions are cheap, neighbourhood grids are not**: `facts_for()` on a 7 ha plot answers in 0.24 s; `constraints_grid()` with ~350 cells of 50 m takes 3–9 s, dominated by `ST_Intersects`/`ST_Intersection` against a few huge polygons (flood extents, protected areas) → subdivide those layers (`ST_Subdivide`) into helper tables before the window. Measured 2026-09-27 on 349 cells: fire hazard 3 653 → 26 ms, flood extent 1 065 → 3 ms, dominant COS 2 356 → 29 ms, dominant PDM 889 → 30 ms, same answer in every cell (dominant class = GROUP BY class ORDER BY summed area, because one polygon becomes several pieces).
- **The DGT data centre's STAC is open, its downloads are not — and every asset link is a one-time token**: `POST cdd.dgterritorio.gov.pt/dgt-be/v1/search` (collection `MDT-2m`) answers without login, in one page (no `next` links); each search returns a *new* `…/download/<hash>` per tile, and a link works **once** — the loader's login check downloaded tile 1 to prove the session and that tile's real download then got HTTP 403 (2026-09-27). So: list right before downloading, never test-download, and record the stable STAC item URL (`…/collections/MDT-2m/items/<id>`, public) in the manifest instead of the token.
- **Keycloak login from a script is four requests**: GET `/auth/login` with a cookie jar (the site starts OIDC + PKCE and keeps the verifier in its own session cookie) → parse `#kc-form-login`'s `action` (HTML-unescape `&amp;`) → POST `username`, `password`, `credentialId` with `curl -L` (the 302 after the POST becomes a GET back to `/auth/callback`) → success = the final URL is back on the site. The password goes in through a process substitution (`--data-urlencode password@<(bw get password …)`), never argv; `"password@<(…)"` in double quotes is NOT a process substitution (bash leaves it literal).
- **A vault entry can be "found" and still be useless**: `bw get item` matched the DGT entry but its username field was empty, so `bw get username` printed `Not found.` and the form got an empty login → check each field separately and say which one is missing.
- **A catalogue that lists a tile is not proof the file exists**: the MDT collection lists all 1 405 Cávado tiles (flight 07-2025, published Nov 2025) but whole rectangular blocks answer HTTP 404 — the collection description still says "Zona Noroeste ainda indisponível". The functions fall back to Copernicus there and say so per fact; coverage per municipality is in `data/sources.md`.
- **In the LiDAR MDT, sea and river water are 0 m, not nodata** (Tagus tiles are all 0; coastal tiles 0 at sea) → a coastal cell's mean slope is diluted by flat water and the Copernicus fallback never triggers at sea; `-999` only marks areas outside the flight.
- **`gdaldem` writes −9999 for "no data" AND, in aspect, for "flat"** → the nodata mask must come from the elevation raster (`gdal_calc … where(A == -32768, -32768, B)` with `--hideNoData`), or a flat parking lot and the sea outside the tiles become the same value.
- **Surface vs terrain, measured** (Lisbon golden points, Copernicus GLO-30 → DGT MDT 10 m): Monsanto forest 175 → 165 m (≈ 10 m of canopy), Alcântara blocks 15 → 7 m (buildings), Parque das Nações slope 11 → 6 %, Praça do Comércio 3 → 4 m. The surface model inflated slope in towns and read tree tops in forests — exactly what the label warned.
- **A raster table without raster constraints can take the database down**: opening `dem_mdt_slope` (5 778 tiles, no `AddRasterConstraints`) with QGIS's `postgresraster` provider made one backend grow to 12.5 GB until the kernel OOM-killed it; the postmaster then restarted every session (a 50-minute QA run died with it; recovery itself took < 1 s, nothing lost). On the server the container has 900 MB. So: relief is read point- or plot-wise through the SQL functions (`ST_Value`, `ST_Clip`), maps use the local GeoTIFFs, and no client opens the relief tables as a whole raster.
- **Nominatim geocodes "Paço das Escolas, Coimbra" to the Porta Férrea** (40.2071, −8.4244), 200 m from where a human would click → geocoding is an evidence item with its own uncertainty, not ground truth.

- **Never let a UI parse the evidence text** (rehearsal, 2026-09-28): the throwaway explorer turned each fact's English
  `value` into a PT card title with regular expressions over the sentences `schema.sql` writes. It failed silently:
  `RCM (\d) — ([^ ]+)` expected a one-word class, so every "muito elevado" fire-risk forecast (two words) fell back
  to the raw English sentence on the Portuguese page, and four plot facts (burn history in %, census, "no building
  inside the plot", coverage) never had a pattern at all. The SQL now writes the status next to the raw columns —
  `level`, `label_pt`/`label_en`, `tag_pt`/`tag_en`, `caveat` — and `value` stays byte-identical for the agent (golden
  diff = 0 over 694 lines). A reader that meets an older database without the columns may keep the regex as a fallback.
- **The biggest share is not the headline** (rehearsal, 2026-09-28): the summary showed each card's largest row, so
  a plot 58 % "low" and 18 % "high – very high" flood hazard read as low. A card's reading is its strongest row
  (status first, then share) — `docs/ux.md` §6.1.
- **`ST_CoveredBy(feature, region)` never uses a prepared geometry; `ST_Covers(region, feature)` does** (PostGIS 3.4.3,
  GEOS 3.9, 2026-09-30): the trim of 944 917 building footprints against the new 46 944-vertex `lisboa_tejo` region ran
  for > 1 h at 100 % of one core; on a 4 424-building sample `ST_CoveredBy` took 33.5 s (7.6 ms each), `ST_Covers` 0.10 s,
  with 0 differences — same predicate, only one side is cached. The QA stage had the same pattern (~50 min for 3
  regions, hours with the new one): three tables went from 4 min 04 s to 10.9 s, same counts → loader and QA use
  `ST_Covers(region, x)`, and the QA runs one region per query so the region stays the same row after row.
- **A DEFLATE GeoTIFF written block by block into strips bloats** (2026-09-30): `gdal_calc.py` reads A in its 256×256
  tiles and rewrote each output strip once per tile column, appending a new compressed copy each time — the `lisboa_tejo`
  aspect Int16 file came out at **1.66 GB** for 286 MB of raw pixels, and the loader's `lo_get` (1 GB `bytea` limit)
  failed: "large object read request is too large", leaving a 1.58 GB orphan large object in the database. With
  `TILED=YES` the same file is 94 MB, 11 s instead of ~2 min, identical values → every Int16 output is tiled; after a
  failed raster load, check `pg_largeobject_metadata` for orphans.
- **The DGT SRUP WFS fails on a large bbox** (2026-09-30): `REN_LVT` over the whole `lisboa_tejo` bbox (120 × 119 km,
  ~35 municipalities of whole-municipality multipolygons) answered with an HTML error page after ~10 min, while the
  same service returned the RAN and the REN watercourse lines for that bbox → when the region request fails the loader
  asks once per municipality bbox (`<typ>_<region>__m<DICO>.gml`, cached; duplicates removed by the hash dedupe and
  the DICO filter).
- **Three traps loading the SRUP pack from GML** (2026-09-30): (1) GDAL's GML reader downloads the XSD named in
  `schemaLocation`; the DGT answered 502 and ogr2ogr waited with 0 % CPU and no HTTP timeout → `-oo DOWNLOAD_SCHEMA=NO
  --config GDAL_HTTP_TIMEOUT 60` (types guessed from the data); (2) `to_jsonb(row)` converts the geometry column to
  GeoJSON, which has no curves → the classified-heritage layer (`MultiSurface`) failed ("GeoJson: geometry not
  supported") → attributes from a `LATERAL` row of the non-geometry columns, geometry through `ST_CurveToLine`; (3) some
  features have no `gml:id` and the NOT NULL `gml_id` column made the COPY fail → `-forceNullable`.
- **A GML read without its XSD is typed by its FIRST file — and appending the next file corrupts silently** (2026-09-30,
  evening): with `-oo DOWNLOAD_SCHEMA=NO` GDAL guesses each field's type and width from the file it reads (and pins them in
  a `.gfs` sidecar). The SRUP pack loads two files per type (`lisboa`, then `lisboa_tejo`) into one table: the second
  file's longer texts were cut to the first file's widths (`DESIGNACAO` 149 → 126 characters, `SERV_HIPERLINK` 67 → 65 —
  broken links to the diplomas) and its decimals turned into integers (`z_desobstrucao_m` 34.5 → 34, `area_ha` 50.0013 →
  50, `codigo_ccdr` "3, 4" → 3; 19 + 26 GDAL warnings nobody read); the CRUS municipality name became `varchar(8)` from
  Mealhada ("ESPOSENDE" → "ESPOSEND" in the golden facts). → `-lco PRECISION=NO` (unsized text) on every appended GML,
  and for the SRUP `--config GML_FIELDTYPES ALWAYS_STRING -oo WRITE_GFS=NO` (every attribute kept as the published text; a
  leftover `.gfs` overrides the option, so none may sit next to the cached GML). Read the loader's warnings: "Lossy
  conversion" and "parsed incompletely" are data loss, not noise.
- **The DGT's XSD request can hang the whole CRUS load** (2026-09-30): the CRUS GML names its schema as a
  DescribeFeatureType URL on the DGT server; that evening it answered 0 bytes in 25 s and GDAL waited ~2 min per
  municipality before falling back (55 municipalities ≈ 1 h 50). → no XSD download for the CRUS either, with an HTTP
  timeout; the same server later stopped answering GetCapabilities (40 s timeouts) → the SRUP GetCapabilities responses
  are cached, and when they cannot be fetched the stage reuses the types already loaded, with a WARN.
- **Older PDMs overlap their neighbours far more than a sample suggested** (2026-09-30): measured over all 55
  municipalities, ≈ 2 050 ha of CRUS polygons lay outside their own municipality (CAOP 2025) in 26 municipality-region
  pairs — Palmela 340 ha, Azambuja 233, Rio Maior 208, Chamusca 202, Alpiarça 201, Barreiro 179 … — against ~3.5 km²
  noted from the first look. Each plan is now clipped to its own municipality before trimming (0 ha outside after the
  fix, no golden fact changed). Measure a known issue over everything before sizing it.
- **A national feature that reaches another pilot region stays there** (2026-09-30): `trim_to_regions` keeps whatever
  touches ANY pilot region, so the Tejo "rio de 1.ª ordem" SRUP polygon left 17 ha tagged `coimbra` (Pampilhosa da
  Serra) and the Linha do Norte two rail segments in Coimbra, although Tier 2 was agreed for the Lisbon study area only →
  `keep_study_area` after the trim.
- **Index names survive `ALTER TABLE … RENAME`** (2026-09-30): ogr2ogr names the primary key and the spatial index after
  the scratch table (`_ruido_pkey`, `_ruido_geom_geom_idx`); after renaming the table to `ruido_mapas` they kept those
  names, and the next run's `_ruido` collided ("relation already exists") → rename the indexes with the table.
- **`ogr2ogr` refuses `-spat_srs` together with `-sql`** ("-spat_srs not compatible with -sql"): give `-spat` in the
  layer's own SRS instead (the APA shapefiles are EPSG:3763, the groundwater bodies EPSG:4326).
- **Open data that is not reachable by a script** (2026-09-30): the CM Lisboa noise map (`.7z` on dados.cm-lisboa.pt)
  sits behind a JavaScript challenge — HTTP 403 to curl with any user agent — so noise is known in Oeiras only;
  `download.geofabrik.de` resolved to IPv6 addresses that did not answer from the laptop (30 s timeout), IPv4 fine →
  `curl -4`; the GitHub API rate limit (60 requests/hour unauthenticated) was reached after a few directory listings —
  the raw file URLs are not limited the same way.
- **A licence can be stated where the catalogue says "not specified"** (2026-09-30): the dados.gov.pt record for the AML
  schools (TML) says "not specified", but its source repository, `github.com/carrismetropolitana/datasets`, carries an
  ODbL 1.0 LICENSE → check the publisher's own repository before treating a dataset as unusable.
- **E-REDES publishes substation capacity without coordinates** (2026-09-30): the hosting-capacity and substation-load
  tables name the installation and its municipality only; the installation code starts with the municipality's DICO. A
  point comes from OSM only when one substation with the same name lies in that municipality (104 of 128 in the study
  area; a spot check of 18 matches was right in all 18) — the rest stay "known by municipality", never guessed.
- **A published geometry can be wrong while its attributes are right** (2026-09-30): the TML OGC API collection
  `gtfs_stops` puts all 12 702 Carris Metropolitana stops on one point, (−8.1332, 39.6686) — the origin of PT-TM06, i.e.
  (0, 0) converted as if it were metres — while `stop_lat`/`stop_lon` are correct. The first load kept 50 of 12 752 stops
  (the Metro's) and nothing failed: `tag_points` silently dropped every stop "outside" the study area → count per source
  after each load, and check that points are not all identical.
- **A map service can answer queries without geometry** (2026-09-30): the LNEG acceleration areas (PAER) return
  attributes (parish, municipality, area) for every query, with `returnGeometry=true` too, but no shapes — view-only; the
  lower-sensitivity areas on the next service do return polygons. Test a real query with geometry before listing a source
  as loadable.
- **Small tool traps met the same night**: `psql -c` never interpolates `:var` (only stdin does) → heredocs for SQL with
  psql variables; the GDAL GTFS driver declares no CRS → `-s_srs EPSG:4326` (GTFS is WGS 84 by specification); GDAL's
  OAPIF driver asks for `crs=http://…/EPSG/0/3763` and the TML server only lists `https://…` (HTTP 400) → page the API
  by hand; `-fieldTypeToString All` when appending one GeoJSON page after another (each page is typed on its own).
- **A licence can live in a third place — search the national catalogue by title, not only the service** (2026-10-01):
  the LNEG lower-sensitivity areas were marked "licence not stated" because the map service says nothing; the dataset's
  own dados.gov.pt record (created 2023-01-25, updated 2025-12-23, pointing to the same `AreasCandidatasRenovaveis`
  service) says **CC BY 4.0**. The same search found CC BY for the LNEG geological maps at 1:500 000, 1:1 000 000 and the
  AML 1:100 000. And the opposite trap: the LNEG geoPortal's legal notice says "free use with the source cited, no
  commercial use" and, a paragraph later, no display or distribution "for any public or commercial purpose" without
  written consent; the DGEG solar-plant service's capabilities say CC BY-NC 4.0 while its dados.gov.pt record says CC BY
  4.0. → record every statement found, with where it was found; where they conflict, apply the stricter and say so (as
  for the fire-hazard map); the decision to show a layer stays the author's.
- **"CC BY" on a record is not "loadable"** (2026-10-01): the LNEG geological map of the AML at 1:100 000 is CC BY on
  dados.gov.pt, but its only resources are two sheet images (JPG and PDF); and the continuous 1:200 000 vector prototype
  (CC BY, 21 272 polygons nationally) covers **1 km² of the 7 512 km² study area** — measured by loading the envelope
  and intersecting, not by reading its description. The 1:500 000 map (5th edition, 1992) covers 7 510 km² and is the
  one loaded: a regional reading (0.5 mm on the map = 250 m on the ground), never a foundation fact for a plot — the
  golden probe in the Tejo estuary water off Vila Franca de Xira reads "Aluviões" on it.
- **One national multipolygon per class again** (2026-10-01): the LNEG 1:500 000 map stores each lithostratigraphic unit
  as one multipolygon for the whole mainland (282 rows; 77 meet the study-area envelope) — the same shape as COS 1995
  (2026-09-27); `trim_to_regions` splits and trims them, and GDAL warns "organizePolygons() received a polygon with more
  than 100 parts" while reading the ESRI JSON (slow, not wrong).

## Global tier (live rasters)

- **Reading one pixel of a public COG is cheap enough to do at query time**: `GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR gdallocationinfo -valonly -wgs84 /vsicurl/<WorldCover tile> lon lat` answered in < 1 s for Madrid, Coimbra and Esposende (all 50 = built-up) and Guadarrama — zero storage, full provenance (URL + tile + date). The JRC flood-hazard COG path I guessed was a 404 → look the tile URLs up in the JRC Data Catalogue before relying on them.

## Zetaris

- **The self-hosted Freemium stack ships an MCP server**: `github.com/zetaris/Freemium` `docker-compose.yml` has `zetaris/genz-mcp:latest` (container `tools`, port 4200) next to `lightning-server` (Spark, ports 10000/9998/4040), `lightning-api` (8888/8889), `lightning-gui` (9001), Postgres 15, OpenSearch, `privateai` (Flask, 3001) and an Ollama image. Images live in a private registry → `docker login` with an account Zetaris activates within ~24 h (knowledge base) → **request access early**. Heavy (Spark + OpenSearch + Ollama): a laptop with ≥16 GB, not the 7.6 GB server. Fallback #2 after Zetaris Cloud Hobby.
- **The Claude Code plugin `aidg` is not on GitHub under `zetaris/`** (404 on 2026-09-26); the marketplace name in the guide is `zetaris/aidg` → probably a private/other-org marketplace; the tools-only route (`claude mcp add zetaris --transport http <url> --header "Authorization: Bearer <token>"`) does not need it.
- **Public Zetaris repos worth knowing:** `lightning-catalog` (open-source data catalog, updated 2026-09) — the catalog/metadata side of the platform.

## NVIDIA / Nemotron

- **Model ids on `integrate.api.nvidia.com/v1` change under you** (probed 2026-09-27 with a 1-token request on our key): `nvidia/nemotron-3-super-120b-a12b` → 200 (planner); `nvidia/nemotron-3-nano-30b-a3b` → **410 Gone** (the worker id noted the day before, retired); `nvidia/nemotron-nano-3-30b-a3b` → 404 although `/v1/models` lists it; `nvidia/nemotron-3.5-lightning-30b-a3b` → 200 (**new worker**); `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` → 503. → the model list is not proof of service: probe every id with a 1-token call before a run, keep ids in `.env` (`MODEL_PLANNER`/`MODEL_WORKER`), and log the id used in every eval result. Reasoning models take `enable_thinking` / `reasoning_budget` via `extra_body`.
- **Known pitfall (forum, 2026):** a personal organization on build.nvidia.com can lack the "Public API Endpoints" permission → 403 on Nemotron 3 Super even with a valid key → test Super on day one (our personal org: 200 on 2026-09-27), keep the small model (Lightning) as the fallback planner.

## Meterless / H-MEM

- **The H-MEM reference has zero runtime dependencies** (only `tsx`/`vitest` for dev); `vendor/hmem` after `npm run setup` is 38 MB because of its own dev `node_modules` → vendor only `reference/src/*.ts` (10 files) into the app.
- **Wiring is small:** `new HMEM({ persistDir })`, `hmem.mine("chat_message", text)` (model-free mining path), `hmem.add({content, type, source})`, retrieval returns items with relevance + provenance ids; the trust ledger records `create` (confidence 0.7 default) and every `read` with timestamps → exactly the audit trail we want to show per recalled fact.
- **Relevance scores are weak on a tiny corpus** (top hit 0.14, off-topic hits 0.12) → in the agent, memory recall is an *evidence item with low weight*, never a fact source; require a live query to confirm.
- **`sleep --preview` is safe** (plans consolidation, applies nothing) → run it in the demo to show the memory lifecycle without risk.

## Agent design

- _(pending)_

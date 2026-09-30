# Data — what is loaded, from where, how to rebuild it, and its limits

Declared pre-existing (see [`../PRE-EXISTING.md`](../PRE-EXISTING.md)). Every dataset's publisher, licence, reference
date and download URL: [`sources.md`](sources.md). No personal data: census and prices are aggregates.

## Subset

- **National:** administrative boundaries (CAOP 2025).
- **Four regions, 55 municipalities** (`regioes.json`): CIM Região de Coimbra (19), Cávado (6), the municipality of
  Lisbon (1) and, since 2026-09-30, `lisboa_tejo` — the other 29 municipalities of the Lisbon study area for site
  selection (AML, Lezíria do Tejo, Vendas Novas; 7 512 km² with Lisbon). Every other layer is clipped to them; a feature
  that spans regions is split into one copy per region.
- Anywhere else the agent answers "outside the pilot regions — unknown", never "nothing here".

## Tables (schema `open`, local database, counted 2026-09-30)

| Group | Table | Rows |
|---|---|---:|
| Boundaries | `caop_freguesias` · `caop_municipios` | 3 049 · 278 |
| Pilot regions | `pilot_regions` · `pilot_region_union` · `pilot_union` | 55 · 4 · 1 |
| Land cover | `cos2023` · `cos_serie` (1995 · 2018 · 2025) | 134 330 · 461 948 |
| Fire | `icnf_perigosidade` · `icnf_areas_ardidas` (1975–2025) · `ipma_rcm_snapshot` | 258 770 · 8 490 · 243 |
| Water | `apa_perigo_inundacao` · `apa_zonas_inundaveis` · `apa_arpsi` · `apa_marcas_cheia` | 54 · 6 021 · 9 · 60 |
| Planning | `dgt_crus` · `dgt_ren` · `dgt_ren_linhas` · `dgt_ran` · `icnf_areas_protegidas` | 45 565 · 82 · 23 · 53 · 52 |
| Buildings | `dgt_construcoes` (LiDAR 2024 footprints: Cávado 177 929 · Coimbra 263 983 · Lisboa 15 120 · lisboa_tejo 487 885) | 944 917 |
| People and prices | `ine_bgri2021` · `ine_precos_habitacao` | 50 399 · 289 |
| Relief (raster tiles) | `dem_mdt_elev` · `dem_mdt_slope` · `dem_mdt_aspect` (DGT MDT, 10 m) · `dem_elev` · `dem_slope` · `dem_aspect` (Copernicus, 25 m) | 14 002 each · 2 465 each |
| Provenance | `dataset_meta` | 22 |
| Grid copies (`ST_Subdivide`) | `grid_perigosidade` · `grid_cos` · `grid_crus` · `grid_ren` · `grid_zonas_inundaveis` · `grid_ran` · `grid_ardidas` · `grid_perigo_inundacao` · `grid_ren_linhas` · `grid_protegidas` · `grid_arpsi` | 329 579 · 270 730 · 147 426 · 70 193 · 57 634 · 25 136 · 21 677 · 12 554 · 7 133 · 1 578 · 822 |

40 tables, 3 678 MB on disk locally (including the grid copies and update bloat); `pg_dump -Fc -n open` = 1 865 MB
(2026-09-30). REN is published for 42 of 55 municipalities and RAN for 53 of 55 (`sources.md`): a municipality without
it answers "not available", never "outside".

## Rebuild

1. `etl/download.sh` — downloads each source into `raw/` and records URL, timestamp, size and sha256 in
   `raw/MANIFEST.tsv`; skips files whose checksum already matches.
2. `etl/load.sh` — loads, clips to the pilot regions, splits features per region; its stage `qa` asserts that every
   geometry lies inside its tagged region (1 m tolerance).
3. `schema.sql` and `views.sql` — lookup functions (`facts_at`, `facts_for` / `facts_in`, `constraints_grid`, relief)
   and flat views for federation. The fact functions return the evidence (`value`, English, plus `sql_hint`, `meta_id`,
   geometry, shares) and its status (`level`, `label_pt`, `label_en`, `tag_pt`, `tag_en`, `caveat` — semantics in the
   `facts_at` comment). A server whose functions belong to a non-superuser role gets `schema.sql` run by the superuser
   in one transaction (`psql -1`), then `ALTER FUNCTION … OWNER TO <role>` for every function in schema `open` — the
   role cannot run `CREATE SCHEMA IF NOT EXISTS`, and a changed return type is a DROP + CREATE.

`raw/` and `tmp/` are git-ignored: tens of GB of source files, reproducible with the scripts.

## Sample for reviewers (built inside the window)

`data/sample/`: the municipality of the main demo plot plus the areas of the golden cases, dumped from `open`, target
< 50 MB (GitHub warns above 50 MB). Used by `docker compose up` and by `SAMPLE_MODE=true`; a place outside the sample
answers "outside the sample".

## Limitations (details in [`../docs/failure-modes.md`](../docs/failure-modes.md))

- **REN / RAN:** no REN delimitation published for Condeixa-a-Nova and no RAN for Lisboa → "not consulted", never
  "outside" (failure mode 21).
- **PDM:** CRUS gives the harmonised class and category of each municipal plan, not its full ordinance (failure mode 12).
- **Flood:** APA maps cover the studied stretches only; outside them is "not mapped", not "safe" (failure mode 4).
- **Relief:** Copernicus GLO-30 is a surface model — canopy and buildings included (failure mode 17).
- **Fire hazard:** the licence metadata disagrees between portals (CC BY 4.0 vs consultation only) → non-commercial use
  with attribution (failure mode 3).
- **IPMA fire risk:** the database holds a dated snapshot; the agent reads the live index (failure mode 14).
- **Census and prices:** BGRI 2021 counts cannot be spread by area (failure mode 16); INE suppresses the median price
  where there were too few sales (failure mode 11).

# Data — what is loaded, from where, how to rebuild it, and its limits

Declared pre-existing (see [`../PRE-EXISTING.md`](../PRE-EXISTING.md)). Every dataset's publisher, licence, reference
date and download URL: [`sources.md`](sources.md). No personal data: census and prices are aggregates.

## Subset

- **National:** administrative boundaries (CAOP 2025).
- **Three pilot regions, 26 municipalities** (`regioes.json`): CIM Região de Coimbra, Cávado and the municipality of
  Lisbon. Every other layer is clipped to them; a feature that spans regions is split into one copy per region.
- Anywhere else the agent answers "outside the pilot regions — unknown", never "nothing here".

## Tables (schema `open`, local database, counted 2026-09-27)

| Group | Table | Rows |
|---|---|---:|
| Boundaries | `caop_freguesias` · `caop_municipios` | 3 049 · 278 |
| Pilot regions | `pilot_regions` · `pilot_region_union` · `pilot_union` | 26 · 3 · 1 |
| Land cover | `cos2023` · `cos_serie` (1995 · 2018 · 2025) | 65 686 · 227 841 |
| Fire | `icnf_perigosidade` · `icnf_areas_ardidas` (1975–2025) · `ipma_rcm_snapshot` | 124 328 · 4 917 · 78 |
| Water | `apa_perigo_inundacao` · `apa_zonas_inundaveis` · `apa_arpsi` · `apa_marcas_cheia` | 32 · 3 209 · 5 · 9 |
| Planning | `dgt_crus` · `dgt_ren` · `dgt_ren_linhas` · `dgt_ran` · `icnf_areas_protegidas` | 20 812 · 45 · 12 · 25 · 25 |
| Buildings | `dgt_construcoes` (LiDAR 2024 footprints) | 457 032 |
| People and prices | `ine_bgri2021` · `ine_precos_habitacao` | 21 482 · 166 |
| Relief (raster tiles) | `dem_elev` · `dem_slope` · `dem_aspect` | 1 088 each |
| Provenance | `dataset_meta` | 21 |
| Grid copies (`ST_Subdivide`) | `grid_cos` · `grid_crus` · `grid_perigosidade` · `grid_ren` · `grid_zonas_inundaveis` · `grid_ran` · `grid_ardidas` · `grid_perigo_inundacao` · `grid_ren_linhas` · `grid_protegidas` · `grid_arpsi` | 137 971 · 82 367 · 154 989 · 42 540 · 28 382 · 15 507 · 14 086 · 3 885 · 2 774 · 528 · 36 |

37 tables, 1 731 MB on disk (including the grid copies and update bloat); `pg_dump -Fc -n open` ≈ 827 MB.

## Rebuild

1. `etl/download.sh` — downloads each source into `raw/` and records URL, timestamp, size and sha256 in
   `raw/MANIFEST.tsv`; skips files whose checksum already matches.
2. `etl/load.sh` — loads, clips to the pilot regions, splits features per region; its stage `qa` asserts that every
   geometry lies inside its tagged region (1 m tolerance).
3. `schema.sql` and `views.sql` — lookup functions (`facts_at`, `facts_for` / `facts_in`, `constraints_grid`, relief)
   and flat views for federation.

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

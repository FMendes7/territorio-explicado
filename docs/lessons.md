# Lessons (pre-window rehearsal)

Non-obvious things learned while preparing data, connecting sponsor technology and building a private
throwaway prototype. **No code from the rehearsal is reused; this text is.**
Format: **observed → cause → what we do about it**. Short and specific.

## Data

- **INE BGRI zips are not directly readable by GDAL via `/vsizip/<zip>`** → each zip holds `BGRI2021_<DICO>.gpkg` **plus** a CSV dictionary, so GDAL cannot pick a driver for the archive root → open the inner file explicitly: `/vsizip/<zip>/BGRI2021_<DICO>.gpkg` (layer has the same name). Fields are uppercase (`N_INDIVIDUOS`, `N_EDIFICIOS_CLASSICOS`, `N_ALOJAMENTOS_TOTAL`); DICO is `DTMN21`.
- **The advertised fire-hazard zip is a 404** (`dgterritorio.gov.pt/download/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip`, 2026-09-26) → the WFS works and is better anyway (bbox download) → `WFS:https://servicos.dgterritorio.pt/SDISNITWFSSRUP_CPIR_PT1/WFService.aspx`.
- **That WFS publishes one feature type per hazard class** (`gmgml:Classe_de_Perigosidade_{Nula,Muito_Baixa,Baixa,Média,Alta,Muito_Alta}`), not one layer with a class attribute → loop the six, tag each with its class, merge; class order 0–5 is ours.
- **Licence texts disagree for the fire-hazard map**: dados.gov.pt says CC BY 4.0, the ICNF geocatalogue metadata says consultation-only/authorisation for other uses → cite both, use non-commercially with attribution, say so in the answer's provenance.
- **DGT OGC API (`ogcapi.dgterritorio.gov.pt`) timed out from our network** (60 s, twice) → do not depend on it; the static zips on `geo2.dgterritorio.gov.pt` are fast (CAOP 111 MB, COS2023v1 S2 898 MB).
- **CAOP 2025 GPKG layer/field names** (not documented on the page): `cont_freguesias(dtmnfr, freguesia, municipio, distrito_ilha, nuts3_cod, nuts3, area_ha)`, `cont_municipios(dtmn, municipio, …)`. `dtmn` = INE DICO → the same code keys CAOP, INE files and IPMA RCM (`dico`).
- **APA flood layer 28 has opaque field names** (`geoapaouro_geoapaourodata_d312_`) and only 4 polygons in the Coimbra bbox → treat as "designated flood-risk areas (ARPSI)", not a flood-extent map; say that in the evidence.
- **Nominatim geocodes "Paço das Escolas, Coimbra" to the Porta Férrea** (40.2071, −8.4244), 200 m from where a human would click → geocoding is an evidence item with its own uncertainty, not ground truth.

## Zetaris

- _(pending)_

## NVIDIA / Nemotron

- _(pending)_

## Meterless / H-MEM

- _(pending)_

## Agent design

- _(pending)_

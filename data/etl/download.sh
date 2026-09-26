#!/usr/bin/env bash
# data/etl/download.sh — fetch the open datasets into data/raw/ and write a manifest
# What: downloads each source listed in data/sources.md, records URL, timestamp, size and sha256 in
#       data/raw/MANIFEST.tsv. Idempotent: skips files whose checksum already matches.
# Depends on: curl, sha256sum; network access to DGT/ICNF/APA/INE endpoints (URLs below).
# Used by: data/etl/load.sh (expects the files named here) — run this first.
# When changing: keep the manifest columns stable (id, url, file, retrieved_at, bytes, sha256); the
#       agent's provenance rows (open.dataset_meta) are built from it.
set -euo pipefail
RAW="$(cd "$(dirname "$0")/../.." && pwd)/data/raw"
mkdir -p "$RAW"
MANIFEST="$RAW/MANIFEST.tsv"
[ -f "$MANIFEST" ] || printf 'id\turl\tfile\tretrieved_at\tbytes\tsha256\n' > "$MANIFEST"

# id  url  local-file  — URLs marked TODO are filled in at first real download (see data/sources.md)
SOURCES=(
  "caop2025|https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip|caop2025_continente_gpkg.zip"
  "cos2023|TODO_COS2023_URL|cos2023.zip"
)

fetch() {
  local id="$1" url="$2" file="$3" dest="$RAW/$3"
  if [[ "$url" == TODO* ]]; then echo "SKIP $id — URL not confirmed yet ($url)"; return; fi
  echo "GET  $id ← $url"
  curl -fL --retry 3 -o "$dest" "$url"
  local bytes sha; bytes=$(stat -c %s "$dest"); sha=$(sha256sum "$dest" | cut -d' ' -f1)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$url" "$file" "$(date -u +%FT%TZ)" "$bytes" "$sha" >> "$MANIFEST"
}

for s in "${SOURCES[@]}"; do IFS='|' read -r id url file <<< "$s"; fetch "$id" "$url" "$file"; done

# INE BGRI 2021: one GeoPackage zip per municipality (DICO code). Codes come from data/regioes.json
# (dico_hint) — load.sh cross-checks them against CAOP.
mkdir -p "$RAW/bgri2021"
for dico in $(jq -r '.regions[].municipalities[].dico_hint' "$(dirname "$RAW")/regioes.json"); do
  [ -s "$RAW/bgri2021/BGRI2021_$dico.zip" ] && continue
  fetch "ine_bgri2021_$dico" "https://mapas.ine.pt/download/filesGPG/2021/municipios/BGRI2021_$dico.zip" "bgri2021/BGRI2021_$dico.zip"
done

# ICNF/DGT fire hazard (SRUP): the advertised zip is 404 (2026-09-26); the WFS works. Downloaded by bbox
# of the pilot regions in load.sh via ogr2ogr (WFS driver), after CAOP gives us the extent.
echo "icnf_perigosidade: fetched via WFS in load.sh (servicos.dgterritorio.pt SDISNITWFSSRUP_CPIR_PT1)"

# APA flood layers come from an ArcGIS REST service (GeoJSON export, paged). Bbox = pilot regions,
# EPSG:4326, filled by load.sh from CAOP once loaded; here we fetch the national layer metadata only.
APA="https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/parh/MapServer"
curl -fsS "$APA/28?f=json" -o "$RAW/apa_layer28_meta.json" && echo "GET  apa layer 28 metadata"
curl -fsS "$APA/27?f=json" -o "$RAW/apa_layer27_meta.json" && echo "GET  apa layer 27 metadata"
echo "done → $MANIFEST"

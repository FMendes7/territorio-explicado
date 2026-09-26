#!/usr/bin/env bash
# data/etl/download.sh — fetch the open datasets into data/raw/ and write a manifest
# What: downloads each source listed in data/sources.md, records URL, timestamp, size and sha256 in
#       data/raw/MANIFEST.tsv. Idempotent: skips files whose checksum already matches.
# Depends on: curl, sha256sum, jq; network access to DGT/ICNF/APA/INE endpoints (URLs below).
# Used by: data/etl/load.sh (expects the files named here) — run this first. WFS/REST/API layers that need the
#       pilot-region bboxes (APA, ICNF WFS, DGT CRUS, IPMA) are fetched by load.sh itself and recorded in the
#       same manifest (load.sh manifest_add).
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
  "cos2023|https://geo2.dgterritorio.gov.pt/cos/S2/COS2023/COS2023v1-S2-gpkg.zip|cos2023.zip"
  "icnf_perigosidade|https://snit-mais.dgterritorio.gov.pt/SNIT/DOWNLOAD/SRUP/CARTA_PERIGOSIDADE_INCENDIO_RURAL/PERIGOSIDADE_INCENDIO_RURAL.zip|icnf_perigosidade.zip"
  # INE indicator 0012234 (median €/m², last 12 months, NUTS 2024 down to parish), quarter pinned (Dim1) so the
  # file is reproducible; the INE JSON API is slow (≈70 s) and times out now and then → curl --retry
  "ine_precos_habitacao|https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2&varcd=0012234&Dim1=S5A20261&lang=PT|ine_precos_0012234_S5A20261.json"
  # COS time series (stage cos_serie): Série 2 shares COS2023's nomenclature (2018v4 · 2023v1 · 2025v1, comparable
  # class by class); Série 1 (1995…2018) uses the older one → 1995 is compared at level 1 only. dados.gov.pt records
  # carta-de-uso-e-ocupacao-do-solo-cos-serie-2-2018v4-2025v1 and …-serie-1-1995v2-2018v2 (CC BY, checked 2026-09-26)
  "cos2025|https://geo2.dgterritorio.gov.pt/cos/S2/COS2025/COS2025v1-S2-gpkg.zip|cos2025.zip"
  "cos2018|https://geo2.dgterritorio.gov.pt/cos/S2/COS2018/COS2018v4-S2-gpkg.zip|cos2018.zip"
  "cos1995|https://geo2.dgterritorio.gov.pt/cos/S1/COS1995/COS1995v2-S1-gpkg.zip|cos1995.zip"
)

fetch() {
  local id="$1" url="$2" file="$3" dest="$RAW/$3"
  if [[ "$url" == TODO* ]]; then echo "SKIP $id — URL not confirmed yet ($url)"; return; fi
  if [ -s "$dest" ]; then
    grep -q "^$id	" "$MANIFEST" && { echo "HAVE $id ($file)"; return; }
    echo "HAVE $id ($file) — adding to manifest"
  else
    echo "GET  $id ← $url"
    curl -fL --retry 3 -C - -o "$dest" "$url"
  fi
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

# ICNF/DGT fire hazard (SRUP): the zip linked on the DGT page is 404 and the WFS is broken (2026-09-26);
# the working official file is the SNIT download listed on dados.gov.pt (295 MB shapefile, 2022-04-08),
# fetched above in SOURCES and clipped per region by load.sh.

# APA flood layers come from an ArcGIS REST service (GeoJSON export, paged). Bbox = pilot regions,
# EPSG:4326, filled by load.sh from CAOP once loaded; here we fetch the national layer metadata only.
APA="https://sniambgeoogc.apambiente.pt/getogc/rest/services/Visualizador/parh/MapServer"
curl -fsS "$APA/28?f=json" -o "$RAW/apa_layer28_meta.json" && echo "GET  apa layer 28 metadata"
curl -fsS "$APA/27?f=json" -o "$RAW/apa_layer27_meta.json" && echo "GET  apa layer 27 metadata"
echo "done → $MANIFEST"

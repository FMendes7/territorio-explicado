#!/usr/bin/env bash
# data/etl/ren_cartas.sh — REN charts as IMAGES for the municipalities the DGT REN WFS leaves empty (view-only backdrop)
# What: the author chose (2026-10-01) to show, where no REN polygons are published, the official REN chart as an image
#       labelled "REN chart (image) — not measured" (decision in docs/decisions.md; layer snit_ren_carta in
#       data/site_profiles.json). The DGT's per-municipality WMS (SDISNITWMSREN_<DICO>_1) is the georeferenced source, but
#       its GetMap did not answer on 2026-10-01 (60–90 s, 0 bytes, while GetCapabilities did) → this script fetches the
#       chart images the DGT's SNIT-SGT portal serves (api/Easement/GetEasementsAsync → listRasters[].finalImageName) into
#       data/raw/ren_snit/ and, ONLY for charts whose image is the municipality with a uniform halo, writes a GeoTIFF
#       (EPSG:3763) by fitting the image to the CAOP 2025 extent of the municipality: one scale s (m/px) and one margin
#       h (px) from W = dx/s + 2h and H = dy/s + 2h. Checked by overlaying the CAOP boundary (2026-10-01): Loures and
#       Salvaterra de Magos fit; Amadora is approximate; Alpiarça and Sesimbra do not (irregular halo / a rectangular
#       sheet) and Coruche is nine sheets — those need ground control points by hand (QGIS Georeferencer) or the WMS.
# Depends on: curl, jq, gdalinfo, gdal_translate (GDAL ≥ 3.6), psql + PG_DSN (open.caop_municipios); manifest_add's
#       column layout of data/raw/MANIFEST.tsv. Network: snit-sgt.dgterritorio.gov.pt.
# Used by: the author / the window's UI (a raster backdrop); nothing in the database reads it.
# Ao mexer: SNIT terms — "consulta e visualização, sendo interdita a sua comercialização": the images and GeoTIFFs stay
#       in data/raw/ (git-ignored), are never committed, never put in the sample extract and never measured; a fit is
#       never a survey — the GeoTIFF carries the method in its metadata. Add a municipality to FIT only after an overlay
#       check.
set -euo pipefail
export LC_NUMERIC=C   # awk/printf would write "6,142" under a pt_PT locale and gdal_translate would reject it
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; RAW="$ROOT/data/raw"; OUT="$RAW/ren_snit"
: "${PG_DSN:?set PG_DSN=postgresql://user@host:port/db (password via PGPASSWORD/.pgpass)}"
API="https://snit-sgt.dgterritorio.gov.pt/api/Easement/GetEasementsAsync"
ALL="1107 1115 1404 1409 1415 1511"   # Loures, Amadora, Alpiarça, Coruche, Salvaterra de Magos, Sesimbra (charts as images)
FIT="${FIT:-1107 1415}"                # charts whose CAOP fit was checked by overlay (2026-10-01)
mkdir -p "$OUT"
# same row layout and replace-by-id as load.sh's manifest_add (id, url, file, retrieved_at, bytes, sha256)
manifest_add() {
  local id="$1" url="$2" f="$3" M="$RAW/MANIFEST.tsv"
  [ -f "$M" ] || printf 'id\turl\tfile\tretrieved_at\tbytes\tsha256\n' > "$M"
  awk -F'\t' -v id="$id" '$1 != id' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$url" "${f#"$RAW"/}" "$(date -u +%FT%TZ)" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" >> "$M"
}
for d in $ALL; do
  j=$(curl -4 -sS --max-time 90 -H "Content-Type: application/json" -H "LanguageId: pt" -X POST \
        -d "{\"regionsMunicipalitiesSelected\":[\"$d\"],\"statusSelected\":1}" "$API")
  for url in $(jq -r '.[].listRasters[]?.finalImageName // empty' <<< "$j"); do
    f="$OUT/$(basename "$url")"
    id="ren_carta_$(basename "$url" .jpg)"
    if [ ! -s "$f" ]; then
      curl -4 -sS --max-time 300 -o "$f.part" "$url" && mv "$f.part" "$f" && manifest_add "$id" "$url" "$f"
    elif ! awk -F'\t' -v id="$id" '$1 == id { found = 1 } END { exit !found }' "$RAW/MANIFEST.tsv"; then
      manifest_add "$id" "$url" "$f"   # fetched by hand before the script existed
    fi
    echo "   $d $(basename "$f") $(stat -c %s "$f") bytes"
  done
done
for d in $FIT; do
  # one chart per municipality is fitted: the first listed raster (Amadora's second image is a detail sheet)
  f=$(ls "$OUT"/REN"$d"_*.jpg 2>/dev/null | grep -v _porm | head -1); [ -n "$f" ] || { echo "WARN: no chart for $d"; continue; }
  read -r W H < <(gdalinfo -json "$f" | jq -r '.size | "\(.[0]) \(.[1])"')
  read -r X0 Y0 X1 Y1 < <(psql "$PG_DSN" -Atc "SELECT ST_XMin(e)||' '||ST_YMin(e)||' '||ST_XMax(e)||' '||ST_YMax(e) FROM (SELECT ST_Extent(geom) e FROM open.caop_municipios WHERE dico = '$d') s")
  read -r ULX ULY LRX LRY S M < <(awk -v W="$W" -v H="$H" -v x0="$X0" -v y0="$Y0" -v x1="$X1" -v y1="$Y1" 'BEGIN {
    dx = x1 - x0; dy = y1 - y0; s = (dy - dx) / (H - W); h = (W - dx / s) / 2
    printf "%.2f %.2f %.2f %.2f %.3f %.1f\n", x0 - h * s, y1 + h * s, x1 + h * s, y0 - h * s, s, h }')
  t="${f%.jpg}_3763.tif"
  gdal_translate -q -of COG -co COMPRESS=JPEG -co QUALITY=90 -a_srs EPSG:3763 -a_ullr "$ULX" "$ULY" "$LRX" "$LRY" \
    -mo "SOURCE=DGT SNIT-SGT $(basename "$f") (consultation and visualisation only)" \
    -mo "GEOREFERENCE=approximate: image fitted to the CAOP 2025 extent of municipality $d (scale $S m/px, margin $M px), checked by overlay 2026-10-01" \
    "$f" "$t"
  echo "   $d → $(basename "$t") (scale $S m/px, margin $M px)"
done

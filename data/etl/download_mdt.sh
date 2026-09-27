#!/usr/bin/env bash
# data/etl/download_mdt.sh — DGT LiDAR 2024 terrain model (MDT, 2 m) tiles for the pilot municipalities
# What: `list` — STAC search on the DGT data centre (open, no login) per pilot-municipality bbox, keeps the tiles
#       within 100 m of a municipality (PostGIS, so slope at the boundary sees its neighbours) → data/raw/mdt2m/
#       tiles.tsv (id, url, bytes, region). `get` — logs into the data centre (Keycloak OIDC + PKCE driven by the
#       site's own /auth/login; the password comes from the Vaultwarden entry $DGT_VW_ENTRY through `bw get` inside a
#       process substitution — never argv, env, file or log; the username from the same entry, else DGT_USER — not a
#       secret), downloads every tile that is not on
#       disk with the STAC size, rejects anything that is not a TIFF, re-logs in when the session expires, then
#       writes data/raw/mdt2m/MANIFEST.tsv (id, url, file, retrieved_at, bytes, sha256 — data/raw/MANIFEST.tsv's
#       columns; url = the public STAC item, because the asset link is a per-search token) from the files on disk.
#       Every `get` pass re-runs `list` first (fresh tokens, ~50 s). Resumable: re-run the same command after a failure.
# Depends on: curl, jq, sha256sum, od; `list`: psql + PG_DSN (open.pilot_regions; read from .env.local when unset);
#       `get`: bw with BW_SESSION unlocked in the calling terminal, gdalinfo (size-mismatch check); network to
#       cdd.dgterritorio.gov.pt and auth.cdd.dgterritorio.gov.pt. MDT tiles are 1 km² Float32 GeoTIFFs, EPSG:3763,
#       nodata −999, ~1 MB each (6 224 tiles / 6.47 GB for the 26 municipalities, counted 2026-09-27).
# Used by: operator, once per data refresh (pre-window data preparation, declared in PRE-EXISTING.md); load.sh
#       stage relevo_mdt reads data/raw/mdt2m/tiles.tsv and the .tif files.
# When changing: the contract with DGT is (a) STAC POST /dgt-be/v1/search returns everything in one page (no next
#       links; limit 5000 covers one municipality; every search mints new one-time asset links — a link used once
#       answers 403), (b) an unauthenticated asset URL answers 302 → /auth/login,
#       (c) the Keycloak form #kc-form-login posts username/password/credentialId. If any breaks, `get` stops with
#       LOGIN FAILED or AUTH and keeps no partial file. Never add `set -x`: it would log the form action URL, which
#       carries the Keycloak session code.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; OUT="$ROOT/data/raw/mdt2m"; mkdir -p "$OUT"
BASE=https://cdd.dgterritorio.gov.pt; STAC="$BASE/dgt-be/v1/search"; STAC_ITEMS="$BASE/dgt-be/v1/collections/MDT-2m/items"
TILES="$OUT/tiles.tsv"; JAR="$OUT/.cookies"; PAR="${PAR:-4}"   # 4 parallel downloads: polite to a public server
STAGE="${1:-all}"

stac_list() {
  if [ -z "${PG_DSN:-}" ] && [ -f "$ROOT/.env.local" ]; then set -a; . "$ROOT/.env.local"; set +a; fi
  : "${PG_DSN:?set PG_DSN (list stage reads open.pilot_regions)}"
  local tmp; tmp=$(mktemp -d)
  psql "$PG_DSN" -Atc "SELECT dico, ST_XMin(b)||','||ST_YMin(b)||','||ST_XMax(b)||','||ST_YMax(b)
                       FROM (SELECT dico, ST_Transform(ST_Envelope(geom), 4326)::box2d b FROM open.pilot_regions) x ORDER BY 1" |
  while IFS='|' read -r dico bb; do
    curl -fsS -m 180 --retry 2 -X POST "$STAC" -H 'Content-Type: application/json' \
      -d "{\"collections\":[\"MDT-2m\"],\"bbox\":[$bb],\"limit\":5000}" > "$tmp/r.json"
    n=$(jq '.features | length' "$tmp/r.json"); [ "$n" -lt 5000 ] || { echo "ERROR: $dico hit the 5000 limit — split the bbox"; exit 1; }
    echo "   $dico: $n tiles in bbox"
    jq -r '.features[] | [.id, .assets.data.href, .properties["file:size"], (.geometry | tostring)] | @tsv' "$tmp/r.json" >> "$tmp/all.tsv"
  done
  sort -u -t$'\t' -k1,1 "$tmp/all.tsv" > "$tmp/uniq.tsv"
  psql "$PG_DSN" -q -v ON_ERROR_STOP=1 <<SQL
CREATE TEMP TABLE stac (id text, href text, bytes bigint, gj text);
\copy stac FROM '$tmp/uniq.tsv' WITH (FORMAT text)
\copy (SELECT DISTINCT ON (s.id) s.id, s.href, s.bytes, p.region FROM stac s JOIN open.pilot_regions p ON ST_DWithin(ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(s.gj), 4326), 3763), p.geom, 100) ORDER BY s.id, p.region) TO '$TILES'
SQL
  LC_ALL=C awk -F'\t' '{n[$4]++; b[$4]+=$3} END {for (r in n) printf "   %s: %d tiles, %.2f GB\n", r, n[r], b[r]/1e9}' "$TILES" | sort
  echo "tiles.tsv: $(wc -l < "$TILES") tiles"; rm -rf "$tmp"
}

# login — fresh cookie jar, GET /auth/login (the site starts the PKCE flow and keeps the verifier in its own session
# cookie), POST the credentials to the form action, follow the redirects back to /auth/callback. Prints nothing secret.
login() {
  [ "$(bw status 2>/dev/null | jq -r .status)" = unlocked ] || { echo "LOGIN FAILED: vault locked in this terminal — export BW_SESSION=\$(bw unlock --raw)"; return 1; }
  bw get item "$DGT_VW_ENTRY" >/dev/null 2>&1 || { echo "LOGIN FAILED: vault entry '$DGT_VW_ENTRY' not found or ambiguous (bw get item must match exactly one item)"; return 1; }
  # the Keycloak login is the account's username (usually the email): from the vault entry, else DGT_USER (not a secret)
  local user page action final
  user=$(bw get username "$DGT_VW_ENTRY" 2>/dev/null | tr -d '\r\n') || true
  [ -n "$user" ] || user="${DGT_USER:-}"
  [ -n "$user" ] || { echo "LOGIN FAILED: vault entry '$DGT_VW_ENTRY' has no username — fill it in Vaultwarden (the DGT login, usually the email) or pass DGT_USER=<login>"; return 1; }
  bw get password "$DGT_VW_ENTRY" >/dev/null 2>&1 || { echo "LOGIN FAILED: vault entry '$DGT_VW_ENTRY' has no password"; return 1; }
  rm -f "$JAR"; ( umask 077; : > "$JAR" )
  page=$(curl -fsS -L -c "$JAR" -b "$JAR" -m 60 "$BASE/auth/login") || { echo "LOGIN FAILED: /auth/login unreachable"; return 1; }
  action=$(grep -o '<form[^>]*id="kc-form-login"[^>]*>' <<<"$page" | sed -n 's/.* action="\([^"]*\)".*/\1/p' | sed 's/&amp;/\&/g')
  [ -n "$action" ] || { echo "LOGIN FAILED: Keycloak form not found (page changed?)"; return 1; }
  final=$(curl -sS -L -c "$JAR" -b "$JAR" -m 60 -o /dev/null -w '%{url_effective}' \
    --data-urlencode username@<(printf '%s' "$user") \
    --data-urlencode password@<(bw get password "$DGT_VW_ENTRY" | tr -d '\r\n') \
    --data-urlencode "credentialId=" "$action") || { echo "LOGIN FAILED: POST to Keycloak failed"; return 1; }
  case "$final" in "$BASE"/*) ;; *) echo "LOGIN FAILED: still on the login page (wrong username/password?)"; return 1;; esac
  # no test download here: an asset link works ONCE (a probe of tile 1 made its real download answer 403, 2026-09-27);
  # a session that does not authorise downloads shows up as AUTH in get_one → rc 255 → the pass stops and logs in again
  echo "LOGIN OK $(date -u +%FT%TZ)"
}

# get_one ID URL BYTES REGION — one tile to OUT/ID.tif through a .part file; exit 255 on an expired session so
# xargs stops and the caller re-logs in. A size different from STAC is accepted only if GDAL reads every pixel.
get_one() {
  local id="$1" url="$2" bytes="$3" f="$OUT/$1.tif" t="$OUT/$1.tif.part" w magic sz
  [ -s "$f" ] && return 0
  w=$(curl -sS -L -b "$JAR" -m 300 --retry 3 --retry-delay 5 -o "$t" -w '%{http_code} %{url_effective}' "$url" 2>/dev/null) || { rm -f "$t"; echo "FAIL $id curl"; return 0; }
  case "$w" in *"/auth/"*|*"auth.cdd."*) rm -f "$t"; echo "AUTH $id — session expired"; return 255;; esac
  [ "${w%% *}" = 200 ] || { rm -f "$t"; echo "FAIL $id HTTP ${w%% *}"; return 0; }
  magic=$(head -c4 "$t" | od -An -tx1 | tr -d ' \n')
  case "$magic" in 49492a00|4d4d002a|49492b00|4d4d002b) ;; *) rm -f "$t"; echo "FAIL $id not a TIFF"; return 0;; esac
  sz=$(stat -c %s "$t")
  if [ "$sz" != "$bytes" ]; then
    gdalinfo -checksum "$t" >/dev/null 2>&1 || { rm -f "$t"; echo "FAIL $id truncated ($sz of $bytes bytes)"; return 0; }
    echo "WARN $id size $sz ≠ STAC $bytes (GDAL reads it — kept)"
  fi
  mv "$t" "$f"
}

download_all() {
  : "${DGT_VW_ENTRY:?set DGT_VW_ENTRY to the Vaultwarden entry name of the DGT data-centre account}"
  [ -s "$TILES" ] || { echo "ERROR: $TILES missing — run: bash data/etl/download_mdt.sh list"; exit 1; }
  export -f get_one; export OUT JAR
  local total have try rc   # ticker stays global: the EXIT trap must see it on any exit path
  total=$(wc -l < "$TILES"); rm -f "$OUT"/*.part
  ( while sleep 60; do echo "PROGRESS $(find "$OUT" -name 'MDT-2m-*.tif' | wc -l)/$total tiles, $(du -sh "$OUT" | cut -f1)"; done ) & ticker=$!
  trap 'kill $ticker 2>/dev/null; rm -f "$JAR"' EXIT
  for try in 1 2 3 4 5 6; do
    # the asset href changes on every search (a per-request token, lifetime unknown) → fresh list before each pass
    stac_list > "$OUT/list.log" 2>&1 || { echo "ERROR: STAC list failed — see $OUT/list.log"; exit 1; }
    login || exit 1
    rc=0; cut -f1-4 "$TILES" | xargs -P "$PAR" -L1 bash -c 'get_one "$@"' _ || rc=$?
    have=$(find "$OUT" -name 'MDT-2m-*.tif' | wc -l)
    [ "$have" -ge "$total" ] && break
    if [ "$rc" -eq 124 ]; then echo "   pass $try: session expired at $have/$total — logging in again"
    else echo "   pass $try: $have/$total (xargs rc=$rc; FAIL lines above) — retrying the missing ones"; fi
  done
  kill $ticker 2>/dev/null || true
  echo "== manifest (sha256 of every tile on disk)"
  local M="$OUT/MANIFEST.tsv"; printf 'id\turl\tfile\tretrieved_at\tbytes\tsha256\n' > "$M.tmp"
  while IFS=$'\t' read -r id _ _ _; do
    f="$OUT/$id.tif"; [ -s "$f" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$STAC_ITEMS/$id" "mdt2m/$id.tif" "$(date -u -r "$f" +%FT%TZ)" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)"
  done < "$TILES" >> "$M.tmp"; mv "$M.tmp" "$M"
  have=$(($(wc -l < "$M") - 1))
  echo "DONE $have/$total tiles, $(du -sh "$OUT" | cut -f1) — $([ "$have" -ge "$total" ] && echo complete || echo "INCOMPLETE: re-run the same command")"
}

case "$STAGE" in
  list) stac_list ;;
  get)  download_all ;;
  all)  [ -s "$TILES" ] || stac_list; download_all ;;
  *) echo "usage: $0 [list|get|all]"; exit 2 ;;
esac

#!/usr/bin/env bash
# data/etl/golden_fill.sh — print what the database says for every golden case (to validate by hand)
# What: for each case in evals/cases/golden.jsonl runs open.facts_at(lon, lat) — or open.facts_for(geometry) when
#       the case is a drawn plot (then each value carries its share of the plot) — and prints, per case,
#       the values found per dataset (concelho/freguesia, land cover, fire hazard class, flood zone,
#       census, burned areas, protected areas, PDM class (CRUS), €/m², IPMA fire-risk snapshot). Output is for
#       a human to compare with expected/notes and then set status=validated.
#       It does NOT write to the cases file (expected values are a human decision).
# Depends on: psql; env PG_DSN (+PGPASSWORD); tables loaded by data/etl/load.sh; jq.
# Used by: pre-window golden-set validation (F1/F3). Read-only.
# When changing: keep the printed keys aligned with the `expected` keys in evals/README.md
#       (concelho, freguesia, land_cover, fire_hazard, flood_zone, census, burned, protected_area, pdm_class,
#       price_eur_m2, slope). Snapshot files are named evals/cases/golden_facts_<date>.txt (stdout redirected).
#       The geometry is passed as a psql variable (:'g'), never spliced into the SQL text.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${PG_DSN:?set PG_DSN}"
CASES="${1:-$ROOT/evals/cases/golden.jsonl}"
jq -c '.' "$CASES" | while read -r c; do
  id=$(jq -r .id <<<"$c"); name=$(jq -r .name <<<"$c"); intent=$(jq -r '.intent // "-"' <<<"$c")
  if jq -e '.geometry' <<<"$c" >/dev/null; then
    g=$(jq -c .geometry <<<"$c")
    echo "── $id  $name  (plot, intent: $intent)"
    echo "SELECT dataset, attribute, coalesce(share_pct::text || ' %', '—'), value FROM open.facts_for(:'g') ORDER BY dataset, attribute, share_pct DESC NULLS LAST" \
      | psql "$PG_DSN" -At -F ' | ' -v g="$g" | sed 's/^/     /'
  else
    lon=$(jq -r .lon <<<"$c"); lat=$(jq -r .lat <<<"$c")
    echo "── $id  $name  ($lon, $lat; intent: $intent)"
    psql "$PG_DSN" -At -F ' | ' -c "
      SELECT dataset, attribute, value FROM open.facts_at($lon, $lat) ORDER BY dataset, attribute" \
      | sed 's/^/     /'
  fi
  echo "     expected: $(jq -c .expected <<<"$c")   notes: $(jq -r .notes <<<"$c")"
done

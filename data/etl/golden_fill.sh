#!/usr/bin/env bash
# data/etl/golden_fill.sh — print what the database says for every golden case (to validate by hand)
# What: for each case in evals/cases/golden.jsonl runs open.facts_at(lon, lat) and prints, per case,
#       the values found per dataset (concelho/freguesia, land cover, fire hazard class, flood zone,
#       census). Output is for a human to compare with expected/notes and then set status=validated.
#       It does NOT write to the cases file (expected values are a human decision).
# Depends on: psql; env PG_DSN (+PGPASSWORD); tables loaded by data/etl/load.sh; jq.
# Used by: pre-window golden-set validation (F1/F3). Read-only.
# When changing: keep the printed keys aligned with the `expected` keys in evals/README.md
#       (concelho, freguesia, land_cover, fire_hazard, flood_zone, census).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${PG_DSN:?set PG_DSN}"
CASES="${1:-$ROOT/evals/cases/golden.jsonl}"
jq -c '.' "$CASES" | while read -r c; do
  id=$(jq -r .id <<<"$c"); name=$(jq -r .name <<<"$c"); lon=$(jq -r .lon <<<"$c"); lat=$(jq -r .lat <<<"$c")
  echo "── $id  $name  ($lon, $lat)"
  psql "$PG_DSN" -At -F ' | ' -c "
    SELECT dataset, attribute, value FROM open.facts_at($lon, $lat) ORDER BY dataset, attribute" \
    | sed 's/^/     /'
  echo "     expected: $(jq -c .expected <<<"$c")   notes: $(jq -r .notes <<<"$c")"
done

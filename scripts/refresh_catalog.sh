#!/usr/bin/env bash
# Refresh the bundled LEGO catalog from Rebrickable's daily-updated bulk CSVs.
#
# Outputs (under assets/data/):
#   - parts.csv                 (full Rebrickable parts table)
#   - part_categories.json      (id -> name)
#   - design_to_variants.json   (LEGO design ID -> [Rebrickable part_num, ...])
#   - part_aliases.json         (part_num -> {mold:[...], alternate:[...]})
#
# Usage: bash scripts/refresh_catalog.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$REPO_ROOT/assets/data"
TMP_DIR="$(mktemp -d -t legcat.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CDN="https://cdn.rebrickable.com/media/downloads"

fetch() {
    local name="$1"
    echo "  fetching $name.csv.gz"
    curl -fsSL --max-time 60 "$CDN/$name.csv.gz" -o "$TMP_DIR/$name.csv.gz"
    gunzip -f "$TMP_DIR/$name.csv.gz"
}

echo "==> downloading Rebrickable bulk catalog"
fetch parts
fetch part_categories
fetch part_relationships
fetch elements

echo "==> installing parts.csv"
cp "$TMP_DIR/parts.csv" "$DATA_DIR/parts.csv"

echo "==> generating sidecar JSON"
python3 "$REPO_ROOT/scripts/generate_catalog_sidecars.py" \
    --parts        "$TMP_DIR/parts.csv" \
    --categories   "$TMP_DIR/part_categories.csv" \
    --relationships "$TMP_DIR/part_relationships.csv" \
    --elements     "$TMP_DIR/elements.csv" \
    --out-dir      "$DATA_DIR"

echo "==> backfilling pieces.json part_cat_id values"
python3 "$REPO_ROOT/scripts/backfill_pieces_categories.py" \
    --parts    "$DATA_DIR/parts.csv" \
    --variants "$DATA_DIR/design_to_variants.json" \
    --pieces   "$DATA_DIR/pieces.json"

echo "==> done"
ls -lh "$DATA_DIR"/parts.csv "$DATA_DIR"/part_categories.json \
       "$DATA_DIR"/design_to_variants.json "$DATA_DIR"/part_aliases.json

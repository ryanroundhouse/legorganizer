#!/usr/bin/env python3
"""Backfill empty part_cat_id values in pieces.json from parts.csv.

If a legoId exists directly in parts.csv, use that row's part_cat_id.
If not, but the design_to_variants map resolves to one or more variants that all
agree on a single part_cat_id, use that.

Leaves pieces.json untouched when neither lookup succeeds; prints a warning so
the maintainer can decide.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", type=Path, required=True)
    ap.add_argument("--variants", type=Path, required=True)
    ap.add_argument("--pieces", type=Path, required=True)
    args = ap.parse_args()

    parts: dict[str, list[str]] = {}
    with args.parts.open(newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if row and row[0] != "part_num":
                parts[row[0]] = row

    variants: dict[str, list[str]] = json.loads(args.variants.read_text("utf-8"))
    pieces: list[dict] = json.loads(args.pieces.read_text("utf-8"))

    fixed = 0
    unresolved: list[tuple[str, str]] = []
    for piece in pieces:
        if (piece.get("part_cat_id") or "").strip():
            continue
        lego_id = piece.get("legoId", "")
        if lego_id in parts:
            piece["part_cat_id"] = parts[lego_id][2]
            fixed += 1
            continue
        candidates = variants.get(lego_id, [])
        cats = sorted({parts[v][2] for v in candidates if v in parts})
        if len(cats) == 1:
            piece["part_cat_id"] = cats[0]
            fixed += 1
        else:
            unresolved.append((lego_id, piece.get("name", "")))

    if fixed:
        args.pieces.write_text(
            json.dumps(pieces, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"  backfilled {fixed} pieces.json rows")
    else:
        print("  pieces.json already complete")

    if unresolved:
        print("  WARNING: could not resolve part_cat_id for:", file=sys.stderr)
        for lid, name in unresolved:
            print(f"    {lid}\t{name}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

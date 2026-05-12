#!/usr/bin/env python3
"""Boil Rebrickable bulk CSVs down to slim JSON sidecars for the app.

Produces three files under --out-dir:
  - part_categories.json     {"id": "name", ...}
  - design_to_variants.json  {"design_id": ["part_num", ...], ...}
                             Only includes design_ids that resolve to a part_num
                             distinct from the design_id itself (i.e. the cases
                             where bare-ID lookup fails today).
  - part_aliases.json        {"part_num": {"mold": [...], "alternate": [...]}}
                             From part_relationships.csv rel_types M and A,
                             stored as an undirected sibling map.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def load_categories(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[row["id"]] = row["name"]
    return out


def load_mold_siblings(path: Path) -> dict[str, set[str]]:
    siblings: dict[str, set[str]] = defaultdict(set)
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["rel_type"] != "M":
                continue
            child = row["child_part_num"]
            parent = row["parent_part_num"]
            siblings[child].add(parent)
            siblings[parent].add(child)
    return siblings


def load_design_to_variants(
    elements_path: Path,
    parts_path: Path,
    relationships_path: Path,
) -> dict[str, list[str]]:
    valid_part_nums: set[str] = set()
    with parts_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            valid_part_nums.add(row["part_num"])

    fanout: dict[str, set[str]] = defaultdict(set)
    with elements_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            design_id = (row.get("design_id") or "").strip()
            part_num = (row.get("part_num") or "").strip()
            if not design_id or not part_num or part_num not in valid_part_nums:
                continue
            fanout[design_id].add(part_num)

    # Expand each design_id's resolution under mold-sibling closure so older
    # variants (e.g. 3040a) get picked up even when only the current SKU
    # (3040b) is referenced from elements.csv.
    mold = load_mold_siblings(relationships_path)
    for design_id in list(fanout):
        frontier = list(fanout[design_id])
        seen = set(fanout[design_id])
        while frontier:
            current = frontier.pop()
            for sib in mold.get(current, ()):
                if sib in seen or sib not in valid_part_nums:
                    continue
                seen.add(sib)
                frontier.append(sib)
        fanout[design_id] = seen

    # Also catch the reviewer's case directly: bare numeric design IDs that
    # have no row in parts.csv but do have lettered siblings (e.g. 4032 -> 4032a/b).
    by_prefix: dict[str, set[str]] = defaultdict(set)
    for part_num in valid_part_nums:
        # Trailing single-letter suffix: 3040a, 4032b, 1140M, etc.
        if len(part_num) >= 2 and part_num[-1].isalpha() and part_num[:-1].isdigit():
            by_prefix[part_num[:-1]].add(part_num)
    for base, sibs in by_prefix.items():
        if base in valid_part_nums:
            continue  # base exists on its own; no fallback needed
        fanout[base].update(sibs)

    out: dict[str, list[str]] = {}
    for design_id, variants in fanout.items():
        useful = {v for v in variants if v != design_id}
        if not useful:
            continue
        out[design_id] = sorted(useful)
    return dict(sorted(out.items()))


def load_aliases(path: Path) -> dict[str, dict[str, list[str]]]:
    mold: dict[str, set[str]] = defaultdict(set)
    alt: dict[str, set[str]] = defaultdict(set)
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rel = row["rel_type"]
            child = row["child_part_num"]
            parent = row["parent_part_num"]
            if rel == "M":
                mold[child].add(parent)
                mold[parent].add(child)
            elif rel == "A":
                alt[child].add(parent)
                alt[parent].add(child)

    keys = set(mold) | set(alt)
    out: dict[str, dict[str, list[str]]] = {}
    for key in sorted(keys):
        entry: dict[str, list[str]] = {}
        if key in mold:
            entry["mold"] = sorted(mold[key])
        if key in alt:
            entry["alternate"] = sorted(alt[key])
        out[key] = entry
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", type=Path, required=True)
    ap.add_argument("--categories", type=Path, required=True)
    ap.add_argument("--relationships", type=Path, required=True)
    ap.add_argument("--elements", type=Path, required=True)
    ap.add_argument("--out-dir", type=Path, required=True)
    args = ap.parse_args()

    cats = load_categories(args.categories)
    variants = load_design_to_variants(args.elements, args.parts, args.relationships)
    aliases = load_aliases(args.relationships)

    (args.out_dir / "part_categories.json").write_text(
        json.dumps(cats, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (args.out_dir / "design_to_variants.json").write_text(
        json.dumps(variants, separators=(",", ":"), ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (args.out_dir / "part_aliases.json").write_text(
        json.dumps(aliases, separators=(",", ":"), ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"  categories: {len(cats)}")
    print(f"  design_to_variants: {len(variants)} design IDs")
    print(f"  part_aliases: {len(aliases)} parts with mold/alternate siblings")


if __name__ == "__main__":
    main()

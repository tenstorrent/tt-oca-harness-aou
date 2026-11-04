#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
"""The verification plan's feature areas (docs/plan_areas.yaml).

  areas()            the areas in reading order: [{key, title, sections, items}]
  assign(items)      {item id: area key} for the plan items; raises PlanAreaError
                     when an item lands in no area or an area names an unknown item

Run as a script, it checks docs/plan_areas.yaml against docs/test_plan_items.yaml
and prints the item count of each area.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import listyaml  # noqa: E402

UVM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AREAS = os.path.join(UVM_ROOT, "docs", "plan_areas.yaml")
PLAN_ITEMS = os.path.join(UVM_ROOT, "docs", "test_plan_items.yaml")


class PlanAreaError(Exception):
    pass


def areas(path=AREAS):
    out = []
    for a in listyaml.load(path):
        out.append({"key": a["key"], "title": a["title"],
                    "sections": [str(s) for s in a.get("sections", [])],
                    "items": [str(i) for i in a.get("items", [])]})
    return out


def assign(items, area_list=None):
    """{item id: area key}: an area's `items` first, then its `sections`."""
    area_list = area_list if area_list is not None else areas()
    ids = {i["id"] for i in items}
    by_item, by_sec, errors = {}, {}, []
    for a in area_list:
        for iid in a["items"]:
            if iid not in ids:
                errors.append(f"area {a['key']}: no plan item {iid}")
            elif iid in by_item:
                errors.append(f"item {iid} in areas {by_item[iid]} and {a['key']}")
            by_item[iid] = a["key"]
        for sec in a["sections"]:
            if sec in by_sec:
                errors.append(f"section {sec} in areas {by_sec[sec]} and {a['key']}")
            by_sec[sec] = a["key"]
    out = {}
    for it in items:
        key = by_item.get(it["id"]) or by_sec.get(it["id"].split(".")[0])
        if key is None:
            errors.append(f"item {it['id']} is in no area")
        out[it["id"]] = key
    if errors:
        raise PlanAreaError("; ".join(errors))
    return out


def main():
    items = listyaml.load(PLAN_ITEMS)
    try:
        where = assign(items)
    except PlanAreaError as e:
        sys.exit(f"plan_areas: {e}")
    for a in areas():
        print(f"{a['key']:<12} {sum(1 for k in where.values() if k == a['key']):>4}  {a['title']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Writes the ZedComm crafting recipes from the one table below.

Outputs, all rewritten in place:
  - the craftRecipe blocks at the end of media/scripts/ZedComm_Items.txt
  - media/lua/shared/Translate/EN/Recipes.json
  - docs/recipes.md, the readable table published with the mod

Change a recipe here, run this script, and commit the three files together.
`--check` writes nothing and exits 1 if any of them is out of date.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "workshop/ZedComm/Contents/mods/ZedComm/42/media"
ITEMS = MEDIA / "scripts/ZedComm_Items.txt"
NAMES = MEDIA / "lua/shared/Translate/EN/ItemName.json"
RECIPE_NAMES = MEDIA / "lua/shared/Translate/EN/Recipes.json"
TABLE = ROOT / "docs/recipes.md"

SCRAP, WIRE, SHEET = "Base.ElectronicsScrap", "Base.ElectricWire", "Base.SheetMetal"
BASIC, ADVANCED = "ZedComm.BasicAdapter", "ZedComm.AdvancedAdapter"
BASE_NAMES = {SCRAP: "Electronics Scrap", WIRE: "Electric Wire", SHEET: "Sheet Metal"}

# (section, item, Electrical level or None, time, ingredients, amount made, tool kept)
RECIPES = [
    ("Adapters", "BasicAdapter", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Adapters", "AdvancedAdapter", 3, 100, {SCRAP: 3, WIRE: 2}, 1, True),

    ("Wire and devices", "SignalWire", None, 30, {WIRE: 1}, 5, False),
    ("Wire and devices", "NetworkSwitch", None, 60, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Wire and devices", "PressurePlate", 1, 80, {SHEET: 1, BASIC: 1}, 1, True),
    ("Wire and devices", "OccupancyPlate", 2, 80, {SHEET: 1, SCRAP: 1, BASIC: 1}, 1, True),
    ("Wire and devices", "WeightPlate", 2, 100, {SHEET: 1, SCRAP: 2, BASIC: 1}, 1, True),
    ("Wire and devices", "NumericDisplay", 2, 80, {SCRAP: 2, BASIC: 1}, 1, True),
    ("Wire and devices", "AdvancedDisplay", 3, 100, {SCRAP: 3, ADVANCED: 1}, 1, True),

    ("Cabinets", "SmallCabinet", 1, 80, {SHEET: 1, BASIC: 1}, 1, True),
    ("Cabinets", "AdvancedSmallCabinet", 3, 80, {SHEET: 1, ADVANCED: 1}, 1, True),

    ("Connection modules", "InputExtension", 1, 40, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Connection modules", "OutputExtension", 1, 40, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Connection modules", "SplitterModule", 1, 50, {SCRAP: 1, WIRE: 2}, 1, True),

    ("Logic modules", "ThresholdModule", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Logic modules", "NotModule", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Logic modules", "AndModule", 2, 50, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Logic modules", "OrModule", 2, 50, {SCRAP: 1, WIRE: 1}, 1, True),
    ("Logic modules", "XorModule", 2, 50, {SCRAP: 1, WIRE: 1}, 1, True),

    ("Arithmetic modules", "AdderModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True),
    ("Arithmetic modules", "SubtractorModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True),
    ("Arithmetic modules", "MultiplierModule", 3, 60, {SCRAP: 3, WIRE: 1}, 1, True),

    ("Memory and timing modules", "CacheModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True),
    ("Memory and timing modules", "TimerModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True),
    ("Memory and timing modules", "WaitModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True),

    ("Source modules", "MainsSourceModule", 2, 60, {SCRAP: 1, WIRE: 2}, 1, True),
    ("Source modules", "BatterySourceModule", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True),
]

# The Basic cabinet item is SmallCabinet; its recipe keeps the clearer name.
RECIPE_IDS = {"SmallCabinet": "ZedCommMakeBasicSmallCabinet"}


def recipe_id(item):
    return RECIPE_IDS.get(item, "ZedCommMake" + item)


def display_name(names, full_type):
    return BASE_NAMES.get(full_type) or names[full_type].replace("ZedComm ", "", 1)


def script_block(item, level, time, inputs, made, tool):
    lines = [f"    craftRecipe {recipe_id(item)}", "    {",
             "        timedAction = MakingElectrical,", f"        time = {time},"]
    if level:
        lines.append(f"        SkillRequired = Electricity:{level},")
    lines += ["        Tags = InHandCraft;Electrical,", "        category = Electrical,",
              "        inputs", "        {"]
    if tool:
        lines.append("            item 1 tags[base:screwdriver] mode:keep flags[NoBrokenItems],")
    lines += [f"            item {count} [{full_type}]," for full_type, count in inputs.items()]
    lines += ["        }", "        outputs", "        {",
              f"            item {made} ZedComm.{item},", "        }", "    }"]
    return "\n".join(lines)


def build(names):
    items = ITEMS.read_text()
    head = items[:items.index("    craftRecipe ")]
    blocks = [script_block(*recipe[1:]) for recipe in RECIPES]
    script = head + "\n\n".join(blocks) + "\n}\n"

    recipe_names = {recipe_id(r[1]): "Make " + names["ZedComm." + r[1]] for r in RECIPES}
    translations = json.dumps(recipe_names, indent=4) + "\n"

    table = ["# ZedComm crafting recipes", "",
             "Every recipe is in the crafting menu under Electrical. Recipes marked with a screwdriver "
             "need one in the inventory and do not use it up. Electrical is the skill level required; "
             "a dash means none.", "",
             "This file is written by `tools/make-recipes.py`. Change recipes there, not here.", ""]
    section = None
    for group, item, level, _time, inputs, made, tool in RECIPES:
        if group != section:
            section = group
            table += [f"## {group}", "", "| Makes | Electrical | Ingredients | Screwdriver |",
                      "| --- | --- | --- | --- |"]
        name = display_name(names, "ZedComm." + item)
        makes = f"{made} × {name}" if made > 1 else name
        parts = ", ".join(f"{count} {display_name(names, full_type)}" for full_type, count in inputs.items())
        table.append(f"| {makes} | {level or '-'} | {parts} | {'Yes' if tool else 'No'} |")
        following = RECIPES[RECIPES.index((group, item, level, _time, inputs, made, tool)) + 1:]
        if not following or following[0][0] != group:
            table.append("")
    return {ITEMS: script, RECIPE_NAMES: translations, TABLE: "\n".join(table)}


def main():
    names = json.loads(NAMES.read_text())
    outputs = build(names)
    if "--check" in sys.argv[1:]:
        stale = [str(path.relative_to(ROOT)) for path, text in outputs.items()
                 if not path.exists() or path.read_text() != text]
        if stale:
            sys.exit("out of date, run tools/make-recipes.py: " + ", ".join(stale))
        return
    for path, text in outputs.items():
        path.write_text(text)
    print(f"wrote {len(RECIPES)} recipes")


if __name__ == "__main__":
    main()

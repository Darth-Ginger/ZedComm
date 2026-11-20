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
# A roll of Base.Wire holds 10 units, and a recipe input counts units.
ROLL, ROLL_UNITS = "Base.Wire", 10
BASIC, ADVANCED = "ZedComm.BasicAdapter", "ZedComm.AdvancedAdapter"
BASE_NAMES = {SCRAP: "Electronics Scrap", WIRE: "Electric Wire", SHEET: "Sheet Metal", ROLL: "Wire"}
# One unit of roll wire stands in for one Electric Wire in every recipe.
SCRIPT_TYPES = {WIRE: f"{WIRE};{ROLL}"}
TABLE_NAMES = {WIRE: "Electric Wire or Wire"}

# (section, item, Electrical level or None, time, ingredients, amount made, tool kept, Electrical XP)
RECIPES = [
    ("Adapters", "BasicAdapter", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True, 4),
    ("Adapters", "AdvancedAdapter", 3, 100, {SCRAP: 3, WIRE: 2}, 1, True, 8),

    ("Wire and devices", "DoorContact", 1, 50, {BASIC: 1, SCRAP: 1, WIRE: 1}, 1, True, 4),
    ("Wire and devices", "WindowContact", 1, 50, {BASIC: 1, SCRAP: 1, WIRE: 1}, 1, True, 4),
    ("Wire and devices", "SignalWire", None, 30, {WIRE: 1}, 5, False, 1),
    ("Wire and devices", "NetworkSwitch", None, 60, {SCRAP: 1, WIRE: 1}, 1, True, 2),
    ("Wire and devices", "PressurePlate", 1, 80, {SHEET: 1, BASIC: 1}, 1, True, 4),
    ("Wire and devices", "OccupancyPlate", 2, 80, {SHEET: 1, SCRAP: 1, BASIC: 1}, 1, True, 5),
    ("Wire and devices", "WeightPlate", 2, 100, {SHEET: 1, SCRAP: 2, BASIC: 1}, 1, True, 6),
    ("Wire and devices", "NumericDisplay", 2, 80, {SCRAP: 2, BASIC: 1}, 1, True, 5),
    ("Wire and devices", "AdvancedDisplay", 3, 100, {SCRAP: 3, ADVANCED: 1}, 1, True, 8),

    ("Cabinets", "SmallCabinet", 1, 80, {SHEET: 1, BASIC: 1}, 1, True, 3),
    ("Cabinets", "AdvancedSmallCabinet", 3, 80, {SHEET: 1, ADVANCED: 1}, 1, True, 4),

    ("Cabinets", "LargeCabinet", 2, 110, {SHEET: 2, SCRAP: 1, BASIC: 1}, 1, True, 4),
    ("Cabinets", "AdvancedLargeCabinet", 4, 110, {SHEET: 2, SCRAP: 1, ADVANCED: 1}, 1, True, 6),
    ("Cabinets", "XLCabinet", 3, 145, {SHEET: 4, SCRAP: 2, BASIC: 1}, 1, True, 6),
    ("Cabinets", "AdvancedXLCabinet", 5, 145, {SHEET: 4, SCRAP: 2, ADVANCED: 1}, 1, True, 8),
    ("Cabinets", "TabletopCabinet", 1, 80, {SHEET: 1, BASIC: 1}, 1, True, 3),
    ("Cabinets", "AdvancedTabletopCabinet", 3, 80, {SHEET: 1, ADVANCED: 1}, 1, True, 4),
    ("Cabinets", "WallCabinet", 2, 110, {SHEET: 2, SCRAP: 1, BASIC: 1}, 1, True, 4),
    ("Cabinets", "AdvancedWallCabinet", 4, 110, {SHEET: 2, SCRAP: 1, ADVANCED: 1}, 1, True, 6),

    ("Connection modules", "InputExtension", 1, 40, {SCRAP: 1, WIRE: 1}, 1, True, 2),
    ("Connection modules", "OutputExtension", 1, 40, {SCRAP: 1, WIRE: 1}, 1, True, 2),
    ("Connection modules", "SplitterModule", 1, 50, {SCRAP: 1, WIRE: 2}, 1, True, 3),

    ("Logic modules", "ThresholdModule", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True, 4),
    ("Logic modules", "NotModule", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True, 4),
    ("Logic modules", "AndModule", 2, 50, {SCRAP: 1, WIRE: 1}, 1, True, 4),
    ("Logic modules", "OrModule", 2, 50, {SCRAP: 1, WIRE: 1}, 1, True, 4),
    ("Logic modules", "XorModule", 2, 50, {SCRAP: 1, WIRE: 1}, 1, True, 4),

    ("Arithmetic modules", "AdderModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True, 5),
    ("Arithmetic modules", "SubtractorModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True, 5),
    ("Arithmetic modules", "MultiplierModule", 3, 60, {SCRAP: 3, WIRE: 1}, 1, True, 6),

    ("Memory and timing modules", "CacheModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True, 5),
    ("Memory and timing modules", "TimerModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True, 4),
    ("Memory and timing modules", "WaitModule", 2, 60, {SCRAP: 2, WIRE: 1}, 1, True, 4),

    ("Source modules", "MainsSourceModule", 2, 60, {SCRAP: 1, WIRE: 2}, 1, True, 4),
    ("Source modules", "BatterySourceModule", 1, 50, {SCRAP: 1, WIRE: 1}, 1, True, 4),
]

# The Basic cabinet item is SmallCabinet; its recipe keeps the clearer name.
RECIPE_IDS = {"SmallCabinet": "ZedCommMakeBasicSmallCabinet"}


def recipe_id(item):
    return RECIPE_IDS.get(item, "ZedCommMake" + item)


def all_recipes():
    """Each table row as (id, label suffix, row), plus the whole-roll Signal Wire recipe."""
    out = []
    for row in RECIPES:
        item = row[1]
        out.append((recipe_id(item), "", row))
        if item == "SignalWire":
            # Cutting a whole roll takes longer, but less than ten single cuts.
            roll = row[:3] + (row[3] * 5, {ROLL: ROLL_UNITS}, row[5] * ROLL_UNITS) + row[6:]
            out.append((recipe_id(item) + "FromWireRoll", " (whole Wire roll)", roll))
    return out


def display_name(names, full_type):
    return BASE_NAMES.get(full_type) or names[full_type].replace("ZedComm ", "", 1)


def script_block(identifier, item, level, time, inputs, made, tool, xp):
    lines = [f"    craftRecipe {identifier}", "    {",
             "        timedAction = MakingElectrical,", f"        time = {time},"]
    if level:
        lines.append(f"        SkillRequired = Electricity:{level},")
    if xp:
        lines.append(f"        xpAward = Electricity:{xp},")
    lines += ["        Tags = InHandCraft;Electrical,", "        category = ZedComm,",
              "        inputs", "        {"]
    if tool:
        lines.append("            item 1 tags[base:screwdriver] mode:keep flags[NoBrokenItems],")
    lines += [f"            item {count} [{SCRIPT_TYPES.get(full_type, full_type)}],"
              for full_type, count in inputs.items()]
    lines += ["        }", "        outputs", "        {",
              f"            item {made} ZedComm.{item},", "        }", "    }"]
    return "\n".join(lines)


def build(names):
    items = ITEMS.read_text(encoding="utf-8")
    head = items[:items.index("    craftRecipe ")]
    recipes = all_recipes()
    blocks = [script_block(identifier, *row[1:]) for identifier, _suffix, row in recipes]
    script = head + "\n\n".join(blocks) + "\n}\n"

    recipe_names = {identifier: "Make " + names["ZedComm." + row[1]] + suffix
                    for identifier, suffix, row in recipes}
    translations = json.dumps(recipe_names, indent=4) + "\n"

    def listed(inputs):
        return ", ".join(f"{count} {TABLE_NAMES.get(full_type) or display_name(names, full_type)}"
                         for full_type, count in inputs.items())

    table = ["# ZedComm crafting recipes", "",
             "Every recipe is in the crafting menu under ZedComm. Recipes marked with a screwdriver "
             "need one in the inventory and do not use it up. Electrical is the skill level required; "
             "a dash means none. XP is the base Electrical award per craft.", "",
             f"Wire means the roll of wire, which holds {ROLL_UNITS} units; amounts of it are in units. "
             "One unit can be used wherever a recipe asks for one Electric Wire.", "",
             "This file is written by `tools/make-recipes.py`. Change recipes there, not here.", ""]
    section = None
    for _identifier, _suffix, (group, item, level, _time, inputs, made, tool, xp) in recipes:
        if group != section:
            section = group
            table += [f"## {group}", "", "| Makes | Electrical | XP | Ingredients | Screwdriver |",
                      "| --- | --- | ---: | --- | --- |"]
        name = display_name(names, "ZedComm." + item)
        makes = f"{made} × {name}" if made > 1 else name
        table.append(f"| {makes} | {level or '-'} | {xp} | {listed(inputs)} | {'Yes' if tool else 'No'} |")
    text = "\n".join(table)
    for heading in sorted({row[0] for _i, _s, row in recipes}):
        text = text.replace(f"|\n## {heading}", f"|\n\n## {heading}")
    return {ITEMS: script, RECIPE_NAMES: translations, TABLE: text + "\n"}


def main():
    names = json.loads(NAMES.read_text(encoding="utf-8"))
    outputs = build(names)
    if "--check" in sys.argv[1:]:
        stale = [str(path.relative_to(ROOT)) for path, text in outputs.items()
                 if not path.exists() or path.read_text(encoding="utf-8") != text]
        if stale:
            sys.exit("out of date, run tools/make-recipes.py: " + ", ".join(stale))
        return
    for path, text in outputs.items():
        path.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {len(all_recipes())} recipes")


if __name__ == "__main__":
    main()

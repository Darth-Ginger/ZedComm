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
# Roll wire stands in for Electric Wire at this many units each, for the extra work.
ROLL_PER_ELECTRIC = 2
SIGNAL_WIRE_PER_UNIT = 5

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


def with_roll_wire(inputs):
    """The same ingredients with Electric Wire swapped for units of roll wire."""
    return {(ROLL if full_type == WIRE else full_type): (count * ROLL_PER_ELECTRIC if full_type == WIRE else count)
            for full_type, count in inputs.items()}


def all_recipes():
    """Each table row, followed by its roll-wire variants: (id, label suffix, row, variant inputs or None)."""
    out = []
    for row in RECIPES:
        _group, item, _level, _time, inputs, made, _tool = row
        out.append((recipe_id(item), "", row, None))
        if item == "SignalWire":
            unit = row[:4] + ({ROLL: 1}, SIGNAL_WIRE_PER_UNIT, row[6])
            # Cutting a whole roll takes longer, but less than ten single cuts.
            roll = row[:3] + (row[3] * 5, {ROLL: ROLL_UNITS}, SIGNAL_WIRE_PER_UNIT * ROLL_UNITS, row[6])
            out.append((recipe_id(item) + "FromWire", " (from Wire)", unit, None))
            out.append((recipe_id(item) + "FromWireRoll", " (from a Wire roll)", roll, None))
        elif WIRE in inputs:
            variant = row[:4] + (with_roll_wire(inputs),) + row[5:]
            out.append((recipe_id(item) + "FromWire", " (from Wire)", variant, inputs))
    return out


def display_name(names, full_type):
    return BASE_NAMES.get(full_type) or names[full_type].replace("ZedComm ", "", 1)


def script_block(identifier, item, level, time, inputs, made, tool):
    lines = [f"    craftRecipe {identifier}", "    {",
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
    recipes = all_recipes()
    blocks = [script_block(identifier, *row[1:]) for identifier, _suffix, row, _base in recipes]
    script = head + "\n\n".join(blocks) + "\n}\n"

    recipe_names = {identifier: "Make " + names["ZedComm." + row[1]] + suffix
                    for identifier, suffix, row, _base in recipes}
    translations = json.dumps(recipe_names, indent=4) + "\n"

    def listed(inputs):
        return ", ".join(f"{count} {display_name(names, full_type)}" for full_type, count in inputs.items())

    table = ["# ZedComm crafting recipes", "",
             "Every recipe is in the crafting menu under Electrical. Recipes marked with a screwdriver "
             "need one in the inventory and do not use it up. Electrical is the skill level required; "
             "a dash means none.", "",
             f"Wire means the roll of wire, which holds {ROLL_UNITS} units; amounts of it are in units. "
             f"It can replace Electric Wire in any recipe at {ROLL_PER_ELECTRIC} units for each Electric Wire.", "",
             "This file is written by `tools/make-recipes.py`. Change recipes there, not here.", ""]
    section = None
    for identifier, _suffix, (group, item, level, _time, inputs, made, tool), base in recipes:
        if base is not None:
            continue  # shown in its base recipe's row
        if group != section:
            section = group
            table += ["" if len(table) and table[-1] else None, f"## {group}", "",
                      "| Makes | Electrical | Ingredients | Or, with Wire | Screwdriver |",
                      "| --- | --- | --- | --- | --- |"]
        name = display_name(names, "ZedComm." + item)
        makes = f"{made} × {name}" if made > 1 else name
        swap = listed(with_roll_wire(inputs)) if WIRE in inputs and item != "SignalWire" else "-"
        table.append(f"| {makes} | {level or '-'} | {listed(inputs)} | {swap} | {'Yes' if tool else 'No'} |")
    table = [line for line in table if line is not None] + [""]
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
    print(f"wrote {len(all_recipes())} recipes")


if __name__ == "__main__":
    main()

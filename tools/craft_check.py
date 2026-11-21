#!/usr/bin/env python3
"""Craft the Roots Classic slice-1 recipes in a real crafting table.

Called by tools/e2e.sh with the open game's control socket. The harness's
crafting grid is slots 100-108 row-major, result 200 (`ctl screen`). Cases:

  1. shaped `pestle`: five diorite in the jar's `X  / XX / XX` variant ->
     `rootsclassic:pestle` x1, and the stack reaches the inventory;
  2. its control: one diorite -> empty result;
  3. shapeless `rooty_stew`: wheat + bowl + old root -> `rooty_stew` x1;
  4. its control: wheat + bowl + stick -> empty;
  5. shapeless `fruit_salad`: 3 melon + apple + bowl + the four berries -> x1;
  6. its control: a stick instead of the elderberry -> empty;
  7. shapeless `healing_poultice`: redcurrant + paper + pestle + verdant sprig
     -> 2 poultices;
  8. its control: a stick instead of the redcurrant -> empty.
  9. shapeless `growth_powder`: wheat seeds + short grass + redstone + pestle
     -> 4 growth powders;
 10. its control: a stick instead of the seeds -> empty;
 11. shapeless `mutating_powder`: 4 growth powder + nether star + nether wart
     + pestle -> 1 mutating powder;
 12. its control: 3 growth powder instead of 4 -> empty.

Exits 1 on the first mismatch.
"""
import json
import subprocess
import sys


def main():
    sock, ctl, x, y, z = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

    def run(*args):
        out = subprocess.run([ctl, "--socket", sock, *args], text=True,
                             capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(args)}: {out.stdout}{out.stderr}")

    def wait(ticks=4):
        run("wait", str(ticks))

    def slots():
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"no menu is open: {screen}")
        return screen["slots"]

    def find(item):
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"missing ingredient {item} in the inventory")

    def setup(items):
        try:
            run("close")
        except SystemExit:
            pass
        wait(5)
        # A death earlier in the scenario leaves the dead screen open, which
        # refuses every click: respawn before the first case and carry on.
        if run("screen").get("screen") == "dead":
            run("respawn")
            wait(20)
            run("command", "gamemode survival @s")
            wait(5)
        run("setblock", x, y, z, "minecraft:air")
        run("setblock", x, y, z, "minecraft:crafting_table")
        wait(2)
        run("command", f"tp @s {float(x) - 0.5} {y} {float(z) + 0.5}")
        wait(3)
        run("command", "clear @s")
        for item, count in items:
            run("give", item, str(count))
        wait(3)
        reply = run("interact", x, y, z)
        wait(5)
        screen = run("screen")
        print(f"  [open] title={screen.get('title')!r} slots={len(screen.get('slots') or [])} "
              f"craft_size={screen.get('craft_size')} station={screen.get('station')} "
              f"container={screen.get('container')} reply={json.dumps(reply)[:160]}")
        # A crafting table menu is 36 inventory + 9 grid (100-108) + result
        # (200): 46 entries, with craft_size 3.
        if screen.get("craft_size") != 3 or len(screen.get("slots") or []) < 46:
            raise SystemExit(f"the crafting table did not open: {json.dumps(screen)[:300]}")

    def result():
        stack = [s for s in slots() if s["slot"] == 200]
        if not stack or not stack[0].get("item"):
            return None
        return stack[0]

    def place(item, targets):
        slot = find(item)
        run("click-slot", str(slot))
        wait(1)
        for target in targets:
            reply = run("click-slot", str(target), "right")
            if reply.get("error"):
                print(f"  [place] slot {target}: {json.dumps(reply)[:160]}")
            wait(1)
        run("click-slot", str(slot))
        wait(2)

    failures = []

    def dump(tag):
        rows = []
        for slot in slots():
            if slot.get("item") and (slot["slot"] >= 100 or slot["slot"] < 36):
                rows.append(f'{slot["slot"]}:{slot["item"]}x{slot.get("count")}')
        print(f"  [{tag}] slots={len(slots())} {' '.join(rows[:24])}")

    def check(label, items, placements, want_item, want_count, take=False):
        setup(items)
        dump("after setup")
        for item, targets in placements:
            place(item, targets)
        dump("after placing")
        got = result()
        print(f"{label} ->", json.dumps(got))
        if not got or got.get("item") != want_item or got.get("count") != want_count:
            failures.append(f"{label}: expected {want_count} {want_item}, got {got}")
            return
        if take:
            run("click-slot", "200")
            wait(5)
            run("click-slot", "9")
            wait(3)
            made = run("inventory")["counts"].get(want_item, 0)
            if made < want_count:
                failures.append(
                    f"{label}: the crafted stack reached the inventory as {made}")

    def empty_control(label, items, placements):
        setup(items)
        for item, targets in placements:
            place(item, targets)
        got = result()
        print(f"{label} ->", json.dumps(got))
        if got is not None:
            failures.append(f"{label}: control crafted {got['item']}")

    mod = "rootsclassic"
    check(
        "5 diorite (X  / XX / XX) -> pestle",
        [("minecraft:diorite", 5)],
        [("minecraft:diorite", ["100", "104", "105", "107", "108"])],
        f"{mod}:pestle",
        1,
        take=True,
    )
    empty_control(
        "1 diorite -> nothing",
        [("minecraft:diorite", 1)],
        [("minecraft:diorite", ["100"])],
    )
    check(
        "wheat + bowl + old root -> rooty_stew",
        [("minecraft:wheat", 1), ("minecraft:bowl", 1), (f"{mod}:old_root", 1)],
        [
            ("minecraft:wheat", ["100"]),
            ("minecraft:bowl", ["101"]),
            (f"{mod}:old_root", ["102"]),
        ],
        f"{mod}:rooty_stew",
        1,
        take=True,
    )
    empty_control(
        "wheat + bowl + stick -> nothing",
        [("minecraft:wheat", 1), ("minecraft:bowl", 1), ("minecraft:stick", 1)],
        [
            ("minecraft:wheat", ["100"]),
            ("minecraft:bowl", ["101"]),
            ("minecraft:stick", ["102"]),
        ],
    )
    check(
        "3 melon + apple + bowl + 4 berries -> fruit_salad",
        [
            ("minecraft:melon", 3),
            ("minecraft:apple", 1),
            ("minecraft:bowl", 1),
            (f"{mod}:elderberry", 1),
            (f"{mod}:whitecurrant", 1),
            (f"{mod}:blackcurrant", 1),
            (f"{mod}:redcurrant", 1),
        ],
        [
            ("minecraft:melon", ["100", "101", "102"]),
            ("minecraft:apple", ["103"]),
            ("minecraft:bowl", ["104"]),
            (f"{mod}:elderberry", ["105"]),
            (f"{mod}:whitecurrant", ["106"]),
            (f"{mod}:blackcurrant", ["107"]),
            (f"{mod}:redcurrant", ["108"]),
        ],
        f"{mod}:fruit_salad",
        1,
        take=True,
    )
    empty_control(
        "3 melon + apple + bowl + 3 berries + stick -> nothing",
        [
            ("minecraft:melon", 3),
            ("minecraft:apple", 1),
            ("minecraft:bowl", 1),
            (f"{mod}:elderberry", 1),
            (f"{mod}:whitecurrant", 1),
            (f"{mod}:blackcurrant", 1),
            ("minecraft:stick", 1),
        ],
        [
            ("minecraft:melon", ["100", "101", "102"]),
            ("minecraft:apple", ["103"]),
            ("minecraft:bowl", ["104"]),
            (f"{mod}:elderberry", ["105"]),
            (f"{mod}:whitecurrant", ["106"]),
            (f"{mod}:blackcurrant", ["107"]),
            ("minecraft:stick", ["108"]),
        ],
    )
    check(
        "redcurrant + paper + pestle + verdant sprig -> 2 poultices",
        [
            (f"{mod}:redcurrant", 1),
            ("minecraft:paper", 1),
            (f"{mod}:pestle", 1),
            (f"{mod}:verdant_sprig", 1),
        ],
        [
            (f"{mod}:redcurrant", ["100"]),
            ("minecraft:paper", ["101"]),
            (f"{mod}:pestle", ["102"]),
            (f"{mod}:verdant_sprig", ["103"]),
        ],
        f"{mod}:healing_poultice",
        2,
        take=True,
    )
    empty_control(
        "paper + pestle + verdant sprig + stick -> nothing",
        [
            ("minecraft:paper", 1),
            (f"{mod}:pestle", 1),
            (f"{mod}:verdant_sprig", 1),
            ("minecraft:stick", 1),
        ],
        [
            ("minecraft:paper", ["100"]),
            (f"{mod}:pestle", ["101"]),
            (f"{mod}:verdant_sprig", ["102"]),
            ("minecraft:stick", ["103"]),
        ],
    )
    # Slice 2: the powder chain. Both are shapeless, so the grid order only has
    # to hold the right multiset.
    check(
        "wheat seeds + short grass + redstone + pestle -> 4 growth powder",
        [
            ("minecraft:wheat_seeds", 1),
            ("minecraft:short_grass", 1),
            ("minecraft:redstone", 1),
            (f"{mod}:pestle", 1),
        ],
        [
            ("minecraft:wheat_seeds", ["100"]),
            ("minecraft:short_grass", ["101"]),
            ("minecraft:redstone", ["102"]),
            (f"{mod}:pestle", ["103"]),
        ],
        f"{mod}:growth_powder",
        4,
        take=True,
    )
    empty_control(
        "short grass + redstone + pestle + stick -> nothing",
        [
            ("minecraft:short_grass", 1),
            ("minecraft:redstone", 1),
            (f"{mod}:pestle", 1),
            ("minecraft:stick", 1),
        ],
        [
            ("minecraft:short_grass", ["100"]),
            ("minecraft:redstone", ["101"]),
            (f"{mod}:pestle", ["102"]),
            ("minecraft:stick", ["103"]),
        ],
    )
    check(
        "4 growth powder + nether star + nether wart + pestle -> mutating powder",
        [
            (f"{mod}:growth_powder", 4),
            ("minecraft:nether_star", 1),
            ("minecraft:nether_wart", 1),
            (f"{mod}:pestle", 1),
        ],
        [
            (f"{mod}:growth_powder", ["100", "101", "102", "103"]),
            ("minecraft:nether_star", ["104"]),
            ("minecraft:nether_wart", ["105"]),
            (f"{mod}:pestle", ["106"]),
        ],
        f"{mod}:mutating_powder",
        1,
        take=True,
    )
    empty_control(
        "3 growth powder + nether star + nether wart + pestle -> nothing",
        [
            (f"{mod}:growth_powder", 3),
            ("minecraft:nether_star", 1),
            ("minecraft:nether_wart", 1),
            (f"{mod}:pestle", 1),
        ],
        [
            (f"{mod}:growth_powder", ["100", "101", "102"]),
            ("minecraft:nether_star", ["103"]),
            ("minecraft:nether_wart", ["104"]),
            (f"{mod}:pestle", ["105"]),
        ],
    )

    run("close")
    wait(3)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        raise SystemExit(1)
    print("recipe PASS: pestle (shaped), rooty_stew and healing_poultice "
          "(shapeless), fruit_salad and the two powders craft; every "
          "wrong-ingredient control stays empty")


if __name__ == "__main__":
    main()

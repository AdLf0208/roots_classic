#!/usr/bin/env bash
# In-game check for Roots Classic slice 1: the three herbs, the forage table and
# the herbs' first uses, Minecraft 26.3 (26.3 prepared resources).
#
# STATUS (2026-11-18, SDK format): the port is one flat `.hmod` now — there is no
# `.hnmod` and no embedded content — so this scenario needs a game the launcher
# built with the package in it:
#
#     horizon-launcher native-build ports/rootsclassic --instance <i> --trust-native-code
#     GAME=<that horizon-client> tools/e2e.sh
#
# `--dev-mod` is still not used: the content half (`assets/`, `data/`) ships
# inside the same `.hmod` as the code, and the game installs both.
#
# The retired bundle's legs are gated behind `EMBEDDED=1` (default 0) and cannot
# run against the flat package: they needed the AE2 embedding — an `.hnmod` that
# wrote `mixins/<id>/data/<id>-content.hmod` into `.horizon-cache/` at start —
# and they assert that file byte for byte. With `EMBEDDED=0` the scenario is:
# Launch 1 (offscreen renderer, The End, the launcher-built game, and a config
# that makes every forage roll certain):
#   1. the content half loads and the three herbs bind, place on dirt and drop
#      themselves when broken, and a herb refuses stone as its ground;
#   2. the forage table: short grass -> old root, wheat age 7 -> verdant sprig,
#      nether wart age 3 -> infernal bulb, a chorus flower -> dragon's eye,
#      oak leaves -> one of the five berries;
#   3. controls: a young wheat age 0, a young nether wart age 0, stone, and
#      leaves broken with shears (they drop themselves) forage nothing;
#   4. the herbs' eaten effects: redcurrant heals 2, healing poultice heals 5,
#      elderberry clears effects, nightshade poisons, the dragon's eye
#      teleports, and old root (no effect) changes no health;
#   5. the jar's recipes craft in a real table, with wrong-ingredient controls
#      staying empty.
# Launch 2 (the same world settings, chances set to 0): the same five breaks
# forage nothing — the config drives the table, it is not a fixed chance.
#
# NEGATIVE=1 / SELFTEST=1 keeps the scenario but expects a berry from shears:
# the run MUST fail after the scenario, proving the control is not vacuous.
#
# The last green run was the retired 0.1.0 bundle on the 1d63e0a5 pin
# (`../_shared/evidence/rootsclassic/e2e-embedded.log`); this script has not run
# against an SDK package yet (no launcher and no game build at 0b14f8a here).
set -euo pipefail

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CLONE/ports/rootsclassic
SHARED=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$SHARED/horizon-ctl}
GAME=${GAME:-$PORT/target/horizon-cargo/fast/horizon-client}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/rootsclassic-e2e.sock}
NEGATIVE=${NEGATIVE:-0}
SELFTEST=${SELFTEST:-0}
# 1 only for the retired 0.1.0 bundle's embedded-content legs (see STATUS above).
EMBEDDED=${EMBEDDED:-0}
MOD=rootsclassic
FLARE=$MOD:flare_orchid
BLOOM=$MOD:midnight_bloom
DAISY=$MOD:radiant_daisy
OLD_ROOT=$MOD:old_root
SPRIG=$MOD:verdant_sprig
BULB=$MOD:infernal_bulb
EYE=$MOD:dragons_eye
POULTICE=$MOD:healing_poultice
BERRY_IDS="$MOD:blackcurrant $MOD:redcurrant $MOD:whitecurrant $MOD:elderberry $MOD:nightshade"

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/horizon-mod.toml" ] || { echo "missing package manifest: $PORT/horizon-mod.toml" >&2; exit 1; }
if [ "$EMBEDDED" = 1 ]; then
    # Retired bundle only: the content half must be the built `.hmod`, or the game would load a
    # stale copy and that run would prove nothing.
    [ -f "$PORT/content/rootsclassic.hmod" ] \
        || { echo "EMBEDDED=1 needs the retired content/rootsclassic.hmod" >&2; exit 1; }
    EMBED=$PORT/mixins/rootsclassic/data/rootsclassic-content.hmod
    cmp -s "$EMBED" "$PORT/content/rootsclassic.hmod" \
        || { echo "$EMBED is not the built content/rootsclassic.hmod" >&2; exit 1; }
fi

say() { echo "== $* =="; }
fail() { echo "FAIL: $*" >&2; exit 1; }

SCRATCH=$(mktemp -d "${E2E_TMP:-/tmp/opencode}"/rootsclassic-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$SCRATCH/config" "$SCRATCH/game"
rm -f "$SOCK"
# `Game::native_config_dir()` is `config/` in the game folder, which is the
# process's working directory: this is where the port writes and reads it.
cd "$SCRATCH"
# Retired bundle only (EMBEDDED=1): it wrote its embedded content into `.horizon-cache/` in the
# game's working directory; `--game-dir` makes the game `set_current_dir` into `$SCRATCH/game`,
# so the cache lives there, not beside this script's cwd.
CACHE_DIR=$SCRATCH/game/.horizon-cache
EMBEDDED_FILE=$CACHE_DIR/rootsclassic-embedded-content.hmod

ctl() { "$CTL" --socket "$SOCK" "$@"; }
end() { ctl command "execute in minecraft:the_end run $1"; }
health() { ctl effects | jq -r '.health'; }
pos() { ctl state | jq -c '.player.position'; }
effects() { ctl effects | jq -c '[.effects.active[].id]'; }
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
settle() {
    local last=-1 cur pend i
    for i in $(seq 1 60); do
        cur=$(ctl state | jq -r '.chunks // 0')
        pend=$(ctl state | jq -r '.streaming.queued // 0')
        [ "$cur" = "$last" ] && [ "$pend" = 0 ] && return 0
        last=$cur
        ctl wait 10 >/dev/null
    done
}
write_config() { # old_root sprig bulb eye berries
    # `Game::native_config_dir()` is `config/` in the game's working directory;
    # write it both beside the scratch cwd and under `--game-dir`, so the test
    # does not depend on which of the two the launcher hands the game.
    local dir
    for dir in "$SCRATCH/config" "$SCRATCH/game/config"; do
        mkdir -p "$dir"
        cat > "$dir/rootsclassic-common.toml" <<EOF
# Settings related to actual gameplay-affecting features
[items]
	oldRootDropChance = $1
	verdantSprigDropChance = $2
	infernalStemDropChance = $3
	dragonsEyeDropChance = $4
	berriesDropChance = $5
	barkKnifeBlockStripChance = 0.3
[magic]
	staffUses = 65
EOF
    done
}

launch() { # world
    # No `--dev-mod`: the herbs, the items and the recipes are the package's own `assets/` and
    # `data/`, installed because the launcher built this game with the mod.
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$1" --seed 20261109 --creative --offscreen --wait \
        --game-dir "$SCRATCH/game" --resources "$RES" \
        --render-distance 4
    ctl wait-ready 180
}

stop() {
    ctl quit >/dev/null 2>&1 || true
    sleep 2
    rm -f "$SOCK"
}

cleanup() {
    local status=$?
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
    echo "EXIT:$status"
}
trap cleanup EXIT

arena() {
    # The floor is wide enough that the dragon's-eye teleport (+/-16 blocks)
    # always lands on it, and the chunks stay loaded.
    end "forceload add -16 -16 64 48"
    end "fill -8 119 -8 48 119 40 minecraft:stone"
    end "tp @s 20.5 120 12.5"
    end "difficulty peaceful"
    end "gamerule spawn_mobs false"
    end "gamerule random_tick_speed 0"
    end "gamerule natural_health_regeneration false"
    # The arena stands over the End's central island, where the dragon lives; the breaks
    # below run in survival, and one unlucky strafe killed the player mid-scenario (a
    # flaky run, not a mod failure). Clearing the level removes the boss and any enderman.
    end "kill @e[type=!player]" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        [ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] && break
        ctl wait 10
    done
    [ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] \
        || fail "the player is in $(ctl state | jq -r '.dimension'), not The End"
    ctl wait-ready 180 >/dev/null
    ctl wait 20 >/dev/null
    settle
}

# Puts one item in the main hand deterministically: `ctl give` can land in the
# main inventory, where `ctl select ITEM` cannot reach it.
hold() { # item [count]
    ctl command "clear @s" >/dev/null
    ctl command "item replace entity @s hotbar.0 with $1 ${2:-1}" >/dev/null \
        || fail "cannot put $1 in the hand"
    ctl wait 2 >/dev/null
    ctl select 1 >/dev/null || fail "cannot select slot 1"
    ctl wait 2 >/dev/null
}

# Breaks a block in survival from two blocks away and prints the ctl reply.
break_block() { # x y z [held]
    ctl command "gamemode survival @s" >/dev/null
    if [ -n "${4:-}" ]; then
        hold "$4"
    else
        ctl command "clear @s" >/dev/null
    fi
    # One block away: a herb's outline is 4x8x4 pixels and from two blocks the
    # client's ray can pass over it entirely ("no face ... is visible").
    ctl tp "$1.5" 120 "$(($3 + 1)).5" >/dev/null
    ctl wait 4 >/dev/null
    # Aim into the block rather than at its centre: the block centre grazes a
    # herb's top edge.
    ctl look-at "$1.5" "$2.1" "$3.5" >/dev/null
    ctl wait 3 >/dev/null
    # One retry aimed at the block itself: the client's ray and the server's
    # block are one tick apart, so a first click can land before the aim does.
    ctl break "$1" "$2" "$3" && return 0
    ctl look-at block "$1" "$2" "$3" >/dev/null
    ctl wait 4 >/dev/null
    ctl break "$1" "$2" "$3"
}

# `bc` prints "2.0", so numeric comparisons go through awk.
diff_is() { # before after want
    awk -v a="$1" -v b="$2" -v d="$3" 'BEGIN { exit !((b - a > d - 0.05) && (b - a < d + 0.05)) }'
}
is_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

dropped() { # reply item -> count
    echo "$1" | jq -r --arg i "$2" '.drops[$i] // 0'
}

berries_in() { # reply -> total of the five berries
    local total=0 item count
    for item in $BERRY_IDS; do
        count=$(dropped "$1" "$item")
        total=$((total + count))
    done
    echo "$total"
}

no_herb() { # label reply
    local label=$1 reply=$2 item count
    for item in "$OLD_ROOT" "$SPRIG" "$BULB" "$EYE"; do
        count=$(dropped "$reply" "$item")
        [ "$count" = 0 ] || fail "$label foraged $count $item"
    done
    count=$(berries_in "$reply")
    [ "$count" = 0 ] || fail "$label foraged $count berries"
}

expect_drop() { # label reply item want
    local got
    got=$(dropped "$2" "$3")
    [ "$got" = "$4" ] || fail "$1: expected $4 $3, got $got"
    echo "$1 PASS: $got $3"
}

# =========================================================== launch 0 (control, retired)
# The retired bundle's control: the same binary with the embedded content made unavailable
# (`.horizon-cache` a plain file), so the ids must be unknown. The flat package has no embedded
# content, so this leg only runs with `EMBEDDED=1` against the 0.1.0 bundle.
if [ "$EMBEDDED" = 1 ]; then
say "launch 0 (control): the same game with no embedded content file"
rm -rf "$CACHE_DIR"
: > "$CACHE_DIR"
launch RootsClassicControl
if ctl give "$OLD_ROOT" 1 >/dev/null 2>&1; then
    fail "give $OLD_ROOT succeeded without the embedded content, so it is not what loads the ids"
fi
# The End's void, so "stayed air" cannot be a lucky Overworld coordinate.
ctl command "execute in minecraft:the_end run tp @s 30.5 120 6.5" >/dev/null
ctl wait 10 >/dev/null
ctl setblock 30 120 6 "$FLARE" >/dev/null 2>&1 || true
[ "$(block_name 30 120 6)" = minecraft:air ] \
    || fail "$FLARE became $(block_name 30 120 6) without the embedded content"
[ -f "$CACHE_DIR" ] || fail "the control's .horizon-cache was replaced: the helper wrote its content"
echo "content control PASS: unknown ids refused, $CACHE_DIR untouched"
stop
rm -f "$CACHE_DIR"
fi

# =========================================================== launch 1
say "launch 1 (the launcher-built package, every forage roll certain)"
write_config 1 1 1 1 1
launch RootsClassicE2E
if [ "$EMBEDDED" = 1 ]; then
# Retired bundle only: it must have written its content out at startup, byte for byte.
[ -f "$EMBEDDED_FILE" ] || fail "the bundle did not write its embedded content to $EMBEDDED_FILE"
cmp -s "$EMBEDDED_FILE" "$PORT/content/rootsclassic.hmod" \
    || fail "the embedded content at $EMBEDDED_FILE differs from content/rootsclassic.hmod"
echo "embedded content PASS: $(wc -c < "$EMBEDDED_FILE" | tr -d ' ') B at $EMBEDDED_FILE, identical to content/rootsclassic.hmod"
fi
if ctl logs --lines 4000 2>/dev/null | grep -q "content mods not loaded"; then
    ctl logs --lines 4000 | grep "content mods not loaded" >&2
    fail "the package's content half did not load"
fi
echo "content mod loaded (no 'content mods not loaded')"
echo "config files: $(find "$SCRATCH" -name 'rootsclassic-common.toml' -printf '%p ' 2>/dev/null)"
arena

# ------------------------------------------------------------ the native hooks
say "native check: the consume hook heals for the jar's +2"
ctl command "gamemode survival @s" >/dev/null
ctl command "effect clear @s" >/dev/null
ctl command "damage @s 4 generic" >/dev/null
ctl wait 4
ctl command "gamemode creative @s" >/dev/null
ctl wait 2
before=$(health)
hold $MOD:redcurrant
ctl use-item --hold 2 >/dev/null
ctl wait 5
after=$(health)
echo "redcurrant heal probe: $before -> $after"
diff_is "$before" "$after" 2 \
    || fail "the consume hook did not heal +2 ($before -> $after): the native bundle is not running"
echo "native PASS: rootsclassic:heal ran"

# ------------------------------------------------------------ the herbs
say "registry: every carried id exists"
for id in "$FLARE" "$BLOOM" "$DAISY" $BERRY_IDS "$OLD_ROOT" "$SPRIG" "$BULB" "$EYE" \
          "$MOD:rooty_stew" "$MOD:fruit_salad" "$POULTICE" "$MOD:pestle"; do
    ctl give "$id" 1 >/dev/null 2>&1 || fail "unknown item $id"
done
echo "registry PASS: 16 carried ids give"
ctl command "clear @s" >/dev/null

say "the three herbs place on dirt and drop themselves"
place_herb() { # x z item
    ctl command "gamemode creative @s" >/dev/null
    end "setblock $1 119 $2 minecraft:dirt" >/dev/null
    hold "$3" 4
    ctl tp "$1.5" 120 "$(($2 + 2)).5" >/dev/null
    ctl wait 4 >/dev/null
    # Right-click the dirt's top face with the herb in hand (the seed-planting
    # path Mystical Agriculture's e2e proved at this pin).
    ctl look-at block "$1" 119 "$2" up >/dev/null
    ctl wait 3 >/dev/null
    reply=$(ctl interact "$1" 119 "$2" up 2>&1) || { echo "interact reply: $reply"; fail "cannot use $3 on dirt"; }
    ctl wait 5 >/dev/null
    block_name "$1" 120 "$2"
}
for pair in "4 4 $FLARE" "5 4 $BLOOM" "6 4 $DAISY"; do
    set -- $pair
    state=$(place_herb "$1" "$2" "$3")
    [ "$state" = "$3" ] || fail "$3 placed as $state"
    echo "placed $state on dirt"
done
# Each herb drops itself on a survival break.
for pair in "4 4 $FLARE" "5 4 $BLOOM" "6 4 $DAISY"; do
    set -- $pair
    reply=$(break_block "$1" 120 "$2" 2>&1) || { echo "break reply: $reply"; fail "cannot break $3 at $1,$2"; }
    echo "$reply" | jq -c '{scenario:"herb break",block,block_before,drops}'
    expect_drop "$3 self-drop" "$reply" "$3" 1
done
ctl command "gamemode creative @s" >/dev/null

say "a herb refuses stone as its ground (the wrong-soil control)"
end "setblock 10 119 8 minecraft:stone"
hold "$FLARE"
ctl tp 10.5 120 10.5 >/dev/null
ctl wait 4 >/dev/null
ctl look-at block 10 119 8 up >/dev/null
ctl wait 3 >/dev/null
ctl interact 10 119 8 up >/dev/null 2>&1 || true
ctl wait 5 >/dev/null
[ "$(block_name 10 120 8)" = minecraft:air ] \
    || fail "a flare orchid planted itself on stone: $(block_name 10 120 8)"
echo "wrong soil PASS: nothing on stone"

# ------------------------------------------------------------ the forage
say "forage: short grass -> old root; a young crop and stone forage nothing"
end "setblock 12 119 4 minecraft:dirt"
end "setblock 12 120 4 minecraft:short_grass"
ctl wait 4
reply=$(break_block 12 120 4 2>&1) || { echo "break reply: $reply"; fail "cannot break 12 120 4"; }
echo "$reply" | jq -c '{scenario:"short_grass",block,block_before,drops}'
echo "config files after the first break: $(find "$SCRATCH" -name 'rootsclassic-common.toml' -printf '%p ' 2>/dev/null)"
expect_drop "short_grass" "$reply" "$OLD_ROOT" 1
end "setblock 13 120 4 minecraft:stone"
ctl wait 4
reply=$(break_block 13 120 4 2>&1) || { echo "break reply: $reply"; fail "cannot break 13 120 4"; }
echo "$reply" | jq -c '{scenario:"stone control",block,block_before,drops}'
no_herb "stone" "$reply"
echo "stone control PASS: nothing foraged"

say "forage: a grown crop -> verdant sprig; a young one -> nothing"
end "fill 16 119 2 18 119 2 minecraft:farmland[moisture=7]"
end "setblock 16 120 2 minecraft:wheat[age=7]"
end "setblock 18 120 2 minecraft:wheat[age=0]"
ctl wait 4
reply=$(break_block 16 120 2 2>&1) || { echo "break reply: $reply"; fail "cannot break 16 120 2"; }
echo "$reply" | jq -c '{scenario:"wheat age=7",block,block_before,drops}'
expect_drop "wheat age 7" "$reply" "$SPRIG" 1
reply=$(break_block 18 120 2 2>&1) || { echo "break reply: $reply"; fail "cannot break 18 120 2"; }
echo "$reply" | jq -c '{scenario:"wheat age=0",block,block_before,drops}'
no_herb "wheat age 0" "$reply"
echo "young crop control PASS: nothing foraged"

say "forage: ripe nether wart -> infernal bulb; young -> nothing"
end "fill 21 119 2 22 119 2 minecraft:soul_sand"
end "setblock 21 120 2 minecraft:nether_wart[age=3]"
end "setblock 22 120 2 minecraft:nether_wart[age=0]"
ctl wait 4
reply=$(break_block 21 120 2 2>&1) || { echo "break reply: $reply"; fail "cannot break 21 120 2"; }
echo "$reply" | jq -c '{scenario:"nether_wart age=3",block,block_before,drops}'
expect_drop "nether wart age 3" "$reply" "$BULB" 1
reply=$(break_block 22 120 2 2>&1) || { echo "break reply: $reply"; fail "cannot break 22 120 2"; }
echo "$reply" | jq -c '{scenario:"nether_wart age=0",block,block_before,drops}'
no_herb "nether wart age 0" "$reply"
echo "young wart control PASS: nothing foraged"

say "forage: a chorus flower -> dragon's eye"
# A chorus flower needs end stone under it, or the block update pops it.
end "setblock 25 119 4 minecraft:end_stone"
end "setblock 25 120 4 minecraft:chorus_flower"
ctl wait 4
reply=$(break_block 25 120 4 2>&1) || { echo "break reply: $reply"; fail "cannot break 25 120 4"; }
echo "$reply" | jq -c '{scenario:"chorus_flower",block,block_before,drops}'
expect_drop "chorus flower" "$reply" "$EYE" 1

say "forage: oak leaves by hand -> one berry; with shears -> the leaves, no berry"
end "fill 28 120 2 29 120 2 minecraft:oak_leaves"
ctl wait 4
reply=$(break_block 28 120 2 2>&1) || { echo "break reply: $reply"; fail "cannot break 28 120 2"; }
echo "$reply" | jq -c '{scenario:"oak leaves",block,block_before,drops}'
got=$(berries_in "$reply")
[ "$got" = 1 ] || fail "oak leaves by hand dropped $got berries, expected 1"
echo "leaves PASS: $got berry"
reply=$(break_block 29 120 2 minecraft:shears 2>&1) || { echo "break reply: $reply"; fail "cannot break 29 120 2 minecraft:shears"; }
echo "$reply" | jq -c '{scenario:"oak leaves, shears",block,block_before,drops}'
sheared=$(dropped "$reply" minecraft:oak_leaves)
[ "$sheared" = 1 ] || fail "shears dropped $sheared oak leaves, expected 1"
no_herb "leaves with shears" "$reply"
if [ "$NEGATIVE" = 1 ] || [ "$SELFTEST" = 1 ]; then
    got=$(berries_in "$reply")
    [ "$got" = 1 ] || fail "SELFTEST: shears foraged no berry (the control is alive)"
fi
echo "shears control PASS: the leaves dropped, no berry"

# ------------------------------------------------------------ the eaten effects
say "the herbs' eaten effects: redcurrant +2, poultice +5, old root nothing"
ctl command "gamemode survival @s" >/dev/null
ctl command "effect clear @s" >/dev/null
ctl command "damage @s 10 generic" >/dev/null
ctl wait 4
ctl command "gamemode creative @s" >/dev/null
ctl wait 2
before=$(health)
hold $MOD:redcurrant
ctl use-item --hold 2 >/dev/null
ctl wait 5
after=$(health)
echo "redcurrant: $before -> $after"
is_gt "$after" "$before" || fail "the redcurrant healed nothing ($before -> $after)"
diff_is "$before" "$after" 2 || fail "the redcurrant healed $before -> $after, expected exactly +2"
echo "redcurrant PASS: $before -> $after"
ctl command "gamemode survival @s" >/dev/null
ctl command "damage @s 4 generic" >/dev/null
ctl wait 4
ctl command "gamemode creative @s" >/dev/null
ctl wait 2
before=$(health)
hold "$POULTICE"
ctl use-item --hold 2 >/dev/null
ctl wait 5
after=$(health)
echo "healing poultice: $before -> $after"
diff_is "$before" "$after" 5 || fail "the poultice healed $before -> $after, expected exactly +5"
echo "poultice PASS: $before -> $after"
before=$(health)
hold "$OLD_ROOT"
ctl use-item --hold 2 >/dev/null
ctl wait 5
after=$(health)
[ "$after" = "$before" ] || fail "old root changed health ($before -> $after)"
echo "old root control PASS: health stays $after"

say "elderberry clears effects; nightshade poisons"
ctl command "effect clear @s" >/dev/null
ctl command "effect give @s minecraft:poison 200 1" >/dev/null
ctl wait 3
effects | grep -q poison || fail "the poison control did not apply: $(effects)"
hold $MOD:elderberry
ctl use-item --hold 2 >/dev/null
ctl wait 5
effects | grep -q poison && fail "the elderberry left the poison: $(effects)"
echo "elderberry PASS: effects $(effects)"
ctl command "effect clear @s" >/dev/null
hold $MOD:nightshade
ctl use-item --hold 2 >/dev/null
ctl wait 5
effects | grep -q poison || fail "nightshade applied no poison: $(effects)"
echo "nightshade PASS: effects $(effects)"
ctl command "effect clear @s" >/dev/null

say "the dragon's eye teleports the eater"
before=$(pos)
hold "$EYE"
ctl use-item --hold 2 >/dev/null
ctl wait 8
after=$(pos)
moved=$(python3 - "$before" "$after" <<'PY'
import json, math, sys
a = json.loads(sys.argv[1]); b = json.loads(sys.argv[2])
print(round(math.dist(a, b), 2))
PY
)
echo "dragon's eye: $before -> $after (moved $moved)"
is_gt "$moved" 1 || fail "the dragon's eye did not move the player ($before -> $after, moved $moved)"
echo "dragon's eye PASS: moved $moved blocks"

# ------------------------------------------------------------ recipes
say "the five recipes are registered (a known recipe id, or the file did not load)"
for recipe in pestle pestle2 rooty_stew fruit_salad healing_poultice; do
    reply=$(ctl command "recipe give @s rootsclassic:$recipe" 2>&1) || true
    case "$reply" in
        *'"ok":true'*) echo "recipe rootsclassic:$recipe exists" ;;
        *) fail "recipe rootsclassic:$recipe did not load: $reply" ;;
    esac
done

say "crafting: the jar's recipes in a real table, with wrong-ingredient controls"
# Survival, not creative: in creative the inventory screen is the creative page,
# which has no crafting grid.
ctl command "gamemode survival @s" >/dev/null
ctl command "effect clear @s" >/dev/null
ctl wait 5 >/dev/null
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" 30 120 16 || {
    echo "content log around the recipes:"
    ctl logs --lines 800 2>/dev/null | grep -i "recipe\|rootsclassic" | tail -20 || true
    fail "craft_check.py failed"
}

# ------------------------------------------------------------ launch 2
say "launch 2: chances 0 in the config, so the same breaks forage nothing"
stop
write_config 0 0 0 0 0
launch RootsClassicE2E
arena
end "setblock 12 119 4 minecraft:dirt"
end "setblock 12 120 4 minecraft:short_grass"
end "fill 16 119 2 17 119 2 minecraft:farmland[moisture=7]"
end "setblock 16 120 2 minecraft:wheat[age=7]"
end "fill 21 119 2 21 119 2 minecraft:soul_sand"
end "setblock 21 120 2 minecraft:nether_wart[age=3]"
# A chorus flower needs end stone under it, or the block update pops it.
end "setblock 25 119 4 minecraft:end_stone"
end "setblock 25 120 4 minecraft:chorus_flower"
end "fill 28 120 2 28 120 2 minecraft:oak_leaves"
ctl wait 6
for spot in "12 120 4" "16 120 2" "21 120 2" "25 120 4" "28 120 2"; do
    set -- $spot
    reply=$(break_block "$1" "$2" "$3" 2>&1) || { echo "break reply: $reply"; fail "cannot break $1,$2,$3 at chance 0"; }
    echo "$reply" | jq -c '{scenario:"chances 0",block,block_before,drops}'
    no_herb "chances 0 at $1,$2,$3" "$reply"
done
echo "config control PASS: chance 0 forages nothing"

# ------------------------------------------------------------ done
stop

if [ "$NEGATIVE" = 1 ] || [ "$SELFTEST" = 1 ]; then
    echo "FAIL: SELFTEST: shears on leaves foraged no berry (the check is alive)" >&2
    exit 1
fi

echo "PASS: the package's own content loads (no --dev-mod) and the three herbs place on dirt, refuse stone and drop themselves; short grass, a grown crop, ripe nether wart, a chorus flower and oak leaves forage the jar's old root, verdant sprig, infernal bulb, dragon's eye and one berry at chance 1, while a young crop, young wart, stone and sheared leaves forage nothing; the same breaks forage nothing at chance 0; redcurrant heals 2, the poultice 5, elderberry clears effects, nightshade poisons, the dragon's eye teleports and old root changes nothing; the jar's recipes craft with empty wrong-ingredient controls"
echo "EXIT:0"
exit 0

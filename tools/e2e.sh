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
# Slice 2 adds the powder chain (0.2.1):
#   6. growth powder on dirt makes grass and is spent; on stone nothing changes
#      and nothing is spent; on a young wheat it advances the age and is spent;
#   7. the three mutations, each in its dimension with its effect and exactly
#      its two or three ingredients summoned as item entities: the flare orchid
#      (Nether, fire resistance, netherrack ring, Fire ticks on the player), the
#      midnight bloom (The End, obsidian two below, slowness, skipTicks=200) and
#      the radiant daisy (Overworld at noon, night vision, blindness);
#   8. their controls: no fire resistance, a bystander item entity in the box
#      and midnight instead of noon each leave the vanilla flower alone, and the
#      powder is spent even when nothing matched (the jar's own behaviour).
#
# NEGATIVE=1 / SELFTEST=1 keeps the scenario but expects a berry from shears
# (and a mutation without fire resistance), so the run MUST fail: the controls
# are not vacuous.
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
    # Wide enough for the dragon's eye's +/-16 blocks in both axes: a landing
    # outside the floor drops the player into the End's void.
    end "fill -8 119 -20 48 119 40 minecraft:stone"
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

# ---- slice 2 helpers: dimensions, item entities, the player file -----------
# Run a command in another dimension (`execute in <dim> run ...`).
at() { ctl command "execute in $1 run $2" >/dev/null; }
dimension() { ctl state | jq -r '.dimension'; }
# Wait until the player is in DIM (`execute in ... run tp` moves them).
enter() { # dim
    local i
    for i in $(seq 1 40); do
        [ "$(dimension)" = "$1" ] && return 0
        ctl wait 10 >/dev/null
    done
    fail "the player is in $(dimension), not $1"
}
count_of() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
items_near() { ctl entities 8 item | jq -r '.entities | length'; }
# One item entity nothing picks up, from the jar's own `AABB` scan box.
summon_item() { # dim x y z item [count]
    at "$1" "summon item $2 $3 $4 {Item:{id:\"$5\",count:${6:-1}},PickupDelay:32767s,Age:-32768s}"
}
# Aim at a point. The mutations aim *inside* a flower's outline, not at its top
# face: a ray that grazes the face only (the ring stands at the same height)
# passes over the flower and lands on the netherrack behind it.
aim_point() { # x y z
    ctl look-at "$1" "$2" "$3" >/dev/null 2>&1 \
        || fail "cannot aim at point $1 $2 $3: $(ctl looking-at 2>&1)"
    ctl wait 3 >/dev/null
}
# Stand at a spot, verifying it: a `tp` that lands elsewhere leaves the next click
# "out of reach" and reads like a port failure.
goto_spot() { # x y z
    local i pos
    for i in 1 2 3 4 5; do
        # A server-side teleport, as the vanilla `/tp` runs it: the client-only
        # cursor moved but the click path still saw the old position 6.8 blocks
        # away, so this leg never reached its block.
        ctl command "tp @s $1 $2 $3" >/dev/null 2>&1 || true
        ctl wait 4 >/dev/null
        pos=$(ctl state | jq -c '.player.position')
        python3 - "$1" "$2" "$3" "$pos" <<'PY' && return 0
import json, math, sys
x, y, z = (float(v) for v in sys.argv[1:4])
try:
    here = json.loads(sys.argv[4])
except (ValueError, TypeError):
    raise SystemExit(1)
raise SystemExit(0 if here and math.dist((x, y, z), here) < 1.0 else 1)
PY
    done
    fail "the player never reached $1 $2 $3 (at $pos)"
}

# Right-click a block's face, with one retry: the client's ray and the server's
# block are a tick apart, so the first click can land before the aim does (the
# herbs' `break_block` has the same retry for the same reason).
click_block() { # x y z face
    local reply
    if reply=$(ctl interact "$1" "$2" "$3" "$4" 2>&1); then
        return 0
    fi
    echo "interact retry: $reply" >&2
    ctl look-at block "$1" "$2" "$3" "$4" >/dev/null 2>&1 || true
    ctl wait 4 >/dev/null
    reply=$(ctl interact "$1" "$2" "$3" "$4" 2>&1) && return 0
    echo "interact reply: $reply" >&2
    echo "  player $(ctl state | jq -c '{position, dimension, screen}') looking-at $(ctl looking-at 2>&1)" >&2
    return 1
}
grown_age() { ctl block 10 120 16 | jq -r '.state' | sed -n 's/.*age=\([0-9]*\).*/\1/p'; }
netherrack_ring() {
    local spot
    for spot in 5,4 3,4 4,3 4,5 5,3 3,5 3,3 5,5; do
        at minecraft:the_nether "setblock ${spot%,*} 120 ${spot#*,} minecraft:netherrack"
    done
}
# One entity tag through `/data get entity @s`: the mutation's side effects are
# entity tags (`Fire`, `NeoForgeData`) that `ctl state`/`ctl effects` do not
# report. The reply is the command's chat line.
data_get() { ctl command "data get entity @s $1" | jq -r '.chat[0] // ""'; }
# The `s` number in "… has the following entity data: 400s".
data_short() { # path
    data_get "$1" | sed -n 's/.*data: \(-\?[0-9][0-9]*\)s.*/\1/p'
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
# Creative for the teleport: it lands up to 16 blocks up or down, and a fall of
# that height would damage a survival player enough to matter (and a landing off
# the floor would be the void). The move is measured the same either way.
ctl command "gamemode creative @s" >/dev/null
ctl wait 2 >/dev/null
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
# The teleport is random (+/-16 blocks, and vertically too): it can land off the
# floor. Put the player back and rescue a death rather than failing the next leg
# with a dead screen.
ctl command "gamemode creative @s" >/dev/null
end "tp @s 20.5 120 12.5"
ctl wait 10 >/dev/null
if [ "$(ctl screen | jq -r '.screen // empty')" = dead ]; then
    ctl respawn >/dev/null 2>&1 || true
    ctl wait 10 >/dev/null
    ctl command "gamemode creative @s" >/dev/null
    end "tp @s 20.5 120 12.5"
    ctl wait 6 >/dev/null
fi
ctl command "effect clear @s" >/dev/null

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


# ------------------------------------------------------------ the powders (slice 2)
say "growth powder: dirt -> grass and the powder is spent; stone grows nothing and is free"
end "setblock 6 119 16 minecraft:dirt"
end "setblock 8 119 16 minecraft:stone"
end "setblock 10 119 16 minecraft:farmland[moisture=7]"
end "setblock 10 120 16 minecraft:wheat[age=0]"
ctl wait 6 >/dev/null
ctl command "gamemode survival @s" >/dev/null
ctl command "effect clear @s" >/dev/null

hold $MOD:growth_powder 3
goto_spot 6.5 120 18.5
ctl look-at block 6 119 16 up >/dev/null
ctl wait 3 >/dev/null
before=$(count_of "$MOD:growth_powder")
click_block 6 119 16 up || fail "cannot use the growth powder on dirt"
ctl wait 6 >/dev/null
state=$(block_name 6 119 16)
after=$(count_of "$MOD:growth_powder")
[ "$state" = minecraft:grass_block ] || fail "growth powder on dirt gave $state, expected grass"
[ "$before" = 3 ] || fail "the growth powder leg started with $before in hand, expected 3"
[ "$after" = 2 ] || fail "growth powder on dirt: $before -> $after, expected one spent"
echo "growth powder PASS: dirt -> $state, powder $before -> $after"

hold $MOD:growth_powder 2
goto_spot 8.5 120 18.5
ctl look-at block 8 119 16 up >/dev/null
ctl wait 3 >/dev/null
before=$(count_of "$MOD:growth_powder")
click_block 8 119 16 up || true
ctl wait 6 >/dev/null
state=$(block_name 8 119 16)
after=$(count_of "$MOD:growth_powder")
[ "$state" = minecraft:stone ] || fail "growth powder turned stone into $state"
[ "$after" = "$before" ] || fail "growth powder on stone spent $before -> $after, expected nothing spent"
echo "stone control PASS: $state unchanged, powder stays $after"

hold $MOD:growth_powder 2
goto_spot 10.5 120 18.5
# A wheat at age 0 is two pixels tall: `look-at block … up` finds no face, so the
# click is aimed at a point inside the crop and made with `use-item`.
before=$(grown_age)
aim_point 10.5 120.06 16.5
ctl use-item >/dev/null 2>&1 || true
ctl wait 8 >/dev/null
if [ "$(grown_age)" = "$before" ]; then
    aim_point 10.5 120.06 16.5
    ctl use-item >/dev/null 2>&1 || true
    ctl wait 8 >/dev/null
fi
after=$(grown_age)
[ "$before" = 0 ] || fail "the wheat started at age $before, expected 0"
is_gt "$after" 0 || fail "the growth powder did not advance the young crop (age $before -> $after)"
[ "$(count_of "$MOD:growth_powder")" = 1 ] \
    || fail "growth powder on a growing crop left $(count_of "$MOD:growth_powder"), expected one of two"
echo "growing crop PASS: wheat age $before -> $after, one powder spent"

# ------------------------------------------------------------ the mutations
say "mutating powder: the flare orchid in the Nether"
at minecraft:the_nether "forceload add 0 0 15 15"
at minecraft:the_nether "fill 0 119 0 12 119 12 minecraft:stone"
at minecraft:the_nether "fill 0 120 0 12 124 12 minecraft:air"
at minecraft:the_nether "kill @e[type=!player]"
at minecraft:the_nether "setblock 4 119 4 minecraft:dirt"
at minecraft:the_nether "setblock 4 120 4 minecraft:blue_orchid"
netherrack_ring
# The ring blocks the line of sight from every side, so the click comes from a
# stand one block above it, two blocks north of the flower.
at minecraft:the_nether "setblock 4 121 6 minecraft:stone"
at minecraft:the_nether "tp @s 4.5 122 6.5"
enter minecraft:the_nether
ctl wait 20 >/dev/null
ctl command "effect clear @s" >/dev/null
ctl command "effect give @s minecraft:fire_resistance 900" >/dev/null
for attempt in 1 2 3; do
    at minecraft:the_nether "setblock 4 120 4 minecraft:blue_orchid"
    at minecraft:the_nether "kill @e[type=item]"
    ctl wait 4 >/dev/null
    hold $MOD:mutating_powder 1
    summon_item minecraft:the_nether 5.5 122.5 4.5 minecraft:blaze_rod
    summon_item minecraft:the_nether 3.5 122.5 4.5 minecraft:lava_bucket
    ctl wait 6 >/dev/null
    echo "flare box before: $(items_near) item entities, block $(block_name 4 120 4)"
    echo "flare scene: dimension=$(dimension) effects=$(effects)"
    echo "flare ring: $(for spot in 5,4 3,4 4,3 4,5 5,3 3,5 3,3 5,5; do block_name "${spot%,*}" 120 "${spot#*,}"; done | tr '\n' ' ')"
    before=$(count_of "$MOD:mutating_powder")
    aim_point 4.5 120.3 4.5
    echo "flare aim: $(ctl looking-at 2>&1 | jq -c '{kind, block}' 2>/dev/null || true)"
    ctl use-item >/dev/null 2>&1 || true
    ctl wait 6 >/dev/null
    echo "flare after the click: powder $before -> $(count_of "$MOD:mutating_powder"), entities $(items_near)"
    [ "$(block_name 4 120 4)" = $MOD:flare_orchid ] && break
    echo "  attempt $attempt did not mutate; retrying" >&2
done
state=$(block_name 4 120 4)
after=$(count_of "$MOD:mutating_powder")
[ "$state" = $MOD:flare_orchid ] || fail "the blue orchid stayed $state, expected $MOD:flare_orchid"
[ "$(items_near)" = 0 ] || fail "the mutation left $(items_near) item entities behind"
[ "$before" = 1 ] || fail "the flare leg started with $before powders, expected 1"
[ "$after" = 0 ] || fail "mutating powder on a hit: $before -> $after, expected one spent"
echo "flare orchid PASS: $state, ingredients gone, powder $before -> $after"
fire=$(data_short Fire)
is_gt "${fire:-0}" 200 || fail "the flare orchid did not set the player on fire (Fire=$fire)"
echo "flare orchid PASS: the player burns (Fire=$fire ticks, /data get entity @s Fire)"

say "control: no fire resistance, so the same box leaves the blue orchid alone"
ctl command "effect clear @s" >/dev/null
at minecraft:the_nether "setblock 4 120 4 minecraft:blue_orchid"
hold $MOD:mutating_powder 1
summon_item minecraft:the_nether 5.5 122.5 4.5 minecraft:blaze_rod
summon_item minecraft:the_nether 3.5 122.5 4.5 minecraft:lava_bucket
ctl wait 6 >/dev/null
aim_point 4.5 120.3 4.5
ctl use-item >/dev/null 2>&1 || true
ctl wait 6 >/dev/null
state=$(block_name 4 120 4)
if [ "$state" = $MOD:flare_orchid ]; then
    fail "SELFTEST: without fire resistance the blue orchid mutated (the control is dead)"
fi
[ "$state" = minecraft:blue_orchid ] || fail "the control left $state, expected the blue orchid"
[ "$(count_of "$MOD:mutating_powder")" = 0 ] \
    || fail "a failed mutation left $(count_of "$MOD:mutating_powder"), expected the jar's one spent"
echo "no-resistance control PASS: $state kept, the powder is still spent"
at minecraft:the_nether "kill @e[type=item]"

say "control: a bystander item entity stops the mutation (the jar's exact match)"
ctl command "effect give @s minecraft:fire_resistance 900" >/dev/null
hold $MOD:mutating_powder 1
summon_item minecraft:the_nether 5.5 122.5 4.5 minecraft:blaze_rod
summon_item minecraft:the_nether 3.5 122.5 4.5 minecraft:lava_bucket
summon_item minecraft:the_nether 4.5 122.5 5.5 minecraft:stick
ctl wait 6 >/dev/null
aim_point 4.5 120.3 4.5
ctl use-item >/dev/null 2>&1 || true
ctl wait 6 >/dev/null
state=$(block_name 4 120 4)
[ "$state" = minecraft:blue_orchid ] || fail "an extra item entity still mutated the flower into $state"
[ "$(items_near)" = 3 ] || fail "the refused mutation destroyed items: $(items_near) left of 3"
echo "extra-item control PASS: $state kept, all 3 entities still there"
at minecraft:the_nether "kill @e[type=item]"

say "mutating powder: the midnight bloom in The End"
at minecraft:the_end "setblock 10 118 12 minecraft:obsidian"
at minecraft:the_end "setblock 10 119 12 minecraft:dirt"
at minecraft:the_end "setblock 10 120 12 minecraft:poppy"
at minecraft:the_end "tp @s 10.5 120 14.5"
enter minecraft:the_end
ctl wait 10 >/dev/null
ctl command "effect clear @s" >/dev/null
ctl command "effect give @s minecraft:slowness 900" >/dev/null
for attempt in 1 2 3; do
    at minecraft:the_end "setblock 10 120 12 minecraft:poppy"
    at minecraft:the_end "kill @e[type=item]"
    ctl wait 4 >/dev/null
    hold $MOD:mutating_powder 1
    summon_item minecraft:the_end 11.5 122.5 12.5 minecraft:coal_block
    ctl wait 6 >/dev/null
    echo "bloom scene: dimension=$(dimension) effects=$(effects) block=$(block_name 10 120 12) below2=$(block_name 10 118 12) entities=$(items_near)"
    before=$(count_of "$MOD:mutating_powder")
    aim_point 10.5 120.3 12.5
    echo "bloom aim: $(ctl looking-at 2>&1 | jq -c '{kind, block}' 2>/dev/null || true)"
    ctl use-item >/dev/null 2>&1 || true
    ctl wait 6 >/dev/null
    echo "bloom after the click: powder $before -> $(count_of "$MOD:mutating_powder"), entities $(items_near)"
    [ "$(block_name 10 120 12)" = $MOD:midnight_bloom ] && break
    echo "  attempt $attempt did not mutate; retrying" >&2
done
state=$(block_name 10 120 12)
[ "$state" = $MOD:midnight_bloom ] || fail "the poppy stayed $state, expected $MOD:midnight_bloom"
skip=$(data_get NeoForgeData)
case "$skip" in
    *RMOD_skipTicks*200*) ;;
    *) fail "the midnight bloom left the player's NeoForgeData as $skip, expected skipTicks 200" ;;
esac
echo "midnight bloom PASS: $state, NeoForgeData=$skip"

say "mutating powder: the radiant daisy in the Overworld at noon"
at minecraft:overworld "forceload add 0 0 15 15"
at minecraft:overworld "fill 0 100 0 12 100 12 minecraft:stone"
at minecraft:overworld "fill 0 101 0 12 105 12 minecraft:air"
at minecraft:overworld "kill @e[type=!player]"
at minecraft:overworld "setblock 4 100 4 minecraft:dirt"
at minecraft:overworld "setblock 4 101 4 minecraft:oxeye_daisy"
at minecraft:overworld "gamerule do_daylight_cycle false"
at minecraft:overworld "time set 6000"
at minecraft:overworld "tp @s 4.5 101 6.5"
enter minecraft:overworld
ctl wait 20 >/dev/null
noon=$(ctl state | jq -r '.time.time_of_day')
awk -v t="$noon" 'BEGIN { exit !(t > 5000 && t < 7000) }' \
    || fail "the Overworld time of day is $noon, outside the daisy's 5000..7000"
ctl command "effect clear @s" >/dev/null
ctl command "effect give @s minecraft:night_vision 900" >/dev/null
for attempt in 1 2 3; do
    at minecraft:overworld "setblock 4 101 4 minecraft:oxeye_daisy"
    at minecraft:overworld "kill @e[type=item]"
    ctl wait 4 >/dev/null
    hold $MOD:mutating_powder 1
    summon_item minecraft:overworld 5.5 103.5 4.5 minecraft:glowstone
    summon_item minecraft:overworld 3.5 103.5 4.5 minecraft:prismarine_crystals
    ctl wait 6 >/dev/null
    before=$(count_of "$MOD:mutating_powder")
    aim_point 4.5 101.3 4.5
    ctl use-item >/dev/null 2>&1 || true
    ctl wait 6 >/dev/null
    echo "daisy after the click: powder $before -> $(count_of "$MOD:mutating_powder"), block $(block_name 4 101 4)"
    [ "$(block_name 4 101 4)" = $MOD:radiant_daisy ] && break
    echo "  attempt $attempt did not mutate; retrying" >&2
done
state=$(block_name 4 101 4)
after=$(count_of "$MOD:mutating_powder")
[ "$state" = $MOD:radiant_daisy ] || fail "the oxeye daisy stayed $state, expected $MOD:radiant_daisy"
effects | grep -q blindness || fail "the radiant daisy applied no blindness: $(effects)"
[ "$before" = 1 ] || fail "the daisy leg started with $before powders, expected 1"
[ "$after" = 0 ] || fail "mutating powder on a hit: $before -> $after, expected one spent"
echo "radiant daisy PASS: $state, blindness applied, powder $before -> $after"

say "control: the same daisy box at midnight stays an oxeye daisy"
at minecraft:overworld "setblock 4 101 4 minecraft:oxeye_daisy"
at minecraft:overworld "time set 18000"
hold $MOD:mutating_powder 1
summon_item minecraft:overworld 5.5 103.5 4.5 minecraft:glowstone
summon_item minecraft:overworld 3.5 103.5 4.5 minecraft:prismarine_crystals
ctl wait 6 >/dev/null
aim_point 4.5 101.3 4.5
ctl use-item >/dev/null 2>&1 || true
ctl wait 6 >/dev/null
state=$(block_name 4 101 4)
[ "$state" = minecraft:oxeye_daisy ] || fail "at midnight the daisy mutated into $state"
echo "midnight control PASS: $state kept"
at minecraft:overworld "kill @e[type=item]"
at minecraft:the_end "tp @s 20.5 120 12.5"
enter minecraft:the_end
ctl command "gamemode creative @s" >/dev/null
ctl command "effect clear @s" >/dev/null

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

echo "PASS: the package's own content loads (no --dev-mod) and the three herbs place on dirt, refuse stone and drop themselves; short grass, a grown crop, ripe nether wart, a chorus flower and oak leaves forage the jar's old root, verdant sprig, infernal bulb, dragon's eye and one berry at chance 1, while a young crop, young wart, stone and sheared leaves forage nothing; the same breaks forage nothing at chance 0; redcurrant heals 2, the poultice 5, elderberry clears effects, nightshade poisons, the dragon's eye teleports and old root changes nothing; the jar's recipes craft with empty wrong-ingredient controls (the powders included); growth powder turns dirt to grass and grows a young crop, spending itself, and refuses stone for free; mutating powder turns a blue orchid into a flare orchid in the Nether (the player burns), a poppy into a midnight bloom in The End (skipTicks 200) and an oxeye daisy into a radiant daisy at noon (blindness), consuming its ingredients and one powder, while no fire resistance, a bystander item entity and midnight each leave the flower alone"
echo "EXIT:0"
exit 0

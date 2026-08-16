"""Regression tests for playtest-derived fixes. Each section names the bug it
covers; run after the build (CI runs all tests/test_*.py).

Covered fixes:
  R1  drag symmetry (west/north thrust worked nowhere)
  R2  storm drift is collision-checked (no crossing continents)
  R3  storms are cleared on shipwreck (no wreck loops)
  R4  9-bit wy in southern streaming (rows >= 256 rendered garbage)
  R5  column blits use their stage-time base row (diagonal scrolls shifted)
  R6  spawn is in open ocean (seed FFFFFFFF spawned in a puddle)
  R7  enemies with no line of sight give up (guardian lagoon stalemate)
  R8  final-battle despawn hands the wave back (finale softlock)
  R9  tavern isle rumor shows the isle's own distance/bearing
  R10 tavern prints the isle rumor even when no port is nearby
  R11 port menu wraps upward from the top item
  R12 gold display clamps to 9999
  R13 boot clears volatile combat/storm state (phantom storm from random WRAM)
  R14 digging up a fragment does not fire the cannons
  R15 SaveGame sets wHasSave (editor offers LOAD without a console reset)
  R16 boot clears fire cooldowns (R13 follow-through)
  R17 tavern nearest-port scan covers whole rings (signed loop bound made
      rings r>=2 test only their NW corner) and SW bears as SW, not S

Freebies:
  F1  B-at-sea quit requires a confirming second press
  F2  storm drift range extended to +-32 (risk/reward fast current)
  F3  window HUD row 2 shows hull / gold / fragments at sea
"""
import os
from pathlib import Path

from pyboy import PyBoy

ROOT = Path(__file__).resolve().parents[1]
ROM = os.environ.get("PF_ROM", str(ROOT / "pirates_folly.gb"))
SYM = os.environ.get("PF_SYM", str(ROOT / "build" / "pirates_folly.sym"))

syms = {}
for line in open(SYM):
    p = line.split()
    if len(p) == 2 and p[1] not in syms:
        syms[p[1]] = int(p[0].split(":")[1], 16)

# ---------------------------------------------------------------- reference
# Python port of the game's worldgen (mirrors src/world.asm / port.asm).

def mix16(x):
    x &= 0xFFFF
    x ^= x >> 8
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF

def lathash(ix, iy, s16):
    return mix16(((ix * 97 + iy * 61) & 0xFFFF) ^ s16) & 0xFF

def _mulmag(m, f):
    return (m * f) >> 3

def _lerp(base, other, f):
    d = other - base
    return base + (_mulmag(d, f) if d >= 0 else -_mulmag(-d, f))

def elevation(wx, wy, s16):
    ix, iy = wx >> 3, wy >> 3
    fx, fy = wx & 7, wy & 7
    h00 = lathash(ix, iy, s16)
    h10 = lathash(ix + 1, iy, s16)
    h01 = lathash(ix, iy + 1, s16)
    h11 = lathash(ix + 1, iy + 1, s16)
    return _lerp(_lerp(h00, h10, fx), _lerp(h01, h11, fx), fy)

def tile_detail(wx, wy, s16):
    return mix16((((wx & 0xFF) * 29 + (wy & 0xFF) * 53) & 0xFFFF) ^ s16) & 0xF

def tile(wx, wy, s16):
    e = elevation(wx, wy, s16)
    if e < 132: return 1
    if e < 148: return 2
    if e < 158: return 3
    if e < 205: return 4
    d = tile_detail(wx, wy, s16)
    if d == 0: return 6
    if d < 6: return 5
    return 4

def district_hash(dx, dy, s16):
    return mix16(((dx * 37 + dy * 91) & 0xFFFF) ^ s16 ^ 0x7E55)

def has_port(dx, dy, s16):
    return (district_hash(dx, dy, s16) & 0x3F) < 12

def shown_tile(wx, wy, s16):
    t = tile(wx, wy, s16)
    if t == 3 and has_port(wx >> 2, wy >> 2, s16):
        return 14
    return t

def snap_dir(dx, dy):
    ax, ay = abs(dx), abs(dy)
    if 2 * ay < ax:
        return 2 if dx > 0 else 6
    if 2 * ax < ay:
        return 4 if dy > 0 else 0
    if dy < 0:
        return 7 if dx < 0 else 1
    return 5 if dx < 0 else 3

DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
ISLE_NAMES = ["LIBERTALIA", "WHYDAH DEEP", "KRAKEN SKERRY", "THE LOCKER",
              "OLD ROGER ROCK", "KIDDS CACHE", "FIDDLERS GREEN",
              "DUTCHMAN CAPE", "MAROON SPIT"]

# ---------------------------------------------------------------- helpers

def boot(garbage=False):
    # Boot a save-free copy of the ROM: PyBoy loads <rom>.ram next to the
    # ROM path and writes it back on stop(), so reusing one path makes every
    # later boot inherit an earlier boot's save. A fresh copy per boot keeps
    # every test on the deterministic default-seed boot, like CI.
    import shutil, tempfile
    path = str(Path(tempfile.mkdtemp()) / "pf.gb")
    shutil.copy(ROM, path)
    pb = PyBoy(path, window="null")
    pb.set_emulation_speed(0)
    if garbage:
        # simulate power-on WRAM garbage BEFORE the first tick (PyBoy zeroes
        # RAM by default; hardware and accurate emulators do not)
        import random
        rng = random.Random(1234)
        for name in ("wStormT", "wStormDX", "wStormDY", "wStormDmgT",
                     "wEnemyActive", "wBallPActive", "wBallEActive",
                     "wFireCool", "wEnemyFireCool"):
            a = syms[name]
            n = 2 if name == "wStormT" else 1
            for i in range(n):
                pb.memory[a + i] = rng.randrange(256)
    for _ in range(150):
        pb.tick()
    return pb

def press(pb, btn, wait=30):
    pb.button_press(btn)
    pb.tick()
    pb.button_release(btn)
    for _ in range(wait):
        pb.tick()

def hold(pb, btn, frames):
    pb.button_press(btn)
    for _ in range(frames):
        pb.tick()
    pb.button_release(btn)

def new_game(pb, seed=None):
    mem = pb.memory
    press(pb, "start", 10)          # title -> editor
    if seed is not None:
        for i in range(8):
            mem[syms["wSeedNib"] + i] = (seed >> (28 - 4 * i)) & 15
    press(pb, "a", 60)              # editor -> new game
    assert mem[syms["wState"]] == 2, "not sailing after new game"
    for _ in range(30):
        pb.tick()

def wait_state(pb, state, frames=180):
    """Tick until wState == state (screen rebuilds take several frames)."""
    mem = pb.memory
    for _ in range(frames):
        pb.tick()
        if mem[syms["wState"]] == state:
            return True
    return False


def press3(pb, btn):
    """Hold a button for 3 frames. A 1-tick press can land between the
    game's joypad reads (PyBoy writes hit mid-frame) and vanish."""
    pb.button_press(btn)
    for _ in range(3):
        pb.tick()
    pb.button_release(btn)


def teleport(pb, tx, ty, tries=8):
    """Teleport to a tile, surviving torn mid-frame position writes (the
    collision check can revert a torn write). Returns success."""
    mem = pb.memory
    for _ in range(tries):
        set16(mem, "wPosX", (tx * 8) << 4)
        set16(mem, "wPosY", (ty * 8) << 4)
        pb.tick()
        if (w16(mem, "wShipX") >> 3, w16(mem, "wShipY") >> 3) == (tx, ty):
            return True
    return False


def district_has_land(dx, dy, s16):
    """Mirror of port.asm DistrictHasLand: 4 sampled tiles per district."""
    for ox, oy in ((1, 1), (2, 1), (1, 2), (2, 2)):
        if tile(dx * 4 + ox, dy * 4 + oy, s16) >= 3:
            return True
    return False


def w16(mem, n):
    return mem[syms[n]] | mem[syms[n] + 1] << 8

def set16(mem, n, v):
    mem[syms[n]] = v & 0xFF
    mem[syms[n] + 1] = v >> 8

def seed16(mem):
    return (mem[syms["wSeed16"]] << 8) | mem[syms["wSeed16"] + 1]

def vram_tile(mem, wx, wy):
    return mem[0x9800 + ((wy & 31) * 32) + (wx & 31)]

def read_text(mem, addr, n):
    out = ""
    for i in range(n):
        t = mem[addr + i]
        if t in (0, 39):
            out += " "
        elif 16 <= t <= 25:
            out += str(t - 16)
        elif 40 <= t <= 65:
            out += chr(ord('A') + t - 40)
        elif t == 38:
            out += ":"
        elif t == 66:
            out += "/"
    return out

def find_water(s16, x0, x1, y0, y1, pred=None):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if tile(x, y, s16) < 3 and (pred is None or pred(x, y)):
                return (x, y)
    return None

# ---------------------------------------------------------------- R1: drag

def r1_drag_symmetry():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    x0, y0 = w16(mem, "wShipX"), w16(mem, "wShipY")
    hold(pb, "left", 60)
    hold(pb, "up", 60)
    for _ in range(120):
        pb.tick()
    x1, y1 = w16(mem, "wShipX"), w16(mem, "wShipY")
    assert x1 < x0 - 20, f"west thrust moved {x0} -> {x1}"
    assert y1 < y0 - 20, f"north thrust moved {y0} -> {y1}"
    pb.stop()
    print("R1 drag symmetry: OK")

# ------------------------------------------------- R2/R3: storms and wrecks

def r2_r3_storm_collision_and_clear():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    # open water with a coast to the east (DEADBEEF: continent from tile ~35)
    spot = find_water(s16, 20, 30, 140, 148,
                      lambda x, y: tile(x + 8, y, s16) >= 3)
    assert spot, "no test spot found"
    set16(mem, "wPosX", (spot[0] * 8) << 4)
    set16(mem, "wPosY", (spot[1] * 8) << 4)
    set16(mem, "wStormT", 480)
    mem[syms["wStormDX"]] = 16       # blow east into the coast
    mem[syms["wStormDY"]] = 0
    for _ in range(600):
        pb.tick()
    tx = w16(mem, "wShipX") >> 3
    assert tx < 40, f"storm pushed ship through land to tile {tx}"
    # R3: a long storm must be cleared by the wreck it causes
    set16(mem, "wStormT", 2000)
    mem[syms["wStormDX"]] = 16
    mem[syms["wHull"]] = 1
    for _ in range(1200):
        pb.tick()
        if mem[syms["wHull"]] == 10:     # wrecked and patched
            break
    assert mem[syms["wHull"]] == 10, "never wrecked"
    assert w16(mem, "wStormT") == 0, f"storm survived wreck ({w16(mem, 'wStormT')})"
    pb.stop()
    print("R2/R3 storm collision + storm cleared on wreck: OK")

# --------------------------------- R4/R5: streaming correctness vs reference

def stream_window_check(pb, tag):
    mem = pb.memory
    s16 = seed16(mem)
    # let the camera settle, then compare the whole window to the reference
    for _ in range(90):
        pb.tick()
    tx0, ty0 = w16(mem, "wTileX"), w16(mem, "wTileY")
    mism = []
    for j in range(18):
        for i in range(20):
            got = vram_tile(mem, tx0 + i, ty0 + j)
            want = shown_tile(tx0 + i, ty0 + j, s16)
            if got != want:
                mism.append((tx0 + i, ty0 + j, got, want))
    assert not mism, f"{tag}: {len(mism)} tile mismatches, e.g. {mism[:4]}"

def r4_southern_sea():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    # teleport into the southern sea (rows >= 256), refill via chart toggle,
    # then scroll west so entering columns are written by GenColStage
    spot = find_water(s16, 15, 30, 258, 268)
    assert spot, "no southern water found"
    set16(mem, "wPosX", (spot[0] * 8) << 4)
    set16(mem, "wPosY", (spot[1] * 8) << 4)
    for _ in range(5):
        pb.tick()
    press(pb, "start", 5)            # chart open
    press(pb, "a", 5)                # chart close -> full refill
    hold(pb, "left", 90)             # scroll west: column stages in rows >= 256
    hold(pb, "right", 90)            # and back east
    stream_window_check(pb, "southern sea")
    pb.stop()
    print("R4 southern sea streaming: OK")

def r5_diagonal_blit():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    # diagonal sail down the continent shore: many same-frame X+Y tile
    # crossings with terrain that actually varies between rows
    set16(mem, "wPosX", (20 * 8) << 4)
    set16(mem, "wPosY", (140 * 8) << 4)
    for _ in range(90):
        pb.tick()
    press(pb, "start", 5)            # chart toggle: full clean refill first
    press(pb, "a", 5)
    pb.button_press("down")
    pb.button_press("right")
    for _ in range(300):
        pb.tick()
    pb.button_release("down")
    pb.button_release("right")
    stream_window_check(pb, "diagonal scroll")
    pb.stop()
    print("R5 diagonal column blits: OK")

# ---------------------------------------------------------------- R6: spawn

def r6_spawn_in_ocean():
    pb = boot()
    mem = pb.memory
    new_game(pb, seed=0xFFFFFFFF)
    # puddle-spawn seed: must land in the main ocean (validated reachability)
    sx, sy = w16(mem, "wPosX") >> 7, w16(mem, "wPosY") >> 7
    assert (sx, sy) == (280, 144), f"spawn ({sx},{sy}), want (280,144)"
    pb.stop()
    pb = boot()
    mem = pb.memory
    new_game(pb, seed=0xDEADBEEF)
    sx, sy = w16(mem, "wPosX") >> 7, w16(mem, "wPosY") >> 7
    assert (sx, sy) == (8, 144), f"spawn ({sx},{sy}), want (8,144)"
    pb.stop()
    print("R6 open-ocean spawn: OK")

# ------------------------------------------------------------- R7: LOS gave-up

def r7_los_despawn():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    # find player/enemy water tiles <= 14 tiles apart with land at all three
    # quarter-sample points (mirrors HasLOS's sampling)
    pair = None
    for ay in range(130, 170):
        for ax in range(4, 60):
            if tile(ax, ay, s16) >= 3:
                continue
            for bx in range(ax + 2, min(ax + 14, 60)):
                for by in range(ay - 14, ay + 15):
                    if tile(bx, by, s16) >= 3:
                        continue
                    dx, dy = bx - ax, by - ay
                    pts = [((ax + ((dx >> 2) * i)), (ay + ((dy >> 2) * i)))
                           for i in (1, 2, 3)]
                    if all(tile(px, py, s16) >= 3 for px, py in pts):
                        pair = ((ax, ay), (bx, by))
                        break
                if pair:
                    break
            if pair:
                break
        if pair:
            break
    assert pair, "no LOS-blocked pair found"
    (ax, ay), (bx, by) = pair
    set16(mem, "wPosX", (ax * 8) << 4)
    set16(mem, "wPosY", (ay * 8) << 4)
    for _ in range(5):
        pb.tick()
    set16(mem, "wEnemyX", (bx * 8) << 4)
    set16(mem, "wEnemyY", (by * 8) << 4)
    mem[syms["wEnemyHP"]] = 3
    mem[syms["wEnemyFireCool"]] = 75
    mem[syms["wIsGuardian"]] = 0
    mem[syms["wLosT"]] = 16
    mem[syms["wNoLOS"]] = 0
    mem[syms["wEnemyActive"]] = 1
    for _ in range(1500):
        pb.tick()
        if not mem[syms["wEnemyActive"]]:
            break
    assert not mem[syms["wEnemyActive"]], "sightless enemy never gave up"
    pb.stop()
    print("R7 line-of-sight despawn: OK")

# --------------------------------------- R8: final battle wave handed back

def r8_final_wave_returned():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    spot = find_water(s16, 45, 70, 140, 150,
                      lambda x, y: tile(x + 12, y, s16) < 3
                      and tile(x - 12, y, s16) < 3 and tile(x, y + 12, s16) < 3)
    assert spot, "no open-water spot"
    set16(mem, "wPosX", (spot[0] * 8) << 4)
    set16(mem, "wPosY", (spot[1] * 8) << 4)
    for _ in range(60):                  # let the teleport settle
        if w16(mem, "wShipX") == spot[0] * 8 and w16(mem, "wShipY") == spot[1] * 8:
            break
        pb.tick()
    mem[syms["wFinal"]] = 1
    # Each cycle: a wave guardian spawns; pushing it >120 px away forces a
    # despawn. With the fix the wave is handed back and the next guardian
    # always spawns; without it wFinal sticks at 3 and the third wave
    # never comes.
    for cycle in range(3):
        spawned = False
        for _ in range(900):
            pb.tick()
            if mem[syms["wEnemyActive"]] and mem[syms["wIsGuardian"]]:
                spawned = True
                break
        assert spawned, f"final wave never respawned (cycle {cycle})"
        ex = w16(mem, "wEnemyX")
        set16(mem, "wEnemyX", min(ex + (260 << 4), 40000))
        for _ in range(90):              # despawn (+ maybe instant respawn)
            pb.tick()
            if not mem[syms["wEnemyActive"]]:
                break
        assert not mem[syms["wEnemyActive"]], "guardian never despawned"
    pb.stop()
    print("R8 final-battle wave handed back on despawn: OK")

# ------------------------------------------------------ R9/R10: tavern rumors

def find_dockable_port(s16):
    """A port district with a beach the game will actually accept: some
    water tile whose FIRST land neighbor in TryDock's N,S,W,E order is a
    beach inside this district. Seed-independent (unlike the old
    hardcoded (10,34), which is not a port district under DEADBEEF)."""
    for dy in range(72):
        for dx in range(80):
            if not has_port(dx, dy, s16):
                continue
            for ty in range(dy * 4, dy * 4 + 4):
                for tx in range(dx * 4, dx * 4 + 4):
                    if tile(tx, ty, s16) < 3:
                        continue
                    for ddx, ddy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                        nx, ny = tx + ddx, ty + ddy
                        if not (0 <= nx < 320 and 0 <= ny < 288):
                            continue
                        if tile(nx, ny, s16) >= 3:
                            continue
                        for pdx, pdy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                            if not (0 <= nx + pdx < 320 and 0 <= ny + pdy < 288):
                                continue
                            if tile(nx + pdx, ny + pdy, s16) >= 3:
                                if (nx + pdx, ny + pdy) == (tx, ty):
                                    return (dx, dy)
                                break
    raise AssertionError("no dockable port district in this sea")


def dock_at_district(pb, s16, dx, dy):
    """Teleport next to a beach in port district (dx,dy) and dock."""
    mem = pb.memory
    for ty in range(dy * 4, dy * 4 + 4):
        for tx in range(dx * 4, dx * 4 + 4):
            if tile(tx, ty, s16) < 3:
                continue
            for ddx, ddy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                nx, ny = tx + ddx, ty + ddy
                if not (0 <= nx < 320 and 0 <= ny < 288):
                    continue
                if tile(nx, ny, s16) >= 3:
                    continue
                # retrying teleport: a one-shot write can be torn mid-frame
                # and the collision check reverts it (surfaced when MainLoop
                # timing shifted)
                if not teleport(pb, nx, ny):
                    continue
                for _ in range(5):
                    pb.tick()
                # a 1-tick press can land between joypad reads: hold for 3
                pb.button_press("a")
                for _ in range(3):
                    pb.tick()
                pb.button_release("a")
                for _ in range(30):
                    pb.tick()
                if mem[syms["wState"]] == 4:
                    return
    raise AssertionError(f"no dockable beach in district ({dx},{dy})")

def r9_r10_tavern():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    dock_at_district(pb, s16, *find_dockable_port(s16))
    press(pb, "down", 2)
    press(pb, "down", 2)
    press(pb, "a", 30)                       # TAVERN
    isle_line = read_text(mem, 0x9800 + 11 * 32 + 1, 16).strip()
    days_line = read_text(mem, 0x9800 + 12 * 32 + 1, 10).strip()
    # reference: nearest unclaimed isle from the ship's cell
    isles = [(mem[syms["wIsles"] + 2 * k], mem[syms["wIsles"] + 2 * k + 1])
             for k in range(9)]
    scx, scy = mem[syms["wShipCX"]], mem[syms["wShipCY"]]
    dist, k, ddx, ddy = min(
        (max(abs(ix - scx), abs(iy - scy)), k, ix - scx, iy - scy)
        for k, (ix, iy) in enumerate(isles))
    want_days = f"{dist:02d} DAYS {DIRS[snap_dir(ddx, ddy)]}"
    assert isle_line.startswith(ISLE_NAMES[k]), \
        f"isle name {isle_line!r}, want {ISLE_NAMES[k]}"
    assert days_line == want_days, f"isle days {days_line!r}, want {want_days!r}"
    press(pb, "b", 5)
    press(pb, "b", 30)                       # set sail
    # R10: a port with no other port within 12 districts still prints the isle
    lonely = None
    for dy in range(72):
        for dx in range(80):
            if not has_port(dx, dy, s16):
                continue
            has_beach = any(tile(tx, ty, s16) >= 3 and tile(tx, ty + 1, s16) < 3
                            for ty in range(dy * 4, dy * 4 + 4)
                            for tx in range(dx * 4, dx * 4 + 4))
            if not has_beach:
                continue
            found = False
            for r in range(1, 13):
                for ddx in range(-r, r + 1):
                    for ddy in range(-r, r + 1):
                        if max(abs(ddx), abs(ddy)) != r:
                            continue
                        cx2, cy2 = dx + ddx, dy + ddy
                        if 0 <= cx2 < 80 and 0 <= cy2 < 72 \
                                and has_port(cx2, cy2, s16):
                            found = True
            if not found:
                lonely = (dx, dy)
                break
        if lonely:
            break
    if lonely is None:
        print("R9 tavern rumor values: OK; R10 skipped (no lonely port)")
        pb.stop()
        return
    dock_at_district(pb, s16, *lonely)
    press(pb, "down", 2)
    press(pb, "down", 2)
    press(pb, "a", 30)
    isle_line = read_text(mem, 0x9800 + 11 * 32 + 1, 16).strip()
    assert any(n in isle_line for n in ISLE_NAMES), \
        f"lonely port printed no isle rumor: {isle_line!r}"
    pb.stop()
    print("R9 tavern rumor values: OK; R10 rumor without nearby port: OK")

# ------------------------------------------- R11/R12: port menu wrap, gold cap

def r11_r12_menu_and_gold():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    dock_at_district(pb, s16, *find_dockable_port(s16))
    press(pb, "up", 5)
    assert mem[syms["wPortMenu"]] == 6, \
        f"UP from top item -> {mem[syms['wPortMenu']]}, want 6 (SET SAIL)"
    set16(mem, "wGold", 30000)
    mem[syms["wPortDirty"]] = 1
    for _ in range(30):
        pb.tick()
    digits = [mem[0x9800 + 3 * 32 + 8 + i] for i in range(4)]
    assert digits == [25, 25, 25, 25], f"gold digits {digits}, want 9999"
    pb.stop()
    print("R11 menu wrap: OK; R12 gold clamp: OK")

# ------------------------------------------------------- R13: boot RAM clear

def r13_boot_clears_state():
    pb = boot(garbage=True)
    mem = pb.memory
    assert w16(mem, "wStormT") == 0, "phantom storm: wStormT not cleared"
    assert not mem[syms["wEnemyActive"]], "phantom enemy not cleared"
    assert not mem[syms["wBallPActive"]], "phantom player ball not cleared"
    assert not mem[syms["wBallEActive"]], "phantom enemy ball not cleared"
    new_game(pb)
    p0 = (w16(mem, "wShipX"), w16(mem, "wShipY"))
    for _ in range(120):
        pb.tick()
    p1 = (w16(mem, "wShipX"), w16(mem, "wShipY"))
    assert p0 == p1, f"ship drifted on its own: {p0} -> {p1}"
    pb.stop()
    print("R13 boot clears volatile state: OK")

# --------------------------------- R14: dig does not fire the cannons

def r14_dig_no_cannon():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    # isle 0's cell: find a water tile with a land neighbor (a diggable beach)
    ix, iy = mem[syms["wIsles"]], mem[syms["wIsles"] + 1]
    spot = None
    for ty in range(iy * 18, iy * 18 + 18):
        for tx in range(ix * 20, ix * 20 + 20):
            if tile(tx, ty, s16) >= 3:
                continue
            if any(tile(tx + ddx, ty + ddy, s16) >= 3
                   for ddx, ddy in ((0, 1), (0, -1), (1, 0), (-1, 0))):
                spot = (tx, ty)
                break
        if spot:
            break
    assert spot, "no beach-adjacent water in isle 0's cell"
    assert teleport(pb, *spot), "teleport never stuck"
    for _ in range(4):
        pb.tick()
    assert (mem[syms["wShipCX"]], mem[syms["wShipCY"]]) == (ix, iy)
    mem[syms["wGuardMask"]] = 1          # isle 0's guardian already sunk
    press3(pb, "a")                      # dig up the fragment
    for _ in range(30):
        pb.tick()
    assert mem[syms["wState"]] == 5, f"state {mem[syms['wState']]}, want DIG"
    assert not mem[syms["wBallPActive"]], "digging fired a cannonball"
    pb.stop()
    print("R14 dig does not fire cannons: OK")

# ---------------------- R15: SaveGame sets wHasSave (continue without reset)

def r15_save_sets_has_save():
    pb = boot()                       # save-free boot (see boot())
    mem = pb.memory
    assert mem[syms["wHasSave"]] == 0, "fresh cart reported a save"
    new_game(pb)
    s16 = seed16(mem)
    dock_at_district(pb, s16, *find_dockable_port(s16))  # autosaves on dock
    assert mem[syms["wHasSave"]] == 1, "wHasSave not set after autosave"
    press3(pb, "b")                      # set sail
    assert wait_state(pb, 2), "never set sail"
    press3(pb, "b")                       # arm quit confirm
    for _ in range(5):                    # B must be seen released...
        pb.tick()
    press3(pb, "b")                       # ...before the confirming edge
    assert wait_state(pb, 0), "did not return to the editor"
    hint = read_text(mem, 0x9800 + 5 * 32 + 5, 11)
    assert hint == "A  NEW GAME", f"editor hint {hint!r}, want 'A  NEW GAME'"
    pb.stop()
    print("R15 SaveGame sets wHasSave + editor LOAD hint: OK")

# --------------------------------- R16: boot clears fire cooldowns

def r16_boot_clears_fire_cooldowns():
    pb = boot(garbage=True)
    mem = pb.memory
    assert mem[syms["wFireCool"]] == 0, "wFireCool not cleared at boot"
    assert mem[syms["wEnemyFireCool"]] == 0, "wEnemyFireCool not cleared at boot"
    pb.stop()
    print("R16 boot clears fire cooldowns: OK")

# --------------------------------- F1: B-at-sea quit confirm

def f1_quit_confirm():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    press3(pb, "b")
    for _ in range(5):
        pb.tick()
    assert mem[syms["wState"]] == 2, "single B press quit without confirm"
    assert mem[syms["wQuitCfm"]] > 0, "confirm window not armed"
    for _ in range(200):                  # let the window expire
        pb.tick()
    assert mem[syms["wQuitCfm"]] == 0, "confirm window never expired"
    assert mem[syms["wState"]] == 2, "expired confirm still quit"
    press3(pb, "b")                       # re-arm
    for _ in range(5):
        pb.tick()
    assert mem[syms["wQuitCfm"]] > 0, "confirm window not re-armed"
    press3(pb, "b")                       # confirm
    assert wait_state(pb, 0), "second B press did not quit"
    pb.stop()
    print("F1 B-at-sea quit confirm: OK")

# --------------------------------- F2: storm drift range

def f2_storm_drift_range():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    isles = {(mem[syms["wIsles"] + 2 * k], mem[syms["wIsles"] + 2 * k + 1])
             for k in range(9)}
    samples = []
    for cy in range(16):
        for cx in range(16):
            if (cx, cy) in isles:
                continue                  # isle cells roll no encounters
            h = mix16(((cx * 73 + cy * 41) & 0xFFFF) ^ s16 ^ 0xC37A)
            if (h >> 8) >= 13 or (h & 0xFF) < 48:
                continue                  # want storm-only cells (no pirate)
            wx, wy = cx * 20 + 10, cy * 18 + 9
            if tile(wx, wy, s16) >= 3:
                continue                  # ship must stay in water
            set16(mem, "wStormT", 0)      # clear the last sample's storm before
            mem[syms["wEnemyActive"]] = 0  # hopping: its drift breaks the
            mem[syms["wMerchActive"]] = 0  # teleport's exact-tile check
            if not teleport(pb, wx, wy):
                continue
            if mem[syms["wState"]] == 8:      # a merchant hailed mid-teleport:
                press3(pb, "a")               # resolve the offer (buy or bust)
                for _ in range(10):
                    pb.tick()
                press3(pb, "a")               # leave the result screen
                for _ in range(10):
                    pb.tick()
            # The teleport's own ticks may roll an encounter at a torn
            # intermediate position, so re-roll cleanly at the settled
            # target: clear explored/storm/enemy, invalidate the
            # MarkExplored tile cache, and wait for the cell to re-mark
            # (writes can land after a frame's logic: tick until it takes).
            for i in range(32):
                mem[syms["wExplored"] + i] = 0
            set16(mem, "wStormT", 0)
            mem[syms["wEnemyActive"]] = 0
            mem[syms["wMerchActive"]] = 0  # a merchant suppresses all rolls
            set16(mem, "wMarkTX", 0xFFFF)
            mem[syms["wShipCX"]] = 0xFF     # force a cell re-entry: the tile
            mem[syms["wShipCY"]] = 0xFF     # cache alone only re-derives tiles
            bit = (cy * 16 + cx) % 8
            for _ in range(4):
                pb.tick()
                if mem[syms["wExplored"] + (cy * 16 + cx) // 8] >> bit & 1:
                    break
            if w16(mem, "wStormT") > 0:
                dx = mem[syms["wStormDX"]]
                dy = mem[syms["wStormDY"]]
                samples.append((dx - 256 if dx > 127 else dx,
                                dy - 256 if dy > 127 else dy))
    assert len(samples) >= 5, f"only {len(samples)} storm cells found"
    biggest = max(max(abs(dx), abs(dy)) for dx, dy in samples)
    assert biggest > 16, \
        f"storm drift never exceeded 16 over {len(samples)} storms (old range)"
    pb.stop()
    print(f"F2 storm drift range: OK ({len(samples)} storms, max {biggest})")

# -------------------- R17: tavern nearest-port scan covers whole rings

def r17_tavern_port_scan():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    ports = [(dx, dy) for dy in range(72) for dx in range(80)
             if has_port(dx, dy, s16) and district_has_land(dx, dy, s16)]
    pset = set(ports)
    # scenario: a port whose nearest fellow port is 2+ rings out and alone
    # on its ring (prefer a SW bearing: DIRS[5] was mislabeled S)
    cands = []
    for p in ports:
        for r in range(1, 13):
            ring = [(p[0] + dx, p[1] + dy)
                    for dx in range(-r, r + 1) for dy in range(-r, r + 1)
                    if max(abs(dx), abs(dy)) == r
                    and (p[0] + dx, p[1] + dy) in pset]
            if ring:
                if r >= 2 and len(ring) == 1:
                    d = snap_dir(ring[0][0] - p[0], ring[0][1] - p[1])
                    cands.append((d != 5, p, r, DIRS[d]))
                break
    cands.sort()
    sailed = False
    for _, (dx, dy), r, dname in cands:
        try:
            dock_at_district(pb, s16, dx, dy)
        except AssertionError:
            continue
        if mem[syms["wPortDX"]] == dx and mem[syms["wPortDY"]] == dy:
            sailed = True
            break
        press(pb, "b", 30)               # wrong district: set sail, try next
    if not sailed:
        pb.stop()
        print("R17 skipped (no ring>=2 port scenario in this sea)")
        return
    press(pb, "down", 2)
    press(pb, "down", 2)
    press(pb, "a", 30)                       # TAVERN
    days = read_text(mem, 0x9800 + 9 * 32 + 1, 2)
    bearing = read_text(mem, 0x9800 + 9 * 32 + 9, 2).strip()
    pb.stop()
    assert days == f"{r:02d}" and bearing == dname, \
        f"tavern says '{days} {bearing}', want '{r:02d} {dname}'"
    print(f"R17 tavern port scan ({days} DAYS {bearing}): OK")

# ----------------- R18: wreck respawn fully redraws the visible window

def r18_wreck_respawn_redraw():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    # hull 1, full speed east into the coast: one ram wrecks. The respawn
    # teleports the ship to open ocean; the redraw must fill the window for
    # the NEW camera, not the stale pre-wreck one (else stale land strips
    # persist in open ocean: CheckStream only patches one edge per frame).
    spot = find_water(s16, 20, 40, 138, 146,
                      lambda x, y: tile(x + 4, y, s16) >= 3)
    assert spot, "no ramming spot found"
    set16(mem, "wPosX", (spot[0] * 8) << 4)
    set16(mem, "wPosY", (spot[1] * 8) << 4)
    for _ in range(5):
        pb.tick()
    mem[syms["wHull"]] = 1
    mem[syms["wVelX"]] = 40
    for _ in range(600):
        pb.tick()
        if mem[syms["wHull"]] == 10:     # wrecked and patched
            break
    assert mem[syms["wHull"]] == 10, "never wrecked"
    for _ in range(140):                 # 90f message + respawn redraw
        pb.tick()
    tx0, ty0 = w16(mem, "wTileX"), w16(mem, "wTileY")
    mism = []
    for j in range(19):
        for i in range(21):
            got = vram_tile(mem, tx0 + i, ty0 + j)
            want = shown_tile(tx0 + i, ty0 + j, s16)
            if got != want:
                mism.append((tx0 + i, ty0 + j, got, want))
    assert not mism, f"post-wreck window: {len(mism)} stale tiles, e.g. {mism[:4]}"
    assert mem[syms["wVelX"]] == 0 and mem[syms["wVelY"]] == 0, \
        "wreck respawn kept pre-wreck momentum"
    pb.stop()
    print("R18 wreck respawn redraws the visible window: OK")

# ----------------- R19: CGB streaming never drops VRAM writes

def r19_cgb_streaming_no_drops():
    """VBlank overruns used to clip the staged blits (tile AND attr passes):
    writes landing in Mode 3 are dropped, leaving stale tiles/palettes that
    only healed when the area happened to be re-streamed. The blits now
    poll STAT before each write, so overruns stretch harmlessly. Sail short
    legs with full settles (lag-robust): every settled window must match
    the reference exactly, tiles and CGB palette attrs."""
    import shutil, tempfile
    path = str(Path(tempfile.mkdtemp()) / "pf.gb")
    shutil.copy(ROM, path)
    pb = PyBoy(path, window="null", cgb=True)
    pb.set_emulation_speed(0)
    mem = pb.memory
    for _ in range(150):
        pb.tick()
    press(pb, "start", 10)
    press(pb, "a", 60)
    s16 = seed16(mem)

    def want_attr(t):                    # mirrors world.asm TileAttr
        if t in (0, 13):
            return 0
        if t in (14, 3):
            return 2
        return 1 if t < 3 else 3

    def check_window(tag):
        tx0, ty0 = w16(mem, "wTileX"), w16(mem, "wTileY")
        bad = []
        for j in range(19):
            base = 0x9800 + ((ty0 + j) & 31) * 32
            for i in range(21):
                addr = base + ((tx0 + i) & 31)
                mem[0xFF4F] = 0
                gt = mem[addr]
                mem[0xFF4F] = 1
                ga = mem[addr] & 7
                mem[0xFF4F] = 0
                wt = shown_tile(tx0 + i, ty0 + j, s16)
                if gt != wt or ga != want_attr(wt):
                    bad.append((tx0 + i, ty0 + j, gt, ga, wt, want_attr(wt)))
        assert not bad, f"{tag}: {len(bad)} dropped/mismatched tiles, e.g. {bad[:4]}"

    legs = [("up", 60), ("right", 60), ("up", 60), ("left", 60),
            ("down", 60), ("right", 60), ("down", 60), ("left", 60),
            ("up", 60), ("right", 60)]
    for k, (btn, n) in enumerate(legs):
        hold(pb, btn, n)
        for _ in range(45):              # settle: all lag/blits catch up
            pb.tick()
        check_window(f"leg {k} {btn}")
    for k in range(3):                   # diagonal stress: col+row same VBlank
        pb.button_press("down")
        pb.button_press("right")
        for _ in range(60):
            pb.tick()
        pb.button_release("down")
        pb.button_release("right")
        for _ in range(45):
            pb.tick()
        check_window(f"diag leg {k}")
    pb.stop()
    print("R19 CGB streaming drops no writes: OK")

# --------------------------------- F3: HUD stats line at sea

def f3_hud_stats_line():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    mem[syms["wHull"]] = 17
    set16(mem, "wGold", 1234)
    mem[syms["wFragMask"]] = 0b101
    mem[syms["wFragMask"] + 1] = 0
    for _ in range(3):
        pb.tick()
    line = read_text(mem, 0x9C00 + 32, 15)
    assert line == "H17 G1234 F2/9 ", f"HUD row 1 {line!r}"
    pb.stop()
    print("F3 HUD hull/gold/fragments line: OK")

# ----------------- R20: crew speeds the cannon reload

def r20_crew_speeds_reload():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    mem[syms["wCrew"]] = 20
    pb.button_press("a")
    fired = False
    for _ in range(5):                   # a press can land between joypad reads
        pb.tick()
        if mem[syms["wBallPActive"]]:
            fired = True
            break
    pb.button_release("a")
    assert fired, "cannon didn't fire"
    # 30 - 20/2 = 20, minus the same-frame cooldown tick in UpdateCombat
    assert mem[syms["wFireCool"]] == 19, \
        f"cooldown {mem[syms['wFireCool']]}, want 19 (30 - crew/2 - tick)"
    for _ in range(60):
        pb.tick()                        # ball expires, cooldown drains
    mem[syms["wCrew"]] = 0
    pb.button_press("a")
    fired = False
    for _ in range(5):
        pb.tick()
        if mem[syms["wBallPActive"]]:
            fired = True
            break
    pb.button_release("a")
    assert fired, "second shot didn't fire"
    assert mem[syms["wFireCool"]] == 29, \
        f"cooldown {mem[syms['wFireCool']]}, want 29 (no crew)"
    pb.stop()
    print("R20 crew speeds cannon reload: OK")

# ----------------- R21: the final fleet escalates per wave

def r21_final_fleet_escalates():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    spot = find_water(s16, 45, 70, 140, 150,
                      lambda x, y: tile(x + 12, y, s16) < 3
                      and tile(x - 12, y, s16) < 3
                      and tile(x, y + 12, s16) < 3
                      and tile(x, y - 12, s16) < 3)
    assert spot, "no open-water spot"
    assert teleport(pb, *spot), "teleport never stuck"
    mem[syms["wEnemyActive"]] = 0        # the teleport may have rolled a pirate
    mem[syms["wBallEActive"]] = 0
    set16(mem, "wStormT", 0)
    mem[syms["wFinal"]] = 1
    for _ in range(300):
        pb.tick()
        if mem[syms["wEnemyActive"]] and mem[syms["wIsGuardian"]]:
            break
    assert mem[syms["wEnemyActive"]], "final wave 1 never spawned"
    assert mem[syms["wEnemyHP"]] == 6, \
        f"wave 1 HP {mem[syms['wEnemyHP']]}, want 6 (GUARD_HP + 1)"
    cool = mem[syms["wEnemyFireCool"]]
    assert 40 <= cool <= 42, f"wave 1 cooldown {cool}, want ~42 (50 - 8)"
    pb.stop()
    print("R21 final fleet escalates per wave: OK")

# ----------------- R22: a won voyage is tagged on the seed screen

def r22_treasure_won_tag():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    mem[syms["wWon"]] = 1
    mem[syms["wHasSave"]] = 1
    press3(pb, "b")                        # arm quit confirm
    for _ in range(5):
        pb.tick()
    press3(pb, "b")                        # confirm
    assert wait_state(pb, 0), "did not return to the editor"
    line = read_text(mem, 0x9800 + 7 * 32 + 5, 12)
    assert line == "TREASURE WON", f"won tag {line!r}"
    assert mem[0x9800 + 7 * 32 + 17] == 67, "missing '!'"
    pb.stop()
    print("R22 seed screen TREASURE WON tag: OK")

# ----------------- R23: the chart shows the voyage seed

def r23_chart_shows_seed():
    pb = boot()
    mem = pb.memory
    new_game(pb)                           # default seed DEADBEEF
    press3(pb, "start")
    assert wait_state(pb, 3), "chart didn't open"
    row = [mem[0x9800 + 17 * 32 + 4 + i] for i in range(13)]
    want = [58, 44, 44, 43, 39, 29, 30, 26, 29, 27, 30, 30, 31]  # SEED DEADBEEF
    assert row == want, f"chart seed row {row}, want {want}"
    pb.stop()
    print("R23 chart shows the voyage seed: OK")

# ----------------- R24/R25: charted-cell revisit rolls + fragment scaling

# xorshift16 mirror of rng.asm Rand16 (triplet 7,9,8)
def xs16(x):
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF

# revisit-roll outcomes are driven by wRngState, so pick states with known
# results. SpawnEnemy then draws the offset from the NEXT Rand16: forbid
# west offsets (2, 6) — water west of the spawn point is unvalidated.
def _spawn_state():
    def good(s):
        r1 = xs16(s)
        if (r1 & 0xFF) >= 12 or (r1 >> 8) < 3:   # must roll a pirate, no storm
            return False
        return (xs16(r1) & 0xFF) & 7 in (0, 1, 3, 4, 5, 7)
    return next(s for s in range(1, 0x10000) if good(s))

# l in [32,48): above the merchant lane (12..31) — nothing spawns on a
# revisit, though a new-cell roll (<48) would have
_NO_ROLL = next(s for s in range(1, 0x10000)
                if 32 <= (xs16(s) & 0xFF) < 48 and (xs16(s) >> 8) >= 3)
_SPAWN = _spawn_state()

def _roll_state(lane_lo, lane_hi):
    """wRngState whose revisit roll lands in [lane_lo, lane_hi) (no storm),
    with a safe (non-west) spawn offset draw."""
    for s in range(1, 0x10000):
        r1 = xs16(s)
        if not (lane_lo <= (r1 & 0xFF) < lane_hi) or (r1 >> 8) < 3:
            continue
        if (xs16(r1) & 0xFF) & 7 in (2, 6):   # PickSpawnSpot's offset draw
            continue
        return s
    raise AssertionError("no such rng state")

_MERCH = _roll_state(12, 32)             # merchant lane

# wRngState is stored h-first (hl big-endian: rng.asm loads h from the
# first byte), so set16 would write the state byte-swapped.
def _set_rng(mem, s):
    mem[syms["wRngState"]] = s >> 8
    mem[syms["wRngState"] + 1] = s & 0xFF

def _sail_into_marked_cell(rng_state, frags=0, won=0):
    """Spawn cell (cx,cy) is charted by the new-game ticks; pre-chart the
    cell to its east and sail in. Returns (pb, mem) stopped at the crossing."""
    pb = boot()
    mem = pb.memory
    new_game(pb)
    mem[syms["wEnemyActive"]] = 0        # clear the spawn cell's own roll
    set16(mem, "wStormT", 0)
    set16(mem, "wFragMask", frags)
    mem[syms["wWon"]] = won
    cx, cy = mem[syms["wShipCX"]], mem[syms["wShipCY"]]
    isles = {(mem[syms["wIsles"] + 2 * k], mem[syms["wIsles"] + 2 * k + 1])
             for k in range(9)}
    assert (cx + 1, cy) not in isles, "east cell is an isle cell: no rolls there"
    bit = cy * 16 + cx + 1
    mem[syms["wExplored"] + bit // 8] |= 1 << (bit % 8)
    _set_rng(mem, rng_state)
    pb.button_press("right")
    for _ in range(300):
        pb.tick()
        if mem[syms["wShipCX"]] == cx + 1:
            break
    pb.button_release("right")
    for _ in range(5):
        pb.tick()
    assert mem[syms["wShipCX"]] == cx + 1, "never reached the charted cell"
    return pb

def r24_revisit_rolls_reduced():
    pb = _sail_into_marked_cell(_NO_ROLL)
    assert not pb.memory[syms["wEnemyActive"]], \
        "revisit roll spawned at full new-cell odds"
    pb.stop()
    pb = _sail_into_marked_cell(_SPAWN)
    assert pb.memory[syms["wEnemyActive"]] == 1, \
        "revisit roll never spawned at reduced odds"
    pb.stop()
    print("R24 charted-cell revisit rolls at reduced odds: OK")

def r25_pirates_scale_with_fragments():
    pb = _sail_into_marked_cell(_SPAWN, frags=0)
    assert pb.memory[syms["wEnemyHP"]] == 3, \
        f"0-fragment HP {pb.memory[syms['wEnemyHP']]}, want 3"
    assert 60 <= pb.memory[syms["wEnemyFireCool"]] <= 75, \
        f"0-fragment cooldown {pb.memory[syms['wEnemyFireCool']]}, want ~75"
    pb.stop()
    pb = _sail_into_marked_cell(_SPAWN, frags=0b111)   # 3 fragments
    assert pb.memory[syms["wEnemyHP"]] == 4, \
        f"3-fragment HP {pb.memory[syms['wEnemyHP']]}, want 4"
    assert 45 <= pb.memory[syms["wEnemyFireCool"]] <= 60, \
        f"3-fragment cooldown {pb.memory[syms['wEnemyFireCool']]}, want ~60"
    pb.stop()
    print("R25 pirates scale with fragments held: OK")

# ----------------- R26: best-haul record persists across saves

def r26_best_haul_record():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    set16(mem, "wGold", 7000)
    dock_at_district(pb, s16, *find_dockable_port(s16))   # autosaves on dock
    assert w16(mem, "wBestGold") == 7000, \
        f"best {w16(mem, 'wBestGold')}, want 7000"
    set16(mem, "wGold", 10)
    press3(pb, "b")                                        # set sail (saves)
    assert wait_state(pb, 2), "never set sail"
    assert w16(mem, "wBestGold") == 7000, "best haul dropped on a poorer save"
    press3(pb, "b")                                        # quit to editor
    for _ in range(5):
        pb.tick()
    press3(pb, "b")
    assert wait_state(pb, 0), "did not return to the editor"
    line = read_text(mem, 0x9800 + 8 * 32 + 5, 11)
    assert line == "BEST 7000 G", f"best line {line!r}"
    pb.stop()
    print("R26 best-haul record + seed screen display: OK")

# ----------------- R27: full chart pays the cartographer's bounty, once

def r27_chart_completion_bounty():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    mem[syms["wEnemyActive"]] = 0
    set16(mem, "wStormT", 0)
    for i in range(32):
        mem[syms["wExplored"] + i] = 0xFF
    gold0 = w16(mem, "wGold")
    press3(pb, "start")
    assert wait_state(pb, 3), "chart didn't open"
    assert w16(mem, "wGold") == gold0 + 500, \
        f"gold {w16(mem, 'wGold')}, want {gold0 + 500}"
    assert mem[syms["wCartDone"]] == 1, "bounty flag not set"
    assert read_text(mem, 0x9800, 14) == "CHART COMPLETE", \
        f"row 0 {read_text(mem, 0x9800, 20)!r}"
    assert mem[0x9800 + 14] == 67, "missing '!'"
    assert read_text(mem, 0x9800 + 15, 5) == " 500G"
    press3(pb, "b")                        # back to sailing
    assert wait_state(pb, 2)
    press3(pb, "start")                    # reopen: no double award
    assert wait_state(pb, 3)
    assert w16(mem, "wGold") == gold0 + 500, "bounty awarded twice"
    pb.stop()
    print("R27 chart completion bounty (once): OK")

# ----------------- R28: chart marks dug isles with X

def r28_chart_marks_dug_isles():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    ix, iy = mem[syms["wIsles"]], mem[syms["wIsles"] + 1]   # isle 0's cell
    bit = iy * 16 + ix
    mem[syms["wExplored"] + bit // 8] |= 1 << (bit % 8)
    set16(mem, "wFragMask", 1)                             # isle 0 dug
    press3(pb, "start")
    assert wait_state(pb, 3), "chart didn't open"
    t = mem[0x9800 + (iy + 1) * 32 + (ix + 2)]
    assert t == 32, f"isle chart tile {t}, want X (TILE_LET_X = 32)"
    pb.stop()
    print("R28 chart marks dug isles with X: OK")

# ----------------- R29/R30: merchant trade and plunder

def _hail_merchant(pb, mem, rng=None):
    """Teleport onto a water tile 16 px from the active merchant and wait
    for the auto-hail (< 20 px). rng seeds the deal/rob rolls: it is written
    AFTER the teleport's own cell roll, so nothing consumes it first."""
    s16 = seed16(mem)
    mxp, myp = w16(mem, "wMerchX") >> 4, w16(mem, "wMerchY") >> 4
    for dx, dy in ((-16, 0), (16, 0), (0, -16), (0, 16)):
        if tile((mxp + dx) // 8, (myp + dy) // 8, s16) < 3:
            set16(mem, "wPosX", (mxp + dx) << 4)
            set16(mem, "wPosY", (myp + dy) << 4)
            break
    else:
        raise AssertionError("no water next to the merchant")
    mem[syms["wEnemyActive"]] = 0        # the teleport's own cell roll
    set16(mem, "wStormT", 0)
    if rng is not None:
        _set_rng(mem, rng)
    for _ in range(30):
        pb.tick()
        if mem[syms["wState"]] == 8:
            return
    raise AssertionError("merchant never hailed")

# rob outcome is the roll after the deal roll: odd high byte = escort
_ROB_ESCORT = next(s for s in range(1, 0x10000) if (xs16(xs16(s)) >> 8) & 1)

def r29_merchant_trade():
    pb = _sail_into_marked_cell(_MERCH)
    mem = pb.memory
    assert mem[syms["wMerchActive"]] == 1, "merchant never spawned"
    _hail_merchant(pb, mem)
    good = mem[syms["wMerchGood"]]
    qty = mem[syms["wMerchQty"]]
    price = mem[syms["wMerchPrice"]]
    assert 3 <= qty <= 6 and price in (2, 5, 7, 12), \
        f"deal {qty}x good{good} @ {price}"
    set16(mem, "wGold", 200)
    press3(pb, "a")                      # buy the lot
    for _ in range(10):                  # result screen renders over ~3 frames
        pb.tick()
    assert mem[syms["wMerchPhase"]] == 2, "no result screen"
    assert w16(mem, "wGold") == 200 - qty * price, "wrong price charged"
    assert mem[syms["wCargo"] + good] == qty, "goods not delivered"
    press3(pb, "a")                      # leave the result screen
    assert wait_state(pb, 2), "never back to sailing"
    assert not mem[syms["wMerchActive"]], "merchant not consumed"
    pb.stop()
    print("R29 merchant hail + trade: OK")

def r30_merchant_rob_escort():
    pb = _sail_into_marked_cell(_MERCH)
    mem = pb.memory
    assert mem[syms["wMerchActive"]] == 1, "merchant never spawned"
    _hail_merchant(pb, mem, rng=_ROB_ESCORT)
    set16(mem, "wGold", 100)
    press3(pb, "b")                      # rob the dog
    for _ in range(10):
        pb.tick()
    assert mem[syms["wMerchPhase"]] == 2, "no result screen"
    g = w16(mem, "wGold")
    assert 130 <= g <= 161, f"robbery paid {g - 100}"
    assert read_text(mem, 0x9800 + 4 * 32, 19) == "HIS ESCORT SAILS IN"
    assert mem[0x9800 + 4 * 32 + 19] == 67, "missing '!'"
    press3(pb, "a")
    assert wait_state(pb, 2), "never back to sailing"
    # the escort spawn retries until its pick finds water
    for _ in range(600):
        pb.tick()
        if mem[syms["wEnemyActive"]]:
            break
    assert mem[syms["wEnemyActive"]] == 1, "escort never sailed in"
    assert not mem[syms["wIsGuardian"]], "escort should be a plain pirate"
    pb.stop()
    print("R30 merchant robbery + escort revenge: OK")

# ----------------- R31: market prices drift between visits

def r31_price_drift():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    dock_at_district(pb, s16, *find_dockable_port(s16))
    press3(pb, "a")                      # TRADE (main menu item 0)
    for _ in range(30):
        pb.tick()
    prices = set()
    for drift in range(8):
        mem[syms["wPriceDrift"]] = drift
        mem[syms["wPortDirty"]] = 1
        for _ in range(20):
            pb.tick()
        d = [mem[0x9800 + 6 * 32 + 9 + i] - 16 for i in range(3)]
        assert all(0 <= x <= 9 for x in d), \
            f"price column not rendered: {d} (latent de-clobber bug)"
        prices.add(d[0] * 100 + d[1] * 10 + d[2])
    assert len(prices) >= 2, f"prices never drift: {prices}"
    pb.stop()
    print(f"R31 market prices drift between visits: OK ({sorted(prices)})")

# ----------------- R32: the dig is a ceremony, skippable

def r32_dig_ceremony():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    ix, iy = mem[syms["wIsles"]], mem[syms["wIsles"] + 1]
    spot = None
    for ty in range(iy * 18, iy * 18 + 18):
        for tx in range(ix * 20, ix * 20 + 20):
            if tile(tx, ty, s16) >= 3:
                continue
            if any(tile(tx + ddx, ty + ddy, s16) >= 3
                   for ddx, ddy in ((0, 1), (0, -1), (1, 0), (-1, 0))):
                spot = (tx, ty)
                break
        if spot:
            break
    assert spot, "no beach-adjacent water in isle 0's cell"
    mem[syms["wGuardMask"]] = 1          # guardian pre-sunk: no spawn race
    assert teleport(pb, *spot), "teleport never stuck"
    press3(pb, "a")
    for _ in range(10):
        pb.tick()
    assert mem[syms["wState"]] == 5, "dig didn't open"
    assert mem[syms["wDigT"]] > 0, "no dig ceremony"
    assert read_text(mem, 0x9800 + 4 * 32 + 2, 16) == "X MARKS THE SPOT"
    press3(pb, "a")                       # skip to the reveal
    for _ in range(10):                   # reveal screen renders over ~3 frames
        pb.tick()
    assert mem[syms["wDigT"]] == 0, "ceremony didn't skip"
    assert read_text(mem, 0x9800 + 4 * 32 + 5, 11) == "YOU FOUND A"
    press3(pb, "a")                       # back to sea
    assert wait_state(pb, 2), "never back to sailing"
    pb.stop()
    print("R32 dig ceremony (knock, skip, reveal): OK")

# ----------------- R33: SELECT mutes anywhere; re-rolls in the editor

def r33_select_mute_and_reroll():
    pb = boot()
    mem = pb.memory
    press3(pb, "select")                 # title screen: mute on
    for _ in range(5):
        pb.tick()
    assert mem[syms["wMuted"]] == 1, "SELECT didn't mute at the title"
    press3(pb, "select")
    for _ in range(5):
        pb.tick()
    assert mem[syms["wMuted"]] == 0, "SELECT didn't unmute"
    new_game(pb)
    press3(pb, "select")                 # at sea: mute cuts the channels
    for _ in range(5):
        pb.tick()
    assert mem[syms["wMuted"]] == 1, "SELECT didn't mute at sea"
    assert mem[0xFF12] == 0, "ch1 not silenced on mute"
    press3(pb, "select")
    for _ in range(5):
        pb.tick()
    assert mem[syms["wMuted"]] == 0, "SELECT didn't unmute at sea"
    press3(pb, "b")                      # quit to the seed editor
    for _ in range(5):
        pb.tick()
    press3(pb, "b")
    assert wait_state(pb, 0), "did not return to the editor"
    before = [mem[syms["wSeedNib"] + i] for i in range(8)]
    press3(pb, "select")                 # editor: re-roll, not mute
    for _ in range(5):
        pb.tick()
    after = [mem[syms["wSeedNib"] + i] for i in range(8)]
    assert after != before, "SELECT didn't re-roll the seed"
    assert mem[syms["wMuted"]] == 0, "editor SELECT leaked into mute"
    pb.stop()
    print("R33 SELECT mute + seed re-roll: OK")

# ----------------- R34: shipyard upgrades (buy, effect, persist)

def r34_shipyard():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    dock_at_district(pb, s16, *find_dockable_port(s16))
    set16(mem, "wGold", 1000)
    for _ in range(4):
        press3(pb, "down")               # TRADE,REPAIR,TAVERN,RECRUIT -> SHIPYARD
        for _ in range(3):
            pb.tick()
    press3(pb, "a")
    for _ in range(10):
        pb.tick()
    assert mem[syms["wPortState"]] == 6, "shipyard didn't open"
    hull0 = mem[syms["wHull"]]            # may have taken a bump while docking
    press3(pb, "a")                       # plating tier 1
    for _ in range(10):
        pb.tick()
    assert mem[syms["wHullMax"]] == 25 and mem[syms["wHull"]] == hull0 + 5, \
        f"plating: max {mem[syms['wHullMax']]} hull {mem[syms['wHull']]}"
    assert w16(mem, "wGold") == 900, f"gold {w16(mem, 'wGold')}, want 900"
    press3(pb, "a")                       # plating tier 2
    for _ in range(10):
        pb.tick()
    assert mem[syms["wHullMax"]] == 30 and w16(mem, "wGold") == 650
    press3(pb, "a")                       # maxed: no sale
    for _ in range(10):
        pb.tick()
    assert w16(mem, "wGold") == 650, "charged for a maxed upgrade"
    press3(pb, "down")                    # SAILS
    for _ in range(3):
        pb.tick()
    press3(pb, "a")
    for _ in range(10):
        pb.tick()
    assert mem[syms["wMaxVel"]] == 48 and w16(mem, "wGold") == 450
    press3(pb, "down")                    # LONG GUNS
    for _ in range(3):
        pb.tick()
    press3(pb, "a")
    for _ in range(10):
        pb.tick()
    assert mem[syms["wBallLife"]] == 56 and w16(mem, "wGold") == 250
    press3(pb, "b")                       # back to main menu
    for _ in range(10):
        pb.tick()
    press3(pb, "b")                       # set sail (autosaves the upgrades)
    assert wait_state(pb, 2), "never set sail"
    # sails: velocity cap is 48 now — a 22-tile runway and per-frame sampling
    # (a 90-frame hold outruns any small patch of guaranteed water)
    spot = find_water(s16, 40, 90, 130, 160,
                      lambda x, y: all(tile(x + k, y, s16) < 3
                                       for k in range(-2, 23)))
    assert spot, "no long water runway"
    assert teleport(pb, *spot)
    vmax = 0
    pb.button_press("right")
    for _ in range(70):
        pb.tick()
        v = mem[syms["wVelX"]]
        if v < 128:
            vmax = max(vmax, v)
    pb.button_release("right")
    assert vmax == 48, f"top speed {vmax}, want 48"
    # long guns: ball lives 56 frames (minus the same-frame tick)
    press3(pb, "a")
    assert mem[syms["wBallPActive"]] == 1, "cannon didn't fire"
    assert mem[syms["wBallPLife"]] in (54, 55, 56), \
        f"ball life {mem[syms['wBallPLife']]}, want ~56"
    # upgrades persist through the save
    press3(pb, "b")                       # quit confirm
    for _ in range(5):
        pb.tick()
    press3(pb, "b")
    assert wait_state(pb, 0), "did not return to the editor"
    press3(pb, "start")                   # continue the saved voyage
    assert wait_state(pb, 2), "continue failed"
    assert mem[syms["wHullMax"]] == 30 and mem[syms["wMaxVel"]] == 48 \
        and mem[syms["wBallLife"]] == 56, "upgrades didn't persist"
    pb.stop()
    print("R34 shipyard upgrades (buy, effect, persist): OK")

# ----------------- R35: a won sea stays wild

def r35_revenge_seas():
    # _NO_ROLL rolls l in [32,48): nothing pre-victory (R24), a pirate after
    pb = _sail_into_marked_cell(_NO_ROLL, won=1)
    assert pb.memory[syms["wEnemyActive"]] == 1, \
        "won sea didn't keep charted waters dangerous"
    pb.stop()
    print("R35 revenge seas after victory: OK")

# ----------------- R36: the kraken rises in deep water

# revisit roll with l >= 32 (no pirate/merchant) and h in {3,4} (kraken
# lane = the 2 values above the storm lane), non-west spawn offset
_KRAKEN = next(s for s in range(1, 0x10000)
               if (xs16(s) & 0xFF) >= 32 and (xs16(s) >> 8) in (3, 4)
               and (xs16(xs16(s)) & 0xFF) & 7 in (0, 1, 3, 4, 5, 7))

def r36_kraken():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    mem[syms["wEnemyActive"]] = 0
    set16(mem, "wStormT", 0)
    isles = {(mem[syms["wIsles"] + 2 * k], mem[syms["wIsles"] + 2 * k + 1])
             for k in range(9)}
    # a cell-boundary tile that is DEEP water, approached from water
    spot = None
    for cy in range(1, 15):
        for cx in range(1, 15):
            if (cx, cy) in isles:
                continue
            wx, wy = cx * 20, cy * 18 + 9
            if tile(wx, wy, s16) == 1 and tile(wx - 1, wy, s16) < 3:
                spot = (cx, cy, wx, wy)
                break
        if spot:
            break
    assert spot, "no deep-water cell boundary found"
    cx, cy, wx, wy = spot
    assert teleport(pb, wx - 4, wy), "teleport never stuck"
    bit = cy * 16 + cx
    mem[syms["wExplored"] + bit // 8] |= 1 << (bit % 8)   # revisited cell
    _set_rng(mem, _KRAKEN)
    pb.button_press("right")
    for _ in range(300):
        pb.tick()
        if mem[syms["wShipCX"]] == cx:
            break
    pb.button_release("right")
    for _ in range(10):
        pb.tick()
    assert mem[syms["wEnemyActive"]] == 1, "kraken never surfaced"
    assert mem[syms["wEnemyHP"]] == 8, f"HP {mem[syms['wEnemyHP']]}, want 8"
    loot = mem[syms["wEnemyLoot"]]
    assert 60 <= loot <= 123, f"hoard {loot}, want 60..123"
    pb.stop()
    print("R36 the kraken rises in deep water: OK")

# ----------------- R37: chart marks a guarded isle with a skull

def r37_chart_skull():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    ix, iy = mem[syms["wIsles"]], mem[syms["wIsles"] + 1]
    bit = iy * 16 + ix
    mem[syms["wExplored"] + bit // 8] |= 1 << (bit % 8)
    press3(pb, "start")
    assert wait_state(pb, 3), "chart didn't open"
    addr = 0x9800 + (iy + 1) * 32 + (ix + 2)
    assert mem[addr] == 68, f"guarded isle tile {mem[addr]}, want skull (68)"
    set16(mem, "wGuardMask", 1)           # guardian sunk, fragment not dug
    press3(pb, "b")
    assert wait_state(pb, 2)
    press3(pb, "start")
    assert wait_state(pb, 3)
    assert mem[addr] not in (32, 68), \
        f"cleared isle tile {mem[addr]}, want plain terrain"
    pb.stop()
    print("R37 chart skull for guarded isles: OK")

# ----------------- R38: a corrupt save slot falls back to the other

def r38_second_save_slot():
    import shutil
    import tempfile
    path = str(Path(tempfile.mkdtemp()) / "pf.gb")
    shutil.copy(ROM, path)
    pb = PyBoy(path, window="null")
    pb.set_emulation_speed(0)
    mem = pb.memory
    for _ in range(150):
        pb.tick()
    new_game(pb)
    s16 = seed16(mem)
    set16(mem, "wGold", 1111)
    dock_at_district(pb, s16, *find_dockable_port(s16))  # save 1 -> slot 0
    press3(pb, "b")                                       # set sail -> slot 1
    assert wait_state(pb, 2)
    set16(mem, "wGold", 2222)
    press3(pb, "a")                                       # re-dock -> slot 0
    for _ in range(40):
        pb.tick()
    assert mem[syms["wState"]] == 4, "re-dock failed"
    pb.stop()                             # writes <rom>.ram (32 KiB SRAM)
    ram = bytearray(open(path + ".ram", "rb").read())
    ram[0x10] ^= 0xFF                     # corrupt slot 0's data (the newer)
    open(path + ".ram", "wb").write(ram)
    pb2 = PyBoy(path, window="null")
    pb2.set_emulation_speed(0)
    mem2 = pb2.memory
    for _ in range(150):
        pb2.tick()
    assert mem2[syms["wHasSave"]] == 1, "no valid save found"
    got = mem2[syms["wGold"]] | mem2[syms["wGold"] + 1] << 8
    assert got == 1111, f"loaded gold {got}, want 1111 (slot 1 fallback)"
    pb2.stop()
    print("R38 corrupt save slot falls back to the other: OK")

# ----------------- R39: merchants despawn on range and on time

def r39_merchant_despawn():
    pb = _sail_into_marked_cell(_MERCH)
    mem = pb.memory
    assert mem[syms["wMerchActive"]] == 1, "merchant never spawned"
    # range: leave her behind (no-storm destination: drift breaks the hop)
    s16 = seed16(mem)
    far = find_water(s16, 150, 250, 40, 120,
                     lambda x, y: (mix16((((x // 20) * 73 + (y // 18) * 41)
                                          & 0xFFFF) ^ s16 ^ 0xC37A) >> 8) >= 13)
    assert far, "no calm far water found"
    mem[syms["wVelX"]] = 0
    mem[syms["wVelY"]] = 0
    set16(mem, "wStormT", 0)
    assert teleport(pb, *far)
    for _ in range(10):
        pb.tick()
    assert not mem[syms["wMerchActive"]], "merchant never left behind"
    # time: park one nearby with 30 frames on the clock
    set16(mem, "wMerchX", (w16(mem, "wShipX") + 100) << 4)
    set16(mem, "wMerchY", w16(mem, "wShipY") << 4)
    mem[syms["wMerchHailed"]] = 1
    set16(mem, "wMerchT", 30)
    mem[syms["wMerchActive"]] = 1
    for _ in range(40):
        pb.tick()
    assert not mem[syms["wMerchActive"]], "merchant never timed out"
    pb.stop()
    print("R39 merchant despawn (range + timer): OK")

# ----------------- R40: robbing a merchant with no escort

# rob outcome = the roll after the deal roll; even high byte = no escort
_ROB_CLEAN = next(s for s in range(1, 0x10000)
                  if not ((xs16(xs16(s)) >> 8) & 1))

def r40_clean_rob():
    pb = _sail_into_marked_cell(_MERCH)
    mem = pb.memory
    assert mem[syms["wMerchActive"]] == 1, "merchant never spawned"
    _hail_merchant(pb, mem, rng=_ROB_CLEAN)
    set16(mem, "wGold", 100)
    press3(pb, "b")                      # rob the dog
    for _ in range(10):
        pb.tick()
    assert mem[syms["wMerchPhase"]] == 2, "no result screen"
    g = w16(mem, "wGold")
    assert 130 <= g <= 161, f"robbery paid {g - 100}"
    assert read_text(mem, 0x9800 + 4 * 32, 16) == "NO QUARTER GIVEN"
    press3(pb, "a")
    assert wait_state(pb, 2), "never back to sailing"
    for _ in range(120):
        pb.tick()
    assert not mem[syms["wEnemyActive"]], "clean robbery spawned an escort"
    assert not mem[syms["wEscortPend"]], "phantom escort pending"
    pb.stop()
    print("R40 clean robbery (no escort branch): OK")

# ----------------- R41: a merchant parley delays the guardian

def r41_merchant_delays_guardian():
    pb = boot()
    mem = pb.memory
    new_game(pb)
    s16 = seed16(mem)
    ix, iy = mem[syms["wIsles"]], mem[syms["wIsles"] + 1]
    spot = None
    for ty in range(iy * 18, iy * 18 + 18):
        for tx in range(ix * 20, ix * 20 + 20):
            if tile(tx, ty, s16) < 3:
                spot = (tx, ty)
                break
        if spot:
            break
    assert spot, "no water in isle 0's cell"
    assert teleport(pb, *spot)
    mem[syms["wEnemyActive"]] = 0        # the teleport tick's guardian
    # park a merchant in range: parley active, hail already done
    set16(mem, "wMerchX", (w16(mem, "wShipX") + 100) << 4)
    set16(mem, "wMerchY", w16(mem, "wShipY") << 4)
    mem[syms["wMerchHailed"]] = 1
    set16(mem, "wMerchT", 500)
    mem[syms["wMerchActive"]] = 1
    for _ in range(120):
        pb.tick()
    assert not mem[syms["wEnemyActive"]], \
        "guardian crashed a merchant parley"
    mem[syms["wMerchActive"]] = 0        # parley over: the guardian comes
    for _ in range(900):
        pb.tick()
        if mem[syms["wEnemyActive"]]:
            break
    assert mem[syms["wEnemyActive"]] and mem[syms["wIsGuardian"]], \
        "guardian never spawned after the merchant left"
    pb.stop()
    print("R41 merchant parley delays the guardian: OK")

if __name__ == "__main__":
    for fn in (r1_drag_symmetry, r2_r3_storm_collision_and_clear, r4_southern_sea,
               r5_diagonal_blit, r6_spawn_in_ocean, r7_los_despawn,
               r8_final_wave_returned, r9_r10_tavern, r11_r12_menu_and_gold,
               r13_boot_clears_state, r14_dig_no_cannon, r15_save_sets_has_save,
               r16_boot_clears_fire_cooldowns, r17_tavern_port_scan,
               r18_wreck_respawn_redraw, r19_cgb_streaming_no_drops,
               r20_crew_speeds_reload, r21_final_fleet_escalates,
               r22_treasure_won_tag, r23_chart_shows_seed,
               r24_revisit_rolls_reduced, r25_pirates_scale_with_fragments,
               r26_best_haul_record, r27_chart_completion_bounty,
               r28_chart_marks_dug_isles,
               r29_merchant_trade, r30_merchant_rob_escort,
               r31_price_drift, r32_dig_ceremony,
               r33_select_mute_and_reroll,
               r34_shipyard, r35_revenge_seas,
               r36_kraken, r37_chart_skull, r38_second_save_slot,
               r39_merchant_despawn, r40_clean_rob,
               r41_merchant_delays_guardian,
               f1_quit_confirm,
               f2_storm_drift_range, f3_hud_stats_line):
        fn()
    print("ALL REGRESSION CHECKS PASSED")

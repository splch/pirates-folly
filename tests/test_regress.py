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
                set16(mem, "wPosX", (nx * 8) << 4)
                set16(mem, "wPosY", (ny * 8) << 4)
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
    assert mem[syms["wPortMenu"]] == 5, \
        f"UP from top item -> {mem[syms['wPortMenu']]}, want 5"
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
            if not teleport(pb, wx, wy):
                continue
            # The teleport's own ticks may roll an encounter at a torn
            # intermediate position, so re-roll cleanly at the settled
            # target: clear explored/storm/enemy, invalidate the
            # MarkExplored tile cache, and wait for the cell to re-mark
            # (writes can land after a frame's logic: tick until it takes).
            for i in range(32):
                mem[syms["wExplored"] + i] = 0
            set16(mem, "wStormT", 0)
            mem[syms["wEnemyActive"]] = 0
            set16(mem, "wMarkTX", 0xFFFF)
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

if __name__ == "__main__":
    for fn in (r1_drag_symmetry, r2_r3_storm_collision_and_clear, r4_southern_sea,
               r5_diagonal_blit, r6_spawn_in_ocean, r7_los_despawn,
               r8_final_wave_returned, r9_r10_tavern, r11_r12_menu_and_gold,
               r13_boot_clears_state, r14_dig_no_cannon, r15_save_sets_has_save,
               r16_boot_clears_fire_cooldowns, r17_tavern_port_scan,
               f1_quit_confirm,
               f2_storm_drift_range, f3_hud_stats_line):
        fn()
    print("ALL REGRESSION CHECKS PASSED")

"""Shore mode (S0): dinghy purchase, going ashore, walking, reboarding,
and the sea/shore silhouette guarantee. Run after the build.

The Python shore model mirrors src/shore.asm: shore tile (sx, sy) samples
the ocean's elevation function with 4-bit fractions, so the shoreline is
exactly the sea chart's landmass at 2x zoom.
"""
import shutil
import tempfile
from pathlib import Path

from pyboy import PyBoy

ROOT = Path(__file__).resolve().parents[1]
ROM = str(ROOT / "pirates_folly.gb")
SYM = str(ROOT / "build" / "pirates_folly.sym")

syms = {}
for line in open(SYM):
    p = line.split()
    if len(p) == 2:
        syms[p[1]] = int(p[0].split(":")[1], 16)

# ---------------------------------------------------------------- reference
# Python port of the worldgen (mirrors src/world.asm / shore.asm).

def mix16(x):
    x &= 0xFFFF
    x ^= x >> 8; x ^= (x << 7) & 0xFFFF; x ^= x >> 9; x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF

def lathash(ix, iy, s16):
    return mix16(((ix * 97 + iy * 61) & 0xFFFF) ^ s16) & 0xFF

def _mulmag(m, f): return (m * f) >> 3
def _lerp(base, other, f):
    d = other - base
    return base + (_mulmag(d, f) if d >= 0 else -_mulmag(-d, f))
def elevation(wx, wy, s16):
    ix, iy = wx >> 3, wy >> 3
    fx, fy = wx & 7, wy & 7
    h00 = lathash(ix, iy, s16); h10 = lathash(ix + 1, iy, s16)
    h01 = lathash(ix, iy + 1, s16); h11 = lathash(ix + 1, iy + 1, s16)
    return _lerp(_lerp(h00, h10, fx), _lerp(h01, h11, fx), fy)
def tile(wx, wy, s16):
    return 1 if elevation(wx, wy, s16) < 132 else \
           2 if elevation(wx, wy, s16) < 148 else \
           3 if elevation(wx, wy, s16) < 158 else 4

def _mulmag16(m, f): return (m * f) >> 4
def _lerp16(base, other, f):
    d = other - base
    return base + (_mulmag16(d, f) if d >= 0 else -_mulmag16(-d, f))
def shore_elevation(sx, sy, s16):
    ix, iy = sx >> 4, sy >> 4
    fx, fy = sx & 15, sy & 15
    h00 = lathash(ix, iy, s16); h10 = lathash(ix + 1, iy, s16)
    h01 = lathash(ix, iy + 1, s16); h11 = lathash(ix + 1, iy + 1, s16)
    return _lerp16(_lerp16(h00, h10, fx), _lerp16(h01, h11, fx), fy)
def shore_detail(sx, sy, s16):
    return mix16(((31 * sx + 63 * sy) & 0xFFFF) ^ s16) & 15
def shore_tile(sx, sy, s16):
    e = shore_elevation(sx, sy, s16)
    if e < 132: return 1     # TILE_DEEP
    if e < 148: return 2     # TILE_SHALLOW
    if e < 158: return 3     # TILE_SAND
    d = shore_detail(sx, sy, s16)
    if e < 205:
        if d == 0: return 98   # lone tree
        if d < 2: return 100   # flowers
        if d < 4: return 97    # tufts
        return 96              # grass
    if d == 0: return 101      # mountain
    if d < 3: return 99        # rock
    return 98                  # tree
def shore_walkable(t):
    return t in (3, 96, 97, 100)

def district_hash(dx, dy, s16):
    return mix16(((dx * 37 + dy * 91) & 0xFFFF) ^ s16 ^ 0x7E55)
def has_port(dx, dy, s16):
    return (district_hash(dx, dy, s16) & 0x3F) < 12
def enc_hash(cx, cy, s16):
    return mix16(((cx * 73 + cy * 41) & 0xFFFF) ^ s16 ^ 0xC37A)

def find_landing(s16, tx, ty):
    """Mirror of shore.asm TryLand: ship at water tile (tx,ty); scan the
    N/S/W/E neighbor ocean tiles for land, then the 4 sub-tiles in order;
    also mirrors TryDock's precedence: the first land neighbor must not be
    a port district (that would dock instead). Returns (sx, sy) or None."""
    if tile(tx, ty, s16) >= 3:
        return None
    for ntx, nty in ((tx, ty - 1), (tx, ty + 1), (tx - 1, ty), (tx + 1, ty)):
        if not (0 <= ntx < 320 and 0 <= nty < 288):
            continue
        if tile(ntx, nty, s16) < 3:
            continue
        if has_port(ntx >> 2, nty >> 2, s16):
            return None            # TryDock would win the A press
        for k in range(4):
            sx, sy = 2 * ntx + (k & 1), 2 * nty + (k >> 1)
            if shore_walkable(shore_tile(sx, sy, s16)):
                return (sx, sy)
        return None                # land but no walkable sub-tile
    return None

# ---------------------------------------------------------------- helpers
RUN = str(Path(tempfile.mkdtemp()) / "pf.gb")
shutil.copy(ROM, RUN)   # shared path: part 2 reloads THIS copy's save

def boot(path):
    pb = PyBoy(path, window="null")
    pb.set_emulation_speed(0)
    for _ in range(150):
        pb.tick()
    return pb

def press(pb, btn, wait=30):
    pb.button_press(btn)
    pb.tick()
    pb.button_release(btn)
    for _ in range(wait):
        pb.tick()

def press3(pb, btn):
    pb.button_press(btn)
    for _ in range(3):
        pb.tick()
    pb.button_release(btn)

def hold(pb, btn, frames):
    pb.button_press(btn)
    for _ in range(frames):
        pb.tick()
    pb.button_release(btn)

def new_game(pb):
    press(pb, "start", 10)
    press(pb, "a", 60)
    mem = pb.memory
    assert mem[syms["wState"]] == 2, "not sailing after new game"
    for _ in range(30):
        pb.tick()

def wait_state(pb, state, frames=180):
    mem = pb.memory
    for _ in range(frames):
        pb.tick()
        if mem[syms["wState"]] == state:
            return True
    return False

def w16(mem, n):
    return mem[syms[n]] | mem[syms[n] + 1] << 8

def set16(mem, n, v):
    mem[syms[n]] = v & 0xFF
    mem[syms[n] + 1] = v >> 8

def teleport(pb, tx, ty, tries=8):
    mem = pb.memory
    def calm():
        set16(mem, "wStormT", 0)
        mem[syms["wEnemyActive"]] = 0
        mem[syms["wMerchActive"]] = 0
    for _ in range(tries):
        set16(mem, "wPosX", (tx * 8) << 4)
        pb.tick()
        calm()
        set16(mem, "wPosY", (ty * 8) << 4)
        pb.tick()
        calm()
        if (w16(mem, "wShipX") >> 3, w16(mem, "wShipY") >> 3) == (tx, ty):
            return True
    return False

# ---------------------------------------------------------------- part 0
# The silhouette guarantee: shore elevation at (2wx, 2wy) must equal ocean
# elevation at (wx, wy) — (m*2f)>>4 == (m*f)>>3, exactly.
s16_probe = 0x1234
for wx in (0, 7, 100, 319):
    for wy in (0, 13, 144, 287):
        assert shore_elevation(2 * wx, 2 * wy, s16_probe) == elevation(wx, wy, s16_probe), \
            f"silhouette mismatch at {wx},{wy}"
print("shore elevation is the ocean's at 2x zoom: OK")

# ---------------------------------------------------------------- part 1
pb = boot(RUN)
mem = pb.memory
new_game(pb)
s16 = (mem[syms["wSeed16"]] << 8) | mem[syms["wSeed16"] + 1]
print(f"seed16 {s16:04X}")

# buy the dinghy: dock at DEADBEEF's port (found by test_m3), open the
# shipyard (main menu item 4), buy item 3
set16(mem, "wGold", 9999)
assert teleport(pb, 40, 139), "port teleport failed"
press3(pb, "a")
assert wait_state(pb, 4), "docking failed"
for _ in range(4):
    press3(pb, "down")
    for _ in range(3):
        pb.tick()
press3(pb, "a")
for _ in range(10):
    pb.tick()
assert mem[syms["wPortState"]] == 6, "shipyard didn't open"
for _ in range(3):
    press3(pb, "down")
    for _ in range(3):
        pb.tick()
press3(pb, "a")                          # buy DINGHY (150G)
for _ in range(10):
    pb.tick()
assert mem[syms["wHasDinghy"]] == 1, "no dinghy after purchase"
assert w16(mem, "wGold") == 9849, f"gold {w16(mem, 'wGold')}, want 9849"
print("dinghy purchase: OK")
press3(pb, "b")                          # back to main menu
for _ in range(10):
    pb.tick()
press3(pb, "b")                          # set sail (autosaves the dinghy)
assert wait_state(pb, 2), "never set sail"

# go ashore: find a beach TryDock ignores (non-port), calm cell
beach = None
for ty in range(60, 240):
    for tx in range(20, 300):
        if find_landing(s16, tx, ty) is None:
            continue
        cx, cy = tx // 20, ty // 18
        h = enc_hash(cx, cy, s16)
        if (h >> 8) < 13 or (h & 0xFF) < 48:
            continue                     # storm/pirate cell: skip
        beach = (tx, ty)
        break
    if beach:
        break
assert beach, "no landing beach found"
landing = find_landing(s16, *beach)
assert teleport(pb, *beach), "beach teleport failed"
press3(pb, "a")
assert wait_state(pb, 9), f"never went ashore (state {mem[syms['wState']]})"
want_px = (landing[0] * 8 + 4, landing[1] * 8 + 4)
got_px = (w16(mem, "wShPosX"), w16(mem, "wShPosY"))
assert got_px == want_px, f"landed at {got_px}, want {want_px}"
print(f"went ashore at {beach} -> shore px {got_px}: OK")

# the dinghy waits at the ship's tile center
assert (w16(mem, "wDingX"), w16(mem, "wDingY")) == \
    (beach[0] * 16 + 8, beach[1] * 16 + 8), "dinghy anchor wrong"

# walking: move in a walkable direction
sx, sy = landing
moved = False
for btn, dx, dy in (("right", 1, 0), ("down", 0, 1), ("left", -1, 0), ("up", 0, -1)):
    if shore_walkable(shore_tile(sx + dx, sy + dy, s16)):
        before = (w16(mem, "wShPosX"), w16(mem, "wShPosY"))
        hold(pb, btn, 30)
        after = (w16(mem, "wShPosX"), w16(mem, "wShPosY"))
        assert after != before, f"walking {btn} didn't move"
        print(f"walking {btn}: {before} -> {after}: OK")
        moved = True
        break
assert moved, "no walkable direction from the landing tile"

# blocked walking: head for water; the player must stay on walkable ground
px, py = w16(mem, "wShPosX"), w16(mem, "wShPosY")
sx, sy = px >> 3, py >> 3
for btn, dx, dy in (("right", 1, 0), ("down", 0, 1), ("left", -1, 0), ("up", 0, -1)):
    if not shore_walkable(shore_tile(sx + dx, sy + dy, s16)):
        hold(pb, btn, 90)
        px, py = w16(mem, "wShPosX"), w16(mem, "wShPosY")
        assert shore_walkable(shore_tile(px >> 3, py >> 3, s16)), \
            f"walked into impassable terrain at {px >> 3},{py >> 3}"
        print(f"blocked by terrain holding {btn}: OK (at {px},{py})")
        break

# reboard: stand on the dinghy, press A
set16(mem, "wShPosX", w16(mem, "wDingX"))
pb.tick()
set16(mem, "wShPosY", w16(mem, "wDingY"))
pb.tick()
press3(pb, "a")
assert wait_state(pb, 2), "reboard failed"
print("reboarded: OK")
pb.stop()

# ---------------------------------------------------------------- part 2
# save v7 round trip: the dinghy persists (autosaved on the set-sail above)
pb2 = boot(RUN)
mem2 = pb2.memory
assert mem2[syms["wHasSave"]] == 1, "no save after reboot"
assert mem2[syms["wHasDinghy"]] == 1, "dinghy didn't persist"
print("dinghy persists through the save (v7): OK")
pb2.stop()
print("ALL SHORE CHECKS PASSED")

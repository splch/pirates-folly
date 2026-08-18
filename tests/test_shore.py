"""Shore mode (S0/S1): dinghy purchase, going ashore, walking, sites,
reboarding, and the sea/shore silhouette guarantee. Run after the build.

The Python shore model mirrors src/shore.asm: shore tile (sx, sy) samples
the ocean's elevation function with 4-bit fractions, so the shoreline is
exactly the sea chart's landmass at 2x zoom.
"""
import shutil
import tempfile
from functools import lru_cache
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
@lru_cache(maxsize=None)
def elevation(wx, wy, s16):
    ix, iy = wx >> 3, wy >> 3
    fx, fy = wx & 7, wy & 7
    h00 = lathash(ix, iy, s16); h10 = lathash(ix + 1, iy, s16)
    h01 = lathash(ix, iy + 1, s16); h11 = lathash(ix + 1, iy + 1, s16)
    return _lerp(_lerp(h00, h10, fx), _lerp(h01, h11, fx), fy)
@lru_cache(maxsize=None)
def tile(wx, wy, s16):
    e = elevation(wx, wy, s16)
    return 1 if e < 132 else 2 if e < 148 else 3 if e < 158 else 4

def _mulmag16(m, f): return (m * f) >> 4
def _lerp16(base, other, f):
    d = other - base
    return base + (_mulmag16(d, f) if d >= 0 else -_mulmag16(-d, f))
@lru_cache(maxsize=None)
def shore_elevation(sx, sy, s16):
    ix, iy = sx >> 4, sy >> 4
    fx, fy = sx & 15, sy & 15
    h00 = lathash(ix, iy, s16); h10 = lathash(ix + 1, iy, s16)
    h01 = lathash(ix, iy + 1, s16); h11 = lathash(ix + 1, iy + 1, s16)
    return _lerp16(_lerp16(h00, h10, fx), _lerp16(h01, h11, fx), fy)
def shore_detail(sx, sy, s16):
    return mix16(((31 * sx + 63 * sy) & 0xFFFF) ^ s16) & 15
@lru_cache(maxsize=None)
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

# --- S1: shore sites (mirror of SiteEval / LandmarkEval in shore.asm) ---
SITE_SALT0, SITE_SALT1, SITE_SALT2, LAND_SALT = 0x3D09, 0xA23E, 0x5A3C, 0x7B1E
DIG_SALT = 0xD1C6
SITE_TRY = ((0, 0), (2, 0), (-2, 0), (0, 2), (0, -2), (2, 2), (-2, -2),
            (2, -2), (-2, 2), (4, 0), (-4, 0), (0, 4), (0, -4))

def dig_site(cx, cy, isle, s16):
    """Mirror of shore.asm DigSitePlace: hash placement, scan fallback,
    then the cell center. Returns (sx, sy) shore tile coords."""
    h1 = mix16(((cy * 16 + cx) * 251 & 0xFFFF) ^ s16 ^ DIG_SALT ^ isle)
    h2 = mix16(h1 ^ SITE_SALT2)
    bx, by = cx * 40 + (h2 & 31), cy * 36 + ((h2 >> 4) & 31)
    for dx, dy in SITE_TRY:
        sx, sy = bx + dx, by + dy
        if sx >= 0 and sy >= 0 and shore_walkable(shore_tile(sx, sy, s16)):
            return (sx, sy)
    for oy in range(36):
        for ox in range(40):
            sx, sy = cx * 40 + ox, cy * 36 + oy
            if shore_walkable(shore_tile(sx, sy, s16)):
                return (sx, sy)
    return (cx * 40 + 20, cy * 36 + 18)

def _site_place(h1, cx, cy, s16):
    h2 = mix16(h1 ^ SITE_SALT2)
    bx, by = cx * 40 + (h2 & 31), cy * 36 + ((h2 >> 4) & 31)
    for dx, dy in SITE_TRY:
        sx, sy = bx + dx, by + dy
        if sx >= 0 and sy >= 0 and shore_walkable(shore_tile(sx, sy, s16)):
            return (sx, sy)
    return None

def site_eval(cx, cy, slot, s16):
    """-> (type, loot, sx, sy) or None. type 1 = chest, 2 = debris."""
    cell = cy * 16 + cx
    h1 = mix16(((cell * 251) & 0xFFFF) ^ s16 ^ (SITE_SALT0 if slot == 0 else SITE_SALT1))
    if (h1 & 7) >= 3:
        return None
    pos = _site_place(h1, cx, cy, s16)
    if pos is None:
        return None
    return ((h1 >> 8 & 1) + 1, h1 >> 8, *pos)

def landmark_eval(cx, cy, s16):
    """-> (type, sx, sy) or None. type 3 = gibbet, 4 = skull pole."""
    cell = cy * 16 + cx
    h1 = mix16(((cell * 251) & 0xFFFF) ^ s16 ^ LAND_SALT)
    if h1 & 31:
        return None
    pos = _site_place(h1, cx, cy, s16)
    if pos is None:
        return None
    return (3 + (h1 >> 8 & 1), *pos)

# --- S3: shore foes (mirror of FoeEval in shore.asm) ---
FOE_SALT0, FOE_SALT1 = 0x6B1D, 0xE492

def foe_eval(cx, cy, slot, s16):
    """-> (type, hp, coin, sx, sy) or None. type 1 = snake, 2 = skeleton."""
    cell = cy * 16 + cx
    h1 = mix16(((cell * 251) & 0xFFFF) ^ s16 ^ (FOE_SALT0 if slot == 0 else FOE_SALT1))
    if (h1 & 7) >= 2:
        return None
    pos = _site_place(h1, cx, cy, s16)
    if pos is None:
        return None
    sx, sy = pos
    if shore_tile(sx, sy, s16) == 3:   # sand -> skeleton
        return (2, 2, 2 + ((h1 >> 8) & 7), sx, sy)
    return (1, 1, 0, sx, sy)           # meadow -> snake

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

def row8_has_text(mem):
    """Is a message/text screen showing? Text tiles (16-67) never overlap
    shore terrain tiles (1-3, 96-101). Scans rows 3-13 (loot/lore messages
    sit at row 8; the dig ceremony at rows 4/6)."""
    return any(16 <= mem[0x9800 + r * 32 + i] <= 67
               for r in range(3, 14) for i in range(20))

def press_a_and_await_text(pb, want_txt=None, tries=6):
    """Press A until the message screen shows (presses can land inside a
    screen rebuild and vanish). Returns True once text is up."""
    mem = pb.memory
    for _ in range(tries):
        press3(pb, "a")
        for _ in range(12):
            pb.tick()
            if row8_has_text(mem):
                if want_txt is None:
                    return True
                got = "".join(chr(t - 40 + ord('A')) if 40 <= t <= 65 else
                              str(t - 16) if 16 <= t <= 25 else " "
                              for r in range(3, 14)
                              for t in (mem[0x9800 + r * 32 + i] for i in range(20)))
                if want_txt.replace(" ", "") in got.replace(" ", ""):
                    return True
    return False

def dismiss_and_wait(pb):
    """Dismiss the message screen, then wait out the rebuild."""
    mem = pb.memory
    for _ in range(6):
        press3(pb, "a")
        for _ in range(4):
            pb.tick()
        if not row8_has_text(mem):
            break
    for _ in range(30):          # the shore rebuild fill spans many frames
        pb.tick()

def clear_foes(mem):
    """Foes interfere with positioning asserts; tests that aren't about
    foes clear them. The refresh re-spawns them when the camera cell
    changes, so clear AFTER any teleport has settled."""
    mem[syms["wFoeList"]] = 0
    mem[syms["wFoeList"] + 8] = 0

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
clear_foes(mem)                     # keep the walking tests bite-free
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

# ---------------------------------------------------------------- S1
# shore sites: chest loot, salvage, landmarks (not consumed), dug bitmap
def go_to(mem, x, y):
    set16(mem, "wShPosX", x)
    pb.tick()
    set16(mem, "wShPosY", y)
    pb.tick()
    for _ in range(5):
        pb.tick()
    clear_foes(mem)

px, py = w16(mem, "wShPosX"), w16(mem, "wShPosY")
ccx, ccy = (px >> 3) // 40, (py >> 3) // 36
ding = (w16(mem, "wDingX"), w16(mem, "wDingY"))
chest = debris = landmark = None
for cy in range(max(0, ccy - 4), 16):
    for cx in range(max(0, ccx - 4), 16):
        for slot in (0, 1):
            s = site_eval(cx, cy, slot, s16)
            if not s:
                continue
            spx = (s[2] * 8 + 4, s[3] * 8 + 4)
            if abs(spx[0] - ding[0]) <= 20 and abs(spx[1] - ding[1]) <= 20:
                continue            # too near the dinghy: A would reboard
            if s[0] == 1 and chest is None:
                chest = (cx, cy, slot, s)
            if s[0] == 2 and debris is None:
                debris = (cx, cy, slot, s)
        lm = landmark_eval(cx, cy, s16)
        if lm:
            lpx = (lm[1] * 8 + 4, lm[2] * 8 + 4)
            if landmark is None and not (abs(lpx[0] - ding[0]) <= 20
                                         and abs(lpx[1] - ding[1]) <= 20):
                landmark = lm
    if chest and debris and landmark:
        break
assert chest, "no chest site found on this sea"
assert debris, "no debris site found on this sea"
assert landmark, "no landmark found on this sea"

# --- chest: dig up gold, dug bit set, sprite hidden ---
ccx, ccy, slot, (typ, loot, sx, sy) = chest
go_to(mem, sx * 8 + 4, sy * 8 + 4)
for _ in range(30):
    pb.tick()                        # let the site list refresh
assert mem[syms["wShadowOAM"] + 8] != 0, "chest sprite not on screen"
gold0 = w16(mem, "wGold")
want = 15 + (loot & 31)
assert press_a_and_await_text(pb, "YE DIG UP"), "chest message never showed"
assert w16(mem, "wGold") == gold0 + want, \
    f"chest gave {w16(mem, 'wGold') - gold0}, want {want}"
dismiss_and_wait(pb)
dug_idx = (ccy * 16 + ccx) * 2 + slot
assert mem[syms["wSiteDug"] + (dug_idx >> 3)] & (1 << (dug_idx & 7)), "no dug bit"
print(f"chest at cell ({ccx},{ccy}) slot {slot}: +{want}G, dug bit set: OK")

# --- debris: salvage cargo ---
cdcx, cdcy, dslot, (dtyp, dloot, dsx, dsy) = debris
go_to(mem, dsx * 8 + 4, dsy * 8 + 4)
for _ in range(30):
    pb.tick()
good = (dloot >> 1) & 3
qty = 3 + ((dloot >> 3) & 3)
cargo0 = mem[syms["wCargo"] + good]
assert press_a_and_await_text(pb, "SALVAGE"), "debris message never showed"
assert mem[syms["wCargo"] + good] == cargo0 + qty, \
    f"salvage gave {mem[syms['wCargo'] + good] - cargo0}, want {qty}"
dismiss_and_wait(pb)
print(f"debris at cell ({cdcx},{cdcy}): +{qty} good {good}: OK")

# --- landmark: lore text, never consumed ---
ltyp, lx, ly = landmark
go_to(mem, lx * 8 + 4, ly * 8 + 4)
for _ in range(30):
    pb.tick()
want_txt = "A GIBBET SWAYS HERE" if ltyp == 3 else "THE DEAD KEEP WATCH"
for attempt in range(2):             # twice: landmarks are not consumed
    assert press_a_and_await_text(pb, want_txt), f"landmark text never showed"
    dismiss_and_wait(pb)
print(f"landmark '{want_txt}' shows twice (not consumed): OK")

# --- S2: the isle dig site (X) appears once the guardian is sunk ---
# use isle 0: read its cell from the game, sink its guardian by fiat
isle0 = (mem[syms["wIsles"]], mem[syms["wIsles"] + 1])
dx_px = dig_site(*isle0, 0, s16)
# the dig works from adjacency; walkability of the site itself is the lint's job
set16(mem, "wGuardMask", 1)          # guardian pre-sunk
go_to(mem, dx_px[0] * 8 + 4, dx_px[1] * 8 + 4)
for _ in range(30):
    pb.tick()                        # site list refresh
assert press_a_and_await_text(pb, "X MARKS THE SPOT"), "no dig scene at the X"
assert mem[syms["wState"]] == 5, "not in the dig scene"
fm0 = w16(mem, "wFragMask")
assert fm0 & 1, "fragment bit not set at dig start"
press3(pb, "a")                      # skip the ceremony to the reveal
for _ in range(15):
    pb.tick()
assert mem[syms["wDigT"]] == 0, "ceremony didn't skip"
press3(pb, "a")                      # leave the dig
for _ in range(60):
    pb.tick()
assert mem[syms["wState"]] == 9, \
    f"dig should return ashore (state {mem[syms['wState']]}, want 9)"
print(f"dig site at {dx_px} (isle 0 cell {isle0}): fragment dug, back ashore: OK")

# --- S3: shore foes — bites, the pistol, coins, collapse ---
# find a spawned foe in a cell near the player's current position
px, py = w16(mem, "wShPosX"), w16(mem, "wShPosY")
ccx, ccy = (px >> 3) // 40, (py >> 3) // 36
foe = None
for cy in range(max(0, ccy - 3), 16):
    for cx in range(max(0, ccx - 3), 16):
        for slot in (0, 1):
            f = foe_eval(cx, cy, slot, s16)
            if f and foe is None:
                foe = f
    if foe:
        break
assert foe, "no shore foe found on this sea"
ftyp, fhp, fcoin, fsx, fsy = foe
print(f"foe found: type {ftyp} at tile ({fsx},{fsy}), coin {fcoin}")

# contact: teleporting onto a foe costs a heart and grants a beat of
# invulnerability (no bite loop)
mem[syms["wShHearts"]] = 3
set16(mem, "wShPosX", fsx * 8 + 4)
pb.tick()
set16(mem, "wShPosY", fsy * 8 + 4)
pb.tick()
for _ in range(40):
    pb.tick()
assert mem[syms["wShHearts"]] == 2, \
    f"foe bite cost {3 - mem[syms['wShHearts']]} hearts, want 1"
assert mem[syms["wShInvT"]] > 0, "no invulnerability after the bite"
print("foe bite: -1 heart, invulnerable after: OK")

# the pistol: weaken the foe, face it, and fire. It dies (and drops its
# coin if it had one).
ent = None
for i in range(2):
    base = syms["wFoeList"] + i * 8
    if mem[base]:
        ent = base
        break
assert ent, "no live foe in the list"
fx = mem[ent + 1] | mem[ent + 2] << 8
fy = mem[ent + 3] | mem[ent + 4] << 8
mem[syms["wShInvT"]] = 90           # don't get bitten mid-test
set16(mem, "wShPosX", fx)
pb.tick()
set16(mem, "wShPosY", fy - 24)
pb.tick()
mem[syms["wShHeading"]] = 2          # face south, down the barrel
mem[ent + 5] = 1                     # weaken to 1 HP
press3(pb, "b")
for _ in range(30):
    pb.tick()
assert mem[ent] == 0, "pistol didn't kill the foe"
print("pistol: ball kills the foe: OK")

# coin drop + pickup (skeletons only; snakes carry nothing)
if ftyp == 2:
    assert mem[syms["wCoinVal"]] != 0, "skeleton dropped no coin"
    val = mem[syms["wCoinVal"]]
    assert val == fcoin, f"coin value {val}, want {fcoin}"
    gold0 = w16(mem, "wGold")
    cx0 = mem[syms["wCoinX"]] | mem[syms["wCoinX"] + 1] << 8
    cy0 = mem[syms["wCoinY"]] | mem[syms["wCoinY"] + 1] << 8
    set16(mem, "wShPosX", cx0)
    pb.tick()
    set16(mem, "wShPosY", cy0)
    pb.tick()
    for _ in range(10):
        pb.tick()
    assert mem[syms["wCoinVal"]] == 0, "coin not collected"
    assert w16(mem, "wGold") == gold0 + val, \
        f"coin gave {w16(mem, 'wGold') - gold0}, want {val}"
    print(f"coin: +{val}G on pickup: OK")
else:
    print("coin: n/a (snake drops nothing)")

# collapse: at 0 hearts the island takes its toll and you wake at the dinghy
foe2 = None
for cy in range(16):
    for cx in range(16):
        for slot in (0, 1):
            f = foe_eval(cx, cy, slot, s16)
            if f and foe2 is None:
                foe2 = f
    if foe2:
        break
assert foe2, "no second foe found"
_, _, _, f2x, f2y = foe2
gold0 = w16(mem, "wGold")
mem[syms["wShInvT"]] = 0
mem[syms["wShHearts"]] = 1
set16(mem, "wShPosX", f2x * 8 + 4)
pb.tick()
set16(mem, "wShPosY", f2y * 8 + 4)
pb.tick()
for _ in range(90):
    pb.tick()                        # bitten to 0 -> collapse message
press3(pb, "a")                      # dismiss "DRAGGED TO THE DINGHY"
for _ in range(30):
    pb.tick()
want_gold = max(0, gold0 - 15)
assert w16(mem, "wGold") == want_gold, \
    f"toll wrong: gold {w16(mem, 'wGold')}, want {want_gold}"
assert mem[syms["wShHearts"]] == 3, "hearts not restored"
assert (w16(mem, "wShPosX"), w16(mem, "wShPosY")) == \
    (w16(mem, "wDingX"), w16(mem, "wDingY")), "didn't wake at the dinghy"
print("collapse: toll paid, wake at the dinghy, hearts restored: OK")

# reboard: stand on the dinghy, press A. A press landing inside a screen
# rebuild vanishes, and one can wake a stale message instead — retry.
set16(mem, "wShPosX", w16(mem, "wDingX"))
pb.tick()
set16(mem, "wShPosY", w16(mem, "wDingY"))
pb.tick()
for _ in range(8):
    press3(pb, "a")
    if wait_state(pb, 2, 60):
        break
    if row8_has_text(mem):
        dismiss_and_wait(pb)
else:
    raise AssertionError("reboard failed")
print("reboarded: OK")

# dock again: autosaves the dug bitmap
assert teleport(pb, 40, 139), "port re-teleport failed"
press3(pb, "a")
assert wait_state(pb, 4), "re-docking failed"
pb.stop()

# ---------------------------------------------------------------- part 2
# save v7 round trip: the dinghy persists (autosaved on the set-sail above)
pb2 = boot(RUN)
mem2 = pb2.memory
assert mem2[syms["wHasSave"]] == 1, "no save after reboot"
assert mem2[syms["wHasDinghy"]] == 1, "dinghy didn't persist"
print("dinghy persists through the save (v8): OK")
assert mem2[syms["wSiteDug"] + (dug_idx >> 3)] & (1 << (dug_idx & 7)), \
    "dug site didn't persist"
print("dug site persists through the save (v8): OK")
pb2.stop()
print("ALL SHORE CHECKS PASSED")

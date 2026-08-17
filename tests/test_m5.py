from pathlib import Path

from pyboy import PyBoy

ROOT = Path(__file__).resolve().parents[1]

ROM = str(ROOT / "pirates_folly.gb")
SYM = str(ROOT / "build" / "pirates_folly.sym")

# Boot a temp copy: PyBoy loads <rom>.ram next to the ROM and writes it on
# stop(), so sharing the repo ROM path leaks saves between test files.
import shutil, tempfile
RUN = str(Path(tempfile.mkdtemp()) / "pf.gb")
shutil.copy(ROM, RUN)

pb = PyBoy(RUN, window="null")
pb.set_emulation_speed(0)

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_regress import teleport  # retrying teleport: single writes can
                                   # tear mid-frame and trip the land revert
syms = {}
for line in open(SYM):
    p = line.split()
    if len(p) == 2:
        syms[p[1]] = int(p[0].split(":")[1], 16)
mem = pb.memory

def w16(n):
    return mem[syms[n]] | mem[syms[n] + 1] << 8

def set16(n, v):
    mem[syms[n]] = v & 0xFF
    mem[syms[n] + 1] = v >> 8

def press(btn, wait=30):
    # hold for 3 ticks: a 1-tick press can land between the game's joypad
    # reads (PyBoy writes hit mid-frame) and vanish
    pb.button_press(btn)
    for _ in range(3):
        pb.tick()
    pb.button_release(btn)
    for _ in range(wait):
        pb.tick()

def mix16(x):
    x &= 0xFFFF
    x ^= x >> 8
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF
SEED = 0x741A
def lathash(ix, iy):
    return mix16(((ix * 97 + iy * 61) & 0xFFFF) ^ SEED) & 0xFF
def mulmag(m, f): return (m * f) >> 3
def lerpu(base, other, f):
    d = other - base
    return base + (mulmag(d, f) if d >= 0 else -mulmag(-d, f))
def elevation(wx, wy):
    ix, iy = wx >> 3, wy >> 3
    fx, fy = wx & 7, wy & 7
    h00 = lathash(ix, iy); h10 = lathash(ix+1, iy); h01 = lathash(ix, iy+1); h11 = lathash(ix+1, iy+1)
    return lerpu(lerpu(h00, h10, fx), lerpu(h01, h11, fx), fy)
def model_tile(wx, wy):
    e = elevation(wx, wy)
    return 1 if e < 132 else (2 if e < 148 else (3 if e < 158 else 4))

# shore model (2x zoom; mirrors src/shore.asm)
def _mulmag16(m, f): return (m * f) >> 4
def _lerp16(base, other, f):
    d = other - base
    return base + (_mulmag16(d, f) if d >= 0 else -_mulmag16(-d, f))
def shore_elevation(sx, sy):
    ix, iy = sx >> 4, sy >> 4
    fx, fy = sx & 15, sy & 15
    h00 = lathash(ix, iy); h10 = lathash(ix+1, iy); h01 = lathash(ix, iy+1); h11 = lathash(ix+1, iy+1)
    return _lerp16(_lerp16(h00, h10, fx), _lerp16(h01, h11, fx), fy)
def shore_detail(sx, sy):
    return mix16(((31 * sx + 63 * sy) & 0xFFFF) ^ SEED) & 15
def shore_tile(sx, sy):
    e = shore_elevation(sx, sy)
    if e < 132: return 1
    if e < 148: return 2
    if e < 158: return 3
    d = shore_detail(sx, sy)
    if e < 205:
        if d == 0: return 98
        if d < 2: return 100
        if d < 4: return 97
        return 96
    if d == 0: return 101
    if d < 3: return 99
    return 98
def shore_walkable(t): return t in (3, 96, 97, 100)
SITE_TRY = ((0, 0), (2, 0), (-2, 0), (0, 2), (0, -2), (2, 2), (-2, -2),
            (2, -2), (-2, 2), (4, 0), (-4, 0), (0, 4), (0, -4))
DIG_SALT = 0xD1C6
def dig_site(cx, cy, isle):
    h1 = mix16(((cy * 16 + cx) * 251 & 0xFFFF) ^ SEED ^ DIG_SALT ^ isle)
    h2 = mix16(h1 ^ 0x5A3C)
    bx, by = cx * 40 + (h2 & 31), cy * 36 + ((h2 >> 4) & 31)
    for dx, dy in SITE_TRY:
        sx, sy = bx + dx, by + dy
        if sx >= 0 and sy >= 0 and shore_walkable(shore_tile(sx, sy)):
            return (sx, sy)
    for oy in range(36):
        for ox in range(40):
            sx, sy = cx * 40 + ox, cy * 36 + oy
            if shore_walkable(shore_tile(sx, sy)):
                return (sx, sy)
    return (cx * 40 + 20, cy * 36 + 18)
def go_ashore(sx, sy):
    set16("wShPosX", sx * 8 + 4); pb.tick()
    set16("wShPosY", sy * 8 + 4); pb.tick()
    for _ in range(30): pb.tick()
def reboard():
    set16("wShPosX", w16("wDingX")); pb.tick()
    set16("wShPosY", w16("wDingY")); pb.tick()
    press("a", 5)
    for _ in range(120): pb.tick()
    assert mem[syms["wState"]] == 2, "reboard failed (state %d)" % mem[syms["wState"]]
def find_approach(isle):
    cx, cy = isle
    for ty in range(cy*18, cy*18+18):
        for tx in range(cx*20, min(cx*20+20, 320)):
            if model_tile(tx, ty) >= 3:
                for ox, oy in ((0,-1),(0,1),(-1,0),(1,0)):
                    wx, wy = tx+ox, ty+oy
                    # water neighbor must also be inside the isle's cell,
                    # or CellWatch never sees the ship in the isle cell
                    if model_tile(wx, wy) < 3 and \
                       cx*20 <= wx < cx*20+20 and cy*18 <= wy < cy*18+18:
                        return (wx, wy)
    raise RuntimeError("no beach in isle cell")

for _ in range(150):
    pb.tick()
pb.button_press("start")
pb.tick()
pb.button_release("start")
for _ in range(10):
    pb.tick()
pb.button_press("a")
pb.tick()
pb.button_release("a")
for _ in range(60):
    pb.tick()

# --- teleport into isle 0's cell ---
isle0 = (mem[syms["wIsles"]], mem[syms["wIsles"] + 1])
print("isle 0 cell:", isle0)
# teleport to the isle cell's NW water area: tile (cx*20+2, cy*18+2) px*8
tx, ty = find_approach(isle0)
assert teleport(pb, tx, ty), "teleport to isle 0's cell never stuck"
# guardian spawn retries one random offset per frame until one lands on
# water, so poll instead of assuming a fixed frame count
for _ in range(600):
    pb.tick()
    if mem[syms["wEnemyActive"]]:
        break
print("ship cell:", mem[syms["wShipCX"]], mem[syms["wShipCY"]])

# guardian should have spawned
print("enemyActive:", mem[syms["wEnemyActive"]], "guardian:", mem[syms["wIsGuardian"]], "HP:", mem[syms["wEnemyHP"]])
assert mem[syms["wEnemyActive"]] == 1, "guardian didn't spawn"
assert mem[syms["wIsGuardian"]] == 1, "spawned enemy isn't a guardian"
assert mem[syms["wEnemyHP"]] == 5, "guardian should have 5 HP"

# land BEFORE defeating the guardian: no X, digging does nothing
mem[syms["wHasDinghy"]] = 1
press("a", 60)  # land on the isle's beach
assert mem[syms["wState"]] == 9, "didn't go ashore (state %d)" % mem[syms["wState"]]
dsx, dsy = dig_site(isle0[0], isle0[1], 0)
go_ashore(dsx, dsy)
press("a", 5)
assert mem[syms["wState"]] == 9, "dig should be blocked while the guardian lives"
print("dig blocked while guardian alive: OK")
reboard()

# sink the guardian: weaken + overlapping player ball
mem[syms["wEnemyHP"]] = 1
ex, ey = w16("wEnemyX"), w16("wEnemyY")
set16("wBallPX", ex)
set16("wBallPY", ey)
mem[syms["wBallPVX"]] = 0
mem[syms["wBallPVY"]] = 0
mem[syms["wBallPLife"]] = 40
mem[syms["wBallPActive"]] = 1
for _ in range(10):
    pb.tick()
assert mem[syms["wEnemyActive"]] == 0, "guardian didn't sink"
gm = w16("wGuardMask")
print("guardian sunk, guardMask =", bin(gm))
assert gm & 1, "guard bit not set"

# land again, walk to the X, dig
press("a", 60)  # land
for _ in range(30):
    pb.tick()
assert mem[syms["wState"]] == 9, "didn't land for the dig"
go_ashore(dsx, dsy)
press("a", 60)  # dig scene opens
assert mem[syms["wState"]] == 5, "dig scene didn't open"
fm = w16("wFragMask")
print("fragMask =", bin(fm))
assert fm & 1, "fragment not collected"
press("a", 5)   # skip the ceremony to the reveal
assert mem[syms["wDigT"]] == 0, "ceremony didn't skip to the reveal"
assert mem[syms["wState"]] == 5, "reveal left the dig state"
press("a", 60)  # leave dig scene (back ashore now: the X is on land)
for _ in range(60):
    pb.tick()
assert mem[syms["wState"]] == 9, "dig scene should return ashore"
reboard()
print("dig scene (ashore): OK")

# --- final battle: set fragments for isles 1-7 (leave isle 8 = bit 8) ---
# our dig was isle 0. Set isles 1..7 collected, then dig isle 8.
set16("wFragMask", 0xFE)  # isles 1-7 collected (bits 1-7)
# teleport to isle 8's cell
isle8 = (mem[syms["wIsles"] + 16], mem[syms["wIsles"] + 17])
print("isle 8 cell:", isle8)
set16("wGuardMask", 0x100)  # its guardian pre-defeated
set16("wFragMask", 0x1FE - 0x100)  # collect all but bit 8 -> 0xFE... recompute: bits 0-7 = 0xFF? we have isle0 already
# actually: currently fragMask has isle0; set bits 1-7 too:
set16("wFragMask", 0x00FF)  # isles 0-7 collected
mem[syms["wFragCount"]] = 8   # SetFrag's cached count (the 9th dig makes 9)
tx, ty = find_approach(isle8)
assert teleport(pb, tx, ty), "teleport to isle 8's cell never stuck"
for _ in range(10):
    pb.tick()
# guardian for isle 8 will try to spawn (guard bit set -> no spawn)
press("a", 60)  # land
d8x, d8y = dig_site(isle8[0], isle8[1], 8)
for _ in range(30):
    pb.tick()
assert mem[syms["wState"]] == 9, "didn't land on isle 8"
go_ashore(d8x, d8y)
press("a", 60)
print("state after 9th dig A:", mem[syms["wState"]])
assert mem[syms["wState"]] == 5, "9th dig scene didn't open"
press("a", 5)   # skip the ceremony to the reveal
print("diag: curIsle", mem[syms["wCurIsle"]], "fragMask", hex(w16("wFragMask")), "final", mem[syms["wFinal"]])
assert mem[syms["wFinal"]] >= 1, "final battle not triggered"
press("a", 60)
for _ in range(60):
    pb.tick()
assert mem[syms["wState"]] == 9, "9th dig should return ashore"
reboard()

# sink all four waves; each sink may instantly spawn the next. Waves
# escalate: wave k has 5+k HP (checked before weakening) and faster guns.
for wave in (1, 2, 3, 4):
    # wave k should be active (spawn retries each frame if it lands on land)
    for _ in range(120):
        pb.tick()
        if mem[syms["wEnemyActive"]]:
            break
    assert mem[syms["wEnemyActive"]] == 1 and mem[syms["wIsGuardian"]] == 1, \
        f"final wave {wave} didn't spawn"
    want_hp = 5 + wave
    assert mem[syms["wEnemyHP"]] == want_hp, \
        f"wave {wave} HP {mem[syms['wEnemyHP']]}, want {want_hp}"
    print(f"final wave {wave} spawned (HP {want_hp})")
    mem[syms["wEnemyHP"]] = 1
    ex, ey = w16("wEnemyX"), w16("wEnemyY")
    set16("wBallPX", ex)
    set16("wBallPY", ey)
    mem[syms["wBallPVX"]] = 0
    mem[syms["wBallPVY"]] = 0
    mem[syms["wBallPLife"]] = 40
    mem[syms["wBallPActive"]] = 1
    for _ in range(5):
        pb.tick()
    print(f"wave {wave} sunk; active =", mem[syms["wEnemyActive"]], "final =", mem[syms["wFinal"]])
    # wait for the next wave / victory
    for _ in range(30):
        pb.tick()

print("final fleet sunk: 4 escalating waves")

print("state:", mem[syms["wState"]], "(6 = victory)")
assert mem[syms["wState"]] == 6, "no victory!"
# victory screen text present
t = [mem[0x9800 + 3 * 32 + 1 + i] for i in range(19)]
print("victory text row:", [x for x in t if x])
assert any(t)
press("a", 60)
assert mem[syms["wState"]] == 2, "victory exit failed"
pb.stop()
print("ALL M5 CHECKS PASSED")

from pyboy import PyBoy

ROM = "/home/spencer/Repositories/gb/pirates-folly/pirates_folly.gb"
SYM = "/home/spencer/Repositories/gb/pirates-folly/build/pirates_folly.sym"

pb = PyBoy(ROM, window="null")
pb.set_emulation_speed(0)
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
    pb.button_press(btn)
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
set16("wPosX", (tx * 8) << 4)
set16("wPosY", (ty * 8) << 4)
for _ in range(10):
    pb.tick()
print("ship cell:", mem[syms["wShipCX"]], mem[syms["wShipCY"]])

# guardian should have spawned
print("enemyActive:", mem[syms["wEnemyActive"]], "guardian:", mem[syms["wIsGuardian"]], "HP:", mem[syms["wEnemyHP"]])
assert mem[syms["wEnemyActive"]] == 1, "guardian didn't spawn"
assert mem[syms["wIsGuardian"]] == 1, "spawned enemy isn't a guardian"
assert mem[syms["wEnemyHP"]] == 5, "guardian should have 5 HP"

# dock attempt BEFORE defeating guardian -> no dig
press("a")
st = mem[syms["wState"]]
assert st != 5, "dig should be blocked while guardian lives"
print("dig blocked while guardian alive: OK (state", st, ")")
if st == 4:  # beach was also a port: B once returns to sailing
    press("b", 60)
    assert mem[syms["wState"]] == 2

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

# now dock -> dig scene
press("a", 60)
print("state after dock A:", mem[syms["wState"]])
assert mem[syms["wState"]] == 5, "dig scene didn't open"
fm = w16("wFragMask")
print("fragMask =", bin(fm))
assert fm & 1, "fragment not collected"
press("a", 60)  # leave dig scene
assert mem[syms["wState"]] == 2, "dig scene didn't exit"
print("dig scene: OK")

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
tx, ty = find_approach(isle8)
set16("wPosX", (tx * 8) << 4)
set16("wPosY", (ty * 8) << 4)
for _ in range(10):
    pb.tick()
# guardian for isle 8 will try to spawn (guard bit set -> TestGuard says defeated -> no spawn)
press("a", 60)
print("state after 9th dig A:", mem[syms["wState"]])
assert mem[syms["wState"]] == 5, "9th dig scene didn't open"
print("diag: curIsle", mem[syms["wCurIsle"]], "fragMask", hex(w16("wFragMask")), "final", mem[syms["wFinal"]])
assert mem[syms["wFinal"]] >= 1, "final battle not triggered"
press("a", 60)
assert mem[syms["wState"]] == 2

# wave 1 should spawn shortly
for _ in range(10):
    pb.tick()
assert mem[syms["wEnemyActive"]] == 1 and mem[syms["wIsGuardian"]] == 1, "wave 1 didn't spawn"
print("final wave 1 spawned")

# sink both waves; each sink may instantly spawn the next
for wave in (1, 2):
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

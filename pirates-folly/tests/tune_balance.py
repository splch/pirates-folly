# Difficulty tuning harness (M6). Measures:
#   1. Port access: Chebyshev distance (in 4x4 districts) from spawn to the
#      nearest dockable port (hash + game land rule), across seeds.
#   2. Automated duels: stationary auto-firing player vs a pirate (3 HP,
#      90-frame gun cooldown) and a guardian (5 HP, 60-frame cooldown).
#      Reports frames-to-sink and hull lost per duel.
from pyboy import PyBoy
ROM = "/home/spencer/Repositories/gb/pirates-folly/pirates_folly.gb"
SYM = "/home/spencer/Repositories/gb/pirates-folly/build/pirates_folly.sym"
syms = {}
for line in open(SYM):
    p = line.split()
    if len(p) == 2:
        syms[p[1]] = int(p[0].split(":")[1], 16)

# --- python world model (must match world.asm) ---
def mix16(x):
    x &= 0xFFFF
    x ^= x >> 8; x ^= (x << 7) & 0xFFFF; x ^= x >> 9; x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF
def lathash(ix, iy, s):
    return mix16(((ix * 97 + iy * 61) & 0xFFFF) ^ s) & 0xFF
def mulmag(m, f): return (m * f) >> 3
def lerpu(b, o, f):
    d = o - b
    return b + (mulmag(d, f) if d >= 0 else -mulmag(-d, f))
def elevation(wx, wy, s):
    ix, iy = wx >> 3, wy >> 3
    return lerpu(lerpu(lathash(ix, iy, s), lathash(ix+1, iy, s), wx & 7),
                 lerpu(lathash(ix, iy+1, s), lathash(ix+1, iy+1, s), wx & 7), wy & 7)
def tile(wx, wy, s):
    e = elevation(wx, wy, s)
    return 1 if e < 132 else (2 if e < 148 else (3 if e < 158 else 4))
def has_port(dx, dy, s):
    return (mix16(((dx*37 + dy*91) & 0xFFFF) ^ s ^ 0x7E55) & 0x3F) < 12
def district_land(dx, dy, s):
    return any(tile(dx*4+ox, dy*4+oy, s) >= 3
               for ox, oy in ((1,1),(2,1),(1,2),(2,2)))

def nearest_port_dist(tx, ty, s):
    dx0, dy0 = tx >> 2, ty >> 2
    for r in range(1, 13):
        for dx in range(dx0 - r, dx0 + r + 1):
            for dy in range(dy0 - r, dy0 + r + 1):
                if max(abs(dx-dx0), abs(dy-dy0)) != r: continue
                if not (0 <= dx < 80 and 0 <= dy < 72): continue
                if has_port(dx, dy, s) and district_land(dx, dy, s):
                    return r
    return None

def open_water(s, rad=15):
    """a tile with water out to `rad` tiles in every direction (duel arena)"""
    while rad >= 6:
        for ty in range(60, 230, 2):
            for tx in range(40, 280, 2):
                if all(tile(tx+ox, ty+oy, s) < 3
                       for ox in range(-rad, rad+1) for oy in range(-rad, rad+1)):
                    return tx, ty
        rad -= 2
    return None

pb = PyBoy(ROM, window="null")
pb.set_emulation_speed(0)
mem = pb.memory
def w16(n): return mem[syms[n]] | mem[syms[n] + 1] << 8
def set16(n, v):
    mem[syms[n]] = v & 0xFF; mem[syms[n] + 1] = v >> 8
def press(btn, wait=1):
    pb.button_press(btn); pb.tick(); pb.button_release(btn)
    for _ in range(wait): pb.tick()

for _ in range(150): pb.tick()
press("start", 10)
press("a", 60)
seed16 = (mem[syms["wSeed16"]] << 8) | mem[syms["wSeed16"] + 1]
print(f"default seed16 {seed16:04X}")

# ---------- 1. port access ----------
# spawn tile
sx, sy = w16("wShipX") >> 3, w16("wShipY") >> 3
d = nearest_port_dist(sx, sy, seed16)
print(f"spawn at tile ({sx},{sy}); nearest dockable port: {d} districts")
# tavern coverage: how many dockable ports have another within radius 12?
dockable = [(dx, dy) for dx in range(80) for dy in range(72)
            if has_port(dx, dy, seed16) and district_land(dx, dy, seed16)]
covered = 0
for dx, dy in dockable:
    found = False
    for r in range(1, 13):
        for ox in range(-r, r+1):
            for oy in range(-r, r+1):
                if max(abs(ox), abs(oy)) != r: continue
                nx, ny = dx+ox, dy+oy
                if 0 <= nx < 80 and 0 <= ny < 72 and (nx, ny) != (dx, dy) \
                   and has_port(nx, ny, seed16) and district_land(nx, ny, seed16):
                    found = True; break
            if found: break
        if found: break
    covered += found
print(f"dockable ports: {len(dockable)}; with another port in tavern range: "
      f"{covered} ({100*covered//max(1,len(dockable))}%)")

# ---------- 2. duels ----------
def duel(hp, cool, dx_px, dy_px, label):
    # fresh sailing state at open water
    mem[syms["wEnemyActive"]] = 0
    mem[syms["wBallEActive"]] = 0
    mem[syms["wBallPActive"]] = 0
    mem[syms["wStormT"]] = 0; mem[syms["wStormT"] + 1] = 0
    mem[syms["wHull"]] = 20
    spot = open_water(seed16)
    tx, ty = spot
    set16("wPosX", (tx * 8) << 4); set16("wPosY", (ty * 8) << 4)
    for _ in range(5): pb.tick()
    # place the enemy
    ex, ey = tx * 8 + dx_px, ty * 8 + dy_px
    set16("wEnemyX", ex << 4); set16("wEnemyY", ey << 4)
    mem[syms["wEnemyHP"]] = hp
    mem[syms["wEnemyFireCool"]] = 30   # mid-fight cadence, not spawn grace
    mem[syms["wEnemyActive"]] = 1
    hull0 = mem[syms["wHull"]]
    frames = 0
    while mem[syms["wEnemyActive"]] and frames < 3600:
        # hammer A (FireCannon has its own 30-frame cooldown; auto-aims)
        if frames % 6 == 0:
            pb.button_press("a"); pb.tick(); pb.button_release("a")
        pb.tick()
        frames += 1
        if mem[syms["wState"]] != 2:   # docked/wrecked/chart = bad test
            return None
    sunk = mem[syms["wEnemyHP"]] == 0 and not mem[syms["wEnemyActive"]]
    lost = hull0 - mem[syms["wHull"]]
    print(f"  {label} ({dx_px:+d},{dy_px:+d}): "
          f"{'sunk in ' + str(frames) + 'f' if sunk else 'NO SINK (despawn/timeout)'}, hull lost {lost}")
    return frames, lost

ANGLES = [(100, 0), (0, 100), (-100, 0), (0, -100), (70, 70), (-70, -70)]
print("pirate duels (stationary player):")
res = [duel(3, 90, dx, dy, "pirate") for dx, dy in ANGLES]
res = [r for r in res if r]
if res:
    losses = sorted(r[1] for r in res)
    times = sorted(r[0] for r in res)
    print(f"  -> hull lost min/med/max: {losses[0]}/{losses[len(losses)//2]}/{losses[-1]}")
    print(f"  -> frames-to-sink min/med/max: {times[0]}/{times[len(times)//2]}/{times[-1]} "
          f"(~{times[len(times)//2]//60}s)")
print("guardian duels (stationary player):")
gres = [duel(5, 60, dx, dy, "guardian") for dx, dy in ANGLES]
gres = [r for r in gres if r]
if gres:
    losses = sorted(r[1] for r in gres)
    times = sorted(r[0] for r in gres)
    print(f"  -> hull lost min/med/max: {losses[0]}/{losses[len(losses)//2]}/{losses[-1]}")
    print(f"  -> frames-to-sink min/med/max: {times[0]}/{times[len(times)//2]}/{times[-1]} "
          f"(~{times[len(times)//2]//60}s)")
pb.stop(save=False)
print("TUNING DATA COMPLETE")

from pyboy import PyBoy
ROM = "/home/spencer/Repositories/gb/pirates_folly.gb"
SYM = "/home/spencer/Repositories/gb/build/pirates_folly.sym"
syms = {}
for line in open(SYM):
    p = line.split()
    if len(p) == 2:
        syms[p[1]] = int(p[0].split(":")[1], 16)

def mix16(x):
    x &= 0xFFFF
    x ^= x >> 8; x ^= (x << 7) & 0xFFFF; x ^= x >> 9; x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF

def lathash(ix, iy, seed16):
    return mix16(((ix * 97 + iy * 61) & 0xFFFF) ^ seed16) & 0xFF
def mulmag(m, f): return (m * f) >> 3
def lerpu(base, other, f):
    d = other - base
    return base + (mulmag(d, f) if d >= 0 else -mulmag(-d, f))
def elevation(wx, wy, seed16):
    ix, iy = wx >> 3, wy >> 3
    fx, fy = wx & 7, wy & 7
    h00 = lathash(ix, iy, seed16); h10 = lathash(ix+1, iy, seed16)
    h01 = lathash(ix, iy+1, seed16); h11 = lathash(ix+1, iy+1, seed16)
    return lerpu(lerpu(h00, h10, fx), lerpu(h01, h11, fx), fy)
def tile(wx, wy, seed16):
    e = elevation(wx, wy, seed16)
    if e < 132: return 1
    if e < 148: return 2
    if e < 158: return 3
    if e < 205: return 4
    return 4  # forest/mountain all >= grass: land either way
def cell_has_land(cx, cy, seed16):
    for ty in range(cy*18, cy*18+18):
        for tx in range(cx*20, cx*20+20):
            if tile(tx, ty, seed16) >= 3: return True
    return False
def district_hash(dx, dy, seed16):
    return mix16((((dx*37 + dy*91) & 0xFFFF) ^ seed16 ^ 0x7E55))
def has_port(dx, dy, seed16):
    return (district_hash(dx, dy, seed16) & 0x3F) < 12
def district_land_game(dx, dy, seed16):
    # game's 4-sample rule
    for ox, oy in ((1,1),(2,1),(1,2),(2,2)):
        if tile(dx*4+ox, dy*4+oy, seed16) >= 3: return True
    return False
def district_land_full(dx, dy, seed16):
    for ty in range(dy*4, dy*4+4):
        for tx in range(dx*4, dx*4+4):
            if tile(tx, ty, seed16) >= 3: return True
    return False

pb = PyBoy(ROM, window="null")
pb.set_emulation_speed(0)
mem = pb.memory
for _ in range(150): pb.tick()
pb.button_press("start"); pb.tick(); pb.button_release("start")
for _ in range(10): pb.tick()

SEEDS = [0xDEADBEEF, 0x00000001, 0x12345678, 0xCAFEBABE, 0x0F0F0F0F,
         0xF0F0F0F0, 0xAAAAAAAA, 0x55555555, 0x60426042, 0xFFFFFFFF,
         0x00010002, 0x80000001, 0x7FFFFFFF, 0x31415926, 0x27182818, 0x00000000]
landless_isles = 0; total_isles = 0
ports_hash = ports_game_land = ports_true_land = 0
spawn_ok = 0
for s in SEEDS:
    nib = [(s >> 28) & 15, (s >> 24) & 15, (s >> 20) & 15, (s >> 16) & 15,
           (s >> 12) & 15, (s >> 8) & 15, (s >> 4) & 15, s & 15]
    for i, n in enumerate(nib):
        mem[syms["wSeedNib"] + i] = n
    pb.button_press("a"); pb.tick(); pb.button_release("a")
    for _ in range(60): pb.tick()
    seed16 = (mem[syms["wSeed16"]] << 8) | mem[syms["wSeed16"]+1]
    # isles
    bad = 0
    for k in range(9):
        cx = mem[syms["wIsles"] + 2*k]; cy = mem[syms["wIsles"] + 2*k + 1]
        total_isles += 1
        if not cell_has_land(cx, cy, seed16):
            landless_isles += 1; bad += 1
    # spawn
    px = mem[syms["wPosX"]] | mem[syms["wPosX"]+1] << 8
    py = mem[syms["wPosY"]] | mem[syms["wPosY"]+1] << 8
    if tile(px >> 7, py >> 7, seed16) < 3: spawn_ok += 1
    # port census
    for dx in range(80):
        for dy in range(72):
            if has_port(dx, dy, seed16):
                ports_hash += 1
                if district_land_game(dx, dy, seed16): ports_game_land += 1
                if district_land_full(dx, dy, seed16): ports_true_land += 1
    print(f"seed {s:08X} seed16 {seed16:04X} landless isles: {bad}")
    # back to editor for next seed: B quits sailing
    pb.button_press("b"); pb.tick(); pb.button_release("b")
    for _ in range(30): pb.tick()

print(f"\n{len(SEEDS)} seeds:")
print(f"  isles landless: {landless_isles}/{total_isles}")
print(f"  spawns on water: {spawn_ok}/{len(SEEDS)}")
print(f"  port districts (hash): {ports_hash}; land per game rule: {ports_game_land}; land full-scan: {ports_true_land}")

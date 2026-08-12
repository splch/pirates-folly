from pyboy import PyBoy

ROM = "/home/spencer/Repositories/gb/pirates_folly.gb"
SYM = "/home/spencer/Repositories/gb/build/pirates_folly.sym"

def load():
    pb = PyBoy(ROM, window="null")
    pb.set_emulation_speed(0)
    syms = {}
    for line in open(SYM):
        p = line.split()
        if len(p) == 2:
            syms[p[1]] = int(p[0].split(":")[1], 16)
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
    return pb, syms

def w16(pb, syms, name):
    return pb.memory[syms[name]] | (pb.memory[syms[name] + 1] << 8)

def tilemap(pb):
    return bytes(pb.memory[0x9800:0x9C00])

def drive(pb, button, frames):
    pb.button_press(button)
    for _ in range(frames):
        pb.tick()
    pb.button_release(button)
    for _ in range(60):
        pb.tick()

# --- run 1: sail around, collect state ---
pb, syms = load()
mem = pb.memory
print("spawn ship:", w16(pb, syms, "wShipX"), w16(pb, syms, "wShipY"))
sea0 = tilemap(pb)
assert any(t not in (0,) for t in sea0), "empty screen!"

drive(pb, "right", 300)
drive(pb, "down", 200)
drive(pb, "left", 100)
map1 = tilemap(pb)
pos1 = (w16(pb, syms, "wShipX"), w16(pb, syms, "wShipY"))
print("after drive:", pos1, "cam:", w16(pb, syms, "wCamX"), w16(pb, syms, "wCamY"))

# explored bitmap must be nonzero after driving
exp = bytes(mem[syms["wExplored"] + i] for i in range(32))
assert any(exp), "no cells marked explored"
print("explored bytes set:", sum(1 for b in exp if b))

# isolate the round-trip from world RNG: no storm drift, no enemy, full hull
mem[syms["wStormT"]] = 0
mem[syms["wStormT"] + 1] = 0
mem[syms["wEnemyActive"]] = 0
mem[syms["wBallEActive"]] = 0
mem[syms["wHull"]] = 20
mem[syms["wVelX"]] = 0
mem[syms["wVelY"]] = 0
for _ in range(5):
    pb.tick()
vis_before = [0]*0
tx1, ty1 = w16(pb, syms, "wTileX"), w16(pb, syms, "wTileY")
vis_before = bytes(mem[0x9800 + ((ty1 + r) & 31) * 32 + ((tx1 + c) & 31)]
                   for r in range(19) for c in range(21))
# chart: open, check, close
pb.button_press("start")
pb.tick()
pb.button_release("start")
for _ in range(10):
    pb.tick()
assert mem[syms["wState"]] == 3, "chart didn't open"
chart = tilemap(pb)
sea_tiles = sum(1 for t in chart if t == 1)
land_tiles = sum(1 for t in chart if t == 4)
print(f"chart: {sea_tiles} sea cells, {land_tiles} land cells shown")
assert sea_tiles + land_tiles > 0, "chart shows nothing"
pb.button_press("b")
pb.tick()
pb.button_release("b")
for _ in range(60):
    pb.tick()
assert mem[syms["wState"]] == 2, "didn't return to sailing"
def visible(pb, syms):
    tx, ty = w16(pb, syms, "wTileX"), w16(pb, syms, "wTileY")
    return bytes(pb.memory[0x9800 + ((ty + r) & 31) * 32 + ((tx + c) & 31)]
                 for r in range(19) for c in range(21))
assert visible(pb, syms) == vis_before, "sail screen corrupted by chart visit"
print("chart round-trip: OK")

# long sail east to the map edge
drive(pb, "right", 3000)
shipX = w16(pb, syms, "wShipX")
camX = w16(pb, syms, "wCamX")
print("edge: shipX", shipX, "camX", camX)
assert shipX <= 2559 and camX <= 2392, "escaped the world!"
map_edge = tilemap(pb)
pb.stop()

# --- run 2: determinism (same default seed, same inputs) ---
pb2, syms2 = load()
drive(pb2, "right", 300)
drive(pb2, "down", 200)
drive(pb2, "left", 100)
map2 = tilemap(pb2)
pos2 = (w16(pb2, syms2, "wShipX"), w16(pb2, syms2, "wShipY"))
pb2.stop()
assert pos1 == pos2, f"positions differ: {pos1} vs {pos2}"
assert map1 == map2, "tilemaps differ across runs"
print("determinism: PASS")

# world has islands somewhere along the path?
allmaps = sea0 + map1 + map_edge
assert any(t in (3, 4, 5, 6) for t in allmaps), "never saw land!"
print("land visible along route: yes")
print("ALL M2 CHECKS PASSED")

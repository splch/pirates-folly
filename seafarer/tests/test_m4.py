from pyboy import PyBoy

ROM = "/home/spencer/Repositories/gb/seafarer/seafarer.gb"
SYM = "/home/spencer/Repositories/gb/seafarer/build/seafarer.sym"

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
assert mem[syms["wState"]] == 2

shipX, shipY = w16("wShipX"), w16("wShipY")
gold0 = w16("wGold")
print(f"ship at ({shipX},{shipY}), gold {gold0}")

# --- force-spawn a pirate 60px east ---
set16("wEnemyX", 2 << 4)  # 62px west, in open water
set16("wEnemyY", shipY << 4)
mem[syms["wEnemyActive"]] = 1
mem[syms["wEnemyHP"]] = 3
mem[syms["wEnemyFireCool"]] = 90
for _ in range(10):
    pb.tick()
assert mem[syms["wEnemyActive"]] == 1, "enemy vanished"

# enemy should approach: distance shrinks
ex0 = w16("wEnemyX") >> 4
for _ in range(30):
    pb.tick()
ex1 = w16("wEnemyX") >> 4
print(f"enemy X: {ex0} -> {ex1} (ship {shipX})")
assert ex1 > ex0, "enemy didn't approach"
assert ex1 <= shipX - 35, f"enemy came too close: {ex1}"  # holds ~40px away

# enemy should fire eventually (within 90px now)
fired = False
for _ in range(150):
    pb.tick()
    if mem[syms["wBallEActive"]]:
        fired = True
        break
assert fired, "enemy never fired"
print("enemy fired: OK")

# player fires at enemy (A at sea, no beach nearby)
pb.button_press("a")
pb.tick()
pb.button_release("a")
pb.tick()
assert mem[syms["wBallPActive"]] == 1, "player ball didn't spawn"
print("player fired: OK")

# let the fight play out; spam fire whenever possible
hits0 = mem[syms["wEnemyHP"]]
for _ in range(600):
    if not mem[syms["wBallPActive"]] and not mem[syms["wFireCool"]]:
        pb.button_press("a")
        pb.tick()
        pb.button_release("a")
    pb.tick()
    if not mem[syms["wEnemyActive"]]:
        break
assert not mem[syms["wEnemyActive"]], "enemy never sunk"
gold1 = w16("wGold")
print(f"enemy sunk! gold {gold0} -> {gold1}")
assert gold1 > gold0, "no loot"

# --- storm: force one and check drift + palette ---
set16("wStormT", 480)
mem[syms["wStormDX"]] = 16  # +1 px/frame east
mem[syms["wStormDY"]] = 0
x0 = w16("wShipX")
for _ in range(30):
    pb.tick()
x1 = w16("wShipX")
bgp = mem[0xFF47]
print(f"storm drift: {x0} -> {x1}, BGP = {bgp:#x}")
assert x1 > x0, "no storm drift"
assert bgp == 0xF9, "storm palette not applied"

# storm ends
set16("wStormT", 2)
for _ in range(10):
    pb.tick()
bgp = mem[0xFF47]
assert bgp == 0xE4, f"palette not restored: {bgp:#x}"
print("storm start/end: OK")

# --- collision damage still works with combat active ---
hull0 = mem[syms["wHull"]]
mem[syms["wDmgCool"]] = 0
set16("wPosX", w16("wPosX"))  # no-op
# drive into the nearest coast: just ram east hard for a while
pb.button_press("right")
for _ in range(400):
    pb.tick()
    if mem[syms["wHull"]] < hull0:
        break
pb.button_release("right")
print(f"hull after ramming: {mem[syms['wHull']]} (was {hull0})")
assert mem[syms["wHull"]] < hull0, "no collision damage"

pb.stop()
print("ALL M4 CHECKS PASSED")

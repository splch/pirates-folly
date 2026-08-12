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
pb = PyBoy(ROM, window="null")
pb.set_emulation_speed(0)
mem = pb.memory
def press(btn, wait=30):
    pb.button_press(btn); pb.tick(); pb.button_release(btn)
    for _ in range(wait): pb.tick()
def set16(n, v):
    mem[syms[n]] = v & 0xFF; mem[syms[n] + 1] = v >> 8

for _ in range(150): pb.tick()
press("start", 10)
press("a", 60)
# teleport next to the RUM COVE beach (port district 10,35)
set16("wPosX", (320) << 4); set16("wPosY", 1112 << 4)
for _ in range(10): pb.tick()
# in-world dock tiles: the beach's sand should render as TILE_DOCK (14)
tx, ty = mem[syms["wTileX"]], mem[syms["wTileY"]]
tm = bytes(mem[0x9800 + ((ty + r) & 31) * 32 + ((tx + c) & 31)] for r in range(19) for c in range(21))
docks = tm.count(14)
print("dock tiles visible:", docks)
assert docks > 0, "no dock tiles rendered near port beach"
# dock there
press("a", 60)
assert mem[syms["wState"]] == 4, "docking failed"
assert any(mem[syms["wPortCells"] + i] for i in range(32)), "port cell not marked"
# set sail, open chart
press("b", 60)
assert mem[syms["wState"]] == 2
press("start", 30)
assert mem[syms["wState"]] == 3, "chart didn't open"
chart = bytes(mem[0x9800:0x9C00])
markers = chart.count(13)
print("chart port markers:", markers)
assert markers >= 1, "no port marker on chart"
pb.stop(save=False)
print("PORT MARKERS + DOCK TILES OK")

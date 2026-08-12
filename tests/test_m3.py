import sys
from pyboy import PyBoy

ROM = "/home/spencer/Repositories/gb/pirates_folly.gb"
SYM = "/home/spencer/Repositories/gb/build/pirates_folly.sym"

def load_symbols():
    syms = {}
    for line in open(SYM):
        p = line.split()
        if len(p) == 2:
            syms[p[1]] = int(p[0].split(":")[1], 16)
    return syms

def new_game(pb):
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

def press(pb, btn, wait=30):
    pb.button_press(btn)
    pb.tick()
    pb.button_release(btn)
    for _ in range(wait):
        pb.tick()

def dock(pb, syms):
    mem = pb.memory
    mem[syms["wPosX"]] = (320 << 4) & 0xFF
    mem[syms["wPosX"] + 1] = (320 << 4) >> 8
    mem[syms["wPosY"]] = (1112 << 4) & 0xFF
    mem[syms["wPosY"] + 1] = (1112 << 4) >> 8
    for _ in range(5):
        pb.tick()
    press(pb, "a", 30)
    assert mem[syms["wState"]] == 4, "docking failed"

# ==== part 1: port flow ====
pb = PyBoy(ROM, window="null")
pb.set_emulation_speed(0)
syms = load_symbols()
mem = pb.memory
new_game(pb)
dock(pb, syms)

name = [t for t in (mem[0x9800 + 32 + 3 + i] for i in range(12)) if t]
assert name == [57, 60, 52, 39, 42, 54, 61, 44], f"bad name {name}"
print("port name: RUM COVE OK")

# tavern (menu index 2)
press(pb, "down")
press(pb, "down")
press(pb, "a", 90)
assert mem[syms["wPortState"]] == 2, "tavern didn't open"
r6 = [t for t in (mem[0x9800 + 6 * 32 + 1 + i] for i in range(18)) if t]
r8 = [t for t in (mem[0x9800 + 8 * 32 + 1 + i] for i in range(14)) if t]
r9 = [t for t in (mem[0x9800 + 9 * 32 + 1 + i] for i in range(12)) if t]
print("tavern rumor:", r6)
print("nearest port line:", r8, r9)
assert r6, "no rumor text"
assert r8 or r9, "no nearest-port line"
press(pb, "b", 30)
assert mem[syms["wPortState"]] == 0, "tavern B-back failed"

# trade: buy 2 rum
press(pb, "a", 30)  # TRADE is cursor 0 (cursor reset on B-back)
assert mem[syms["wPortState"]] == 1
press(pb, "right", 30)
press(pb, "right", 30)
gold = mem[syms["wGold"]] | mem[syms["wGold"] + 1] << 8
rum = mem[syms["wCargo"]]
print("after 2 buys: gold", gold, "rum", rum)
assert rum == 2 and gold == 38, f"trade wrong: gold {gold} rum {rum}"
# sell 1 back
press(pb, "left", 30)
gold = mem[syms["wGold"]] | mem[syms["wGold"] + 1] << 8
rum = mem[syms["wCargo"]]
assert rum == 1 and gold == 44, f"sell wrong: gold {gold} rum {rum}"
print("trade buy/sell OK")
press(pb, "b", 30)

# set sail (B from main menu)
press(pb, "b", 60)
assert mem[syms["wState"]] == 2, "set sail failed"
pb.stop()
print("PORT FLOW OK")

# ==== part 2: save/load round trip ====
import os
sav = ROM.replace(".gb", ".sav")
pb2 = PyBoy(ROM, window="null")
pb2.set_emulation_speed(0)
mem2 = pb2.memory
syms = load_symbols()
for _ in range(150):
    pb2.tick()
pb2.button_press("start")
pb2.tick()
pb2.button_release("start")
for _ in range(10):
    pb2.tick()
has_save = mem2[syms["wHasSave"]]
print("wHasSave on reboot:", has_save)
gold2 = mem2[syms["wGold"]] | mem2[syms["wGold"] + 1] << 8
rum2 = mem2[syms["wCargo"]]
print("loaded: gold", gold2, "rum", rum2)
assert has_save == 1, "no save detected after reboot"
assert gold2 == 44 and rum2 == 1, f"loaded state wrong: gold {gold2} rum {rum2}"
# editor should show hint text (nonzero tiles on rows 5-6)
hint = [t for t in (mem2[0x9800 + 5 * 32 + 5 + i] for i in range(12)) if t]
assert hint, "no continue hint"
# START continues into sailing
pb2.button_press("start")
pb2.tick()
pb2.button_release("start")
for _ in range(60):
    pb2.tick()
assert mem2[syms["wState"]] == 2, "continue failed"
pos = (mem2[syms["wShipX"]] | mem2[syms["wShipX"] + 1] << 8, mem2[syms["wShipY"]] | mem2[syms["wShipY"] + 1] << 8)
print("continue: sailing at", pos)
pb2.stop()
print("SAVE/LOAD OK")
print("ALL M3 CHECKS PASSED")

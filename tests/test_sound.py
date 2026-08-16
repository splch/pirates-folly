from pathlib import Path

from pyboy import PyBoy

ROOT = Path(__file__).resolve().parents[1]
ROM = str(ROOT / "pirates_folly.gb")
SYM = str(ROOT / "build" / "pirates_folly.sym")
pb = PyBoy(ROM, window="null")
pb.set_emulation_speed(0)
syms = {}
for line in open(SYM):
    p = line.split()
    if len(p) == 2:
        syms[p[1]] = int(p[0].split(":")[1], 16)
mem = pb.memory
def press(btn, wait=30):
    # hold for 3 ticks: a 1-tick press can land between the game's joypad
    # reads (PyBoy writes hit mid-frame) and vanish
    pb.button_press(btn)
    for _ in range(3):
        pb.tick()
    pb.button_release(btn)
    for _ in range(wait): pb.tick()

for _ in range(150): pb.tick()
# APU on, title song playing (Drunken Sailor)
assert mem[0xFF26] & 0x80, "APU off"
assert mem[syms["wSongID"]] == 1, f"song {mem[syms['wSongID']]}"
# after enough frames, a melody note should have triggered ch1 (NR12 env set)
envs = set()
for _ in range(90):
    pb.tick()
    envs.add(mem[0xFF12])
assert 0xF3 in envs, f"ch1 melody env never written: {envs}"
# percussion: NR43 should vary
polys = set()
for _ in range(120):
    pb.tick()
    polys.add(mem[0xFF22])
assert 0x23 in polys or 0x61 in polys, f"no percussion: {polys}"
print("title music OK (env ch1 + ch4 percussion)")

# title -> editor -> new game -> sailing: Wellerman
press("start"); press("a", 60)
assert mem[syms["wSongID"]] == 2, f"sail song {mem[syms['wSongID']]}"
print("sail music OK")

# battle music: force an enemy active
mem[syms["wStormT"]] = 200
for _ in range(5): pb.tick()
assert mem[syms["wSongID"]] == 4, f"battle song {mem[syms['wSongID']]}"
mem[syms["wStormT"]] = 1
for _ in range(8): pb.tick()
assert mem[syms["wSongID"]] == 2, f"back to sail {mem[syms['wSongID']]}"
print("battle/calm switching OK")

# cannon SFX: fire (A) -> ch4 sfx timer set + NR42 cannon env
press("a", 2)
assert mem[syms["wSfx4T"]] > 0, "no sfx timer"
assert mem[0xFF21] == 0xF6, f"cannon env {mem[0xFF21]:#x}"
print("cannon SFX OK")
print("ALL SOUND CHECKS PASSED")

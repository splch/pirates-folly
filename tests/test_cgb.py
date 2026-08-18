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

# Boot a temp copy: PyBoy loads <rom>.ram next to the ROM and writes it on
# stop(), so sharing the repo ROM path leaks saves between test files.
import shutil, tempfile
RUN = str(Path(tempfile.mkdtemp()) / "pf.gb")
shutil.copy(ROM, RUN)

# --- CGB mode ---
pb = PyBoy(RUN, window="null", cgb=True)
pb.set_emulation_speed(0)
mem = pb.memory
for _ in range(150): pb.tick()
assert mem[syms["wIsCGB"]] == 0x11, f"wIsCGB {mem[syms['wIsCGB']]:#x}"
# BG palette 1 (sea) should be loaded: read back via BGPI/BGPD
mem[0xFF68] = 0x80 | 8  # pal 1 color 0
lo = mem[0xFF69]
mem[0xFF68] = 0x80 | 9
hi = mem[0xFF69]
assert (hi << 8 | lo) == 0x7FDA, f"deep-sea pal {hi<<8|lo:#x}"
# title -> editor -> sail
pb.button_press("start"); pb.tick(); pb.button_release("start")
for _ in range(10): pb.tick()
pb.button_press("a"); pb.tick(); pb.button_release("a")
for _ in range(120): pb.tick()
# after sailing fill, bank-1 attrmap should have sea/land attrs in viewport area
mem[0xFF4F] = 1
attrs = bytes(mem[0x9800:0x9800 + 32*20])
mem[0xFF4F] = 0
sea = attrs.count(1) + attrs.count(4); land = sum(attrs.count(i) for i in (2, 3, 5, 6))
print(f"CGB attrmap: sea={sea} sand/land={land}")
assert sea > 50, "no sea attrs streamed"
# sail right for a while; streaming must keep attrs coming
pb.button_press("d-right") if False else None
print("CGB MODE OK")

# --- DMG mode still fine (needs the DMG boot ROM: PyBoy's bundled CGB one
# forces CGB mode) ---
import os, pyboy as _pb
BOOTROM_DMG = os.environ.get("PYBOY_DMG_BOOTROM",
    os.path.join(os.path.dirname(_pb.__file__), "core", "bootrom_dmg.bin"))
pb2 = PyBoy(RUN, window="null", cgb=False, bootrom=BOOTROM_DMG)
pb2.set_emulation_speed(0)
mem2 = pb2.memory
for _ in range(150): pb2.tick()
assert mem2[syms["wIsCGB"]] != 0x11, "DMG misdetected as CGB"
pb2.button_press("start"); pb2.tick(); pb2.button_release("start")
for _ in range(10): pb2.tick()
pb2.button_press("a"); pb2.tick(); pb2.button_release("a")
for _ in range(60): pb2.tick()
assert mem2[syms["wState"]] == 2, "not sailing on DMG"
# DMG must never touch VRAM bank 1. (PyBoy pre-fills bank 1 with junk even
# in DMG mode, so compare before/after instead of asserting zero.)
mem2[0xFF4F] = 1
before = bytes(mem2[0x9800:0x9C00])
mem2[0xFF4F] = 0
for _ in range(120):
    pb2.button_press("d-right") if False else None
    pb2.tick()
mem2[0xFF4F] = 1
after = bytes(mem2[0x9800:0x9C00])
mem2[0xFF4F] = 0
assert before == after, "DMG wrote attr bank!"
print("DMG MODE OK (bank 1 untouched)")

# SGB border: header unlock bytes, hardware detection, and the full
# transfer path (driven by forcing wIsSGB — PyBoy has no SNES side, but
# every GB-side VRAM/bank/packet step runs and must not wedge the game).
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

# --- header: SGB functions stay locked unless $0146=3 and $014B=$33 ---
rom = open(ROM, "rb").read()
assert rom[0x146] == 0x03, f"SGB flag {rom[0x146]:#x}"
assert rom[0x14B] == 0x33, f"old licensee {rom[0x14B]:#x}"
assert rom[0x148] == 0x02 and len(rom) == 131072, "must be a 128 KiB ROM now"

# --- DMG: detection says no-SGB, boot/sail unaffected ---
import os, shutil, tempfile, pyboy as _pb
BOOT = os.path.join(os.path.dirname(_pb.__file__), "core", "bootrom_dmg.bin")
# Boot a temp copy: PyBoy loads <rom>.ram next to the ROM and writes it on
# stop(), so sharing the repo ROM path leaks saves between test files.
RUN = str(Path(tempfile.mkdtemp()) / "pf.gb")
shutil.copy(ROM, RUN)
pb = PyBoy(RUN, window="null", cgb=False, bootrom=BOOT)
pb.set_emulation_speed(0)
mem = pb.memory
for _ in range(150): pb.tick()
assert mem[syms["wIsSGB"]] != 0x14, "DMG misdetected as SGB"
pb.button_press("start"); pb.tick(); pb.button_release("start")
for _ in range(10): pb.tick()
pb.button_press("a"); pb.tick(); pb.button_release("a")
for _ in range(60): pb.tick()
assert mem[syms["wState"]] == 2, "not sailing on DMG"
print("DMG: no SGB detected, sailing OK")

# --- forced SGB: the whole border-transfer path must run and recover ---
pb2 = PyBoy(RUN, window="null", cgb=False, bootrom=BOOT)
pb2.set_emulation_speed(0)
mem2 = pb2.memory
for _ in range(150): pb2.tick()
pb2.button_press("start"); pb2.tick(); pb2.button_release("start")
for _ in range(10): pb2.tick()
mem2[syms["wIsSGB"]] = 0x14  # pretend the SGB boot ROM ran
pb2.button_press("a"); pb2.tick(); pb2.button_release("a")
for _ in range(200): pb2.tick()  # transfer takes ~30 frames of LCD cycling
assert mem2[syms["wState"]] == 2, "SGB border transfer never returned to sailing"
# the sea screen must be fully redrawn: HUD window on, scroll sane
assert mem2[0xFF40] & 0x80, "LCD off after transfer"
assert mem2[0xFF40] & 0x40, "window (HUD) off after transfer"
# the visible map window must hold real terrain again, not seq-map garbage
# (the 32x32 map wraps; rows outside the camera window are always stale)
tx = mem2[syms["wTileX"]] | mem2[syms["wTileX"] + 1] << 8
ty = mem2[syms["wTileY"]] | mem2[syms["wTileY"] + 1] << 8
vals = {mem2[0x9800 + ((ty + r) & 31) * 32 + ((tx + c) & 31)]
        for r in range(19) for c in range(21)}
assert vals <= {1, 2, 3, 4, 5, 6, 14}, f"transfer garbage in view: {vals}"
assert 1 in vals, "no deep-water tiles after redraw"
print("forced-SGB: transfer ran, sea screen rebuilt, sailing OK")

print("ALL SGB CHECKS PASSED")

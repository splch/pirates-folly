from pathlib import Path

from pyboy import PyBoy

ROOT = Path(__file__).resolve().parents[1]
ROM = str(ROOT / "pirates_folly.gb")
# Boot a temp copy: PyBoy loads <rom>.ram next to the ROM and writes it on
# stop(), so sharing the repo ROM path leaks saves between test files.
import shutil, tempfile
RUN = str(Path(tempfile.mkdtemp()) / "pf.gb")
shutil.copy(ROM, RUN)
pb = PyBoy(RUN, window="null")
pb.set_emulation_speed(0)
mem = pb.memory
for _ in range(120): pb.tick()
# title text "PIRATES FOLLY" = tiles at row 4 col 3
row = [mem[0x9800 + 4*32 + 3 + i] for i in range(13)]
assert row == [55,48,57,40,59,44,58,39,45,54,51,51,64], f"title row {row}"
# ship tile on row 13 col 9
assert mem[0x9800 + 13*32 + 9] == 10, "no ship on title"
# press START -> seed editor (digits row 2 = D E A D B E E F)
pb.button_press("start"); pb.tick(); pb.button_release("start")
for _ in range(30): pb.tick()
row2 = [mem[0x9800 + 2*32 + 6 + i] for i in range(8)]
assert row2 == [29,30,26,29,27,30,30,31], f"seed row {row2}"
print("TITLE SCREEN OK")

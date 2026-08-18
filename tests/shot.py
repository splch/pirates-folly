"""Screenshot harness: boot the ROM, sail on DEADBEEF, dump PNGs for art review."""
import shutil, tempfile
from pathlib import Path
from pyboy import PyBoy

ROOT = Path(__file__).resolve().parents[1]
RUN = str(Path(tempfile.mkdtemp()) / "pf.gb")
shutil.copy(ROOT / "pirates_folly.gb", RUN)

pb = PyBoy(RUN, window="null")
pb.set_emulation_speed(0)
for _ in range(150):
    pb.tick()
pb.button_press("start"); pb.tick(); pb.button_release("start")
for _ in range(10):
    pb.tick()
pb.button_press("a"); pb.tick(); pb.button_release("a")
for _ in range(120):
    pb.tick()

out = ROOT / "build" / "shots"
out.mkdir(exist_ok=True)

def snap(name):
    pb.screen.image.save(out / name)

snap("sea_spawn.png")

# sail east into new water
pb.button_press("right")
for _ in range(400):
    pb.tick()
pb.button_release("right")
for _ in range(30):
    pb.tick()
snap("sea_east.png")

# sail south toward likely coast
pb.button_press("down")
for _ in range(400):
    pb.tick()
pb.button_release("down")
for _ in range(30):
    pb.tick()
snap("sea_south.png")

# chart screen
pb.button_press("start"); pb.tick(); pb.button_release("start")
for _ in range(30):
    pb.tick()
snap("chart.png")
pb.stop()
print("wrote", out)

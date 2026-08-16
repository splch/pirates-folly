# PIRATE'S FOLLY

*A procedurally-generated pirate voyage for the Game Boy. Every sea is born
from an 8-digit seed; share a seed, share a world.*

You are a pirate captain with a small ship, a blank chart, and an ocean that
has never existed before. Somewhere out there, ringing the center of the
world, lie the **Nine Isles of Legend** — Libertalia, Whydah Deep, Kraken
Skerry, The Locker, Old Roger Rock, Kidds Cache, Fiddlers Green, Dutchman
Cape, and Maroon Spit. Each is guarded. Each hides a fragment of a chart.
Assemble all nine, survive the final fleet, and the Treasure of the Nine
Isles is yours.

Runs on DMG, CGB, AGB, SGB, emulators, and Analogue Pocket. DMG-first
(4 shades), with color palettes auto-detected on CGB. On a Super Game Boy
each sea gets a day or night border, chosen by the seed itself.

## Playing

**Play now in your browser**: <https://splch.github.io/pirates-folly/> —
the ROM runs in a WebAssembly emulator, no install needed. Progress autosaves
in the browser, and touch devices get an on-screen gamepad.


Get `pirates_folly.gb` from the
[latest rolling release](https://github.com/splch/pirates-folly/releases/tag/latest)
(rebuilt on every push to `main`) or [build it yourself](#building),
then flash it to a cartridge or open it in any Game Boy emulator
(BGB, SameBoy, mGBA, PyBoy, ...).

| Button | At sea | In port | Elsewhere |
|---|---|---|---|
| D-pad | Sail (momentum — ease off!) | Menus | Edit seed digits |
| A | Dock at a beach / fire cannons / **dig** on an isle | Confirm / buy (RIGHT) | New game (seed screen) |
| B | Quit to seed screen (press twice; unsaved) | Back / set sail | — |
| START | **The chart** (your map fills in as you explore) | — | Continue a saved game |

- **Eight hex digits, one ocean.** `DEADBEEF` is a fine first sea. **A** starts
  a new voyage with the edited seed; **START** continues a saved one (the game
  autosaves whenever you dock or leave port, and on victory).
- **Chart everything.** Sailing into a new cell inks it into your map. Newly
  charted waters may hold pirates (~1 in 5, ≈19%) or storms — isle cells roll no
  random encounters, but their guardians will find you.
- **Spot ports from the sea**: beaches with plank-dock tiles are dockable.
  Trade four goods (rum, silk, spice, cannon), repair the hull, recruit crew,
  and ask the tavern for rumors — it knows the nearest port and the nearest
  unclaimed Isle of Legend.
- **Digging.** An isle's beach only gives up its fragment once its guardian
  is sunk.
- **Hull is life.** Ramming land, enemy shot, and storm-tossed drifting all
  cost hull (watch the **H** reading at the bottom of the screen, beside your
  gold and fragment count). At 0 you wreck: lose half your gold and wake in
  open water with a patched hull.

See [MANUAL.md](MANUAL.md) for the full captain's handbook.

## Building

Requires [RGBDS](https://rgbds.gbdev.io) (v1.0.x; CI pins v1.0.3). Either put
`rgbasm`/`rgblink`/`rgbfix` on your `PATH`, or point `RGBDS` at a bin
directory:

```sh
make                       # uses tools/rgbds/bin/ by default
make RGBDS=/path/to/bin/   # use your own RGBDS install
```

Output: `pirates_folly.gb` (64 KiB, MBC5+RAM+BATTERY) plus `build/` artifacts
(symbol and map files used by the test suite).

### Web build

The `web/` directory is a static [binjgb](https://github.com/binji/binjgb)
(MIT) site deployed to GitHub Pages by `.github/workflows/pages.yml` on every
push to `main` (the workflow builds the ROM fresh, so the page always ships
the latest `main`). To preview locally:

```sh
make && cp pirates_folly.gb web/ && (cd web && python3 -m http.server)
```

## Testing

Headless [PyBoy](https://github.com/Baekalfen/PyBoy) tests drive the real ROM
and assert on VRAM, WRAM symbols, and hardware registers:

```sh
pip install pyboy
for t in tests/test_*.py; do python "$t"; done
python tests/lint_worlds.py    # seed sweep: spawns, isle land, port census
```

- `test_title.py` / `test_cgb.py` — title screen, CGB palette init, DMG/CGB parity
- `test_m2.py` … `test_m5.py` — worldgen/streaming, ports & economy, combat, the Nine Isles
- `test_sound.py` — APU driver and song/SFX triggers
- `test_sgb.py` — SGB header/detection, forced-run of the border transfer
- `test_ports_m6.py` — port content pass
- `tests/lint_worlds.py` — reimplements the worldgen math in Python and sweeps
  16 seeds against the running ROM, validating spawns land on water, every
  isle contains land, and port-district statistics
- `tests/tune_balance.py` — combat balance harness (port-access distance,
  automated duels)

CI (`.github/workflows/ci.yml`) builds the ROM and runs the whole suite on
every push and PR, uploading the `.gb` as an artifact.

## Project layout

```
src/            RGBDS assembly (the whole game is hand-written SM83)
  main.asm      boot, state machine, title & seed editor, save init
  world.asm     procedural ocean: value noise, streaming blits, fog of war, chart
  sail.asm      sailing physics, smooth scrolling, tile streaming, HUD, wreck
  combat.asm    pirates, guardians, broadsides, storms
  isles.asm     the Nine Isles, digs, final battle, victory
  port.asm      docking, market, tavern, repair/recruit, battery save/load
  sound.asm     3-channel shanty driver + SFX (no hUGEDriver)
  sgb.asm       SGB border transfer (CHR_TRN/PCT_TRN), seed-picked day/night
  sgb_day.inc, sgb_night.inc   generated border data (tools/png2sgb.py)
  tiles.asm     hand-drawn 2bpp tiles & 3x5 font (gfx literals), CGB palettes
  rng.asm       Mul8, Mix16 coordinate hash, xorshift16 PRNG
  joypad.asm    input with new-press detection and auto-repeat
  defs.inc      shared constants (states, tiles, tuning knobs)
tests/          PyBoy headless test suite + world lint + balance tuner
res/            SGB border art (256x224 PNGs)
tools/          png2sgb.py (SGB border converter), vendored RGBDS (gitignored)
docs/           PIRATE_GAME_PLAN.md, PIRATE_LORE.md, dev references
MANUAL.md       the player's manual
```

## How it works

- **The world is a pure function of the seed.** `WorldTile(x, y)` derives
  terrain from value noise — a `Mix16` coordinate hash on an 8-tile lattice,
  bilinear elevation, thresholds for deep/shallow/sand/grass/forest/mountain.
  Nothing about the world is ever stored; only your *changes* are (fog of
  war, port markers, fragment/guardian bits, position, gold, cargo).
- **32-bit seed, 16-bit fold.** The seed editor's 8 hex digits fold to
  `wSeed16 = Mix16(b0:b1) + Mix16(b2:b3)` — an additive fold, so
  `00000000`, `FFFFFFFF`, and `AAAAAAAA` don't collapse to the same world.
- **Streaming scroll.** The logic phase generates the entering row/column
  into staging buffers; VBlank code blits ≤21 tiles into the wrapping BG map,
  runs OAM DMA from HRAM, animates water, and updates the HUD window.
- **Everything else is hashed too.** Port districts (~19% of 4×4-tile
  districts), port names (16×16 prefix/suffix), market price drift, tavern
  rumors, encounter rolls, and the Nine Isles' positions are all pure hash
  functions of coordinates + seed — deterministic and storage-free.
- **SGB borders.** On SGB/SGB2 (detected via the boot ROM's C register),
  the border is beamed over with CHR_TRN/PCT_TRN VRAM transfers while the
  screen is frozen with MASK_EN: 256 SNES 4bpp tiles, a 32x28+1 map, and
  three 15-color palettes per border, all generated offline from PNG art.
  Day or night is bit 0 of `wSeed16` — the sky is part of the world.
- **Battery save.** MBC5 SRAM at `$A000` with magic bytes, a version field,
  and a checksum; validated on boot. Isle positions are recomputed from the
  seed on load, never saved.
- **Music.** Six public-domain shanties — Drunken Sailor (title), Wellerman
  (sailing), Spanish Ladies (port), Blow the Man Down (battle), Rolling Home
  (victory), Leave Her Johnny (shipwreck) — on a hand-rolled 3-channel driver
  (pulse melody, pulse bass, noise percussion) with priority SFX.

The design doc is [docs/PIRATE_GAME_PLAN.md](docs/PIRATE_GAME_PLAN.md); the
names and rumors draw on [docs/PIRATE_LORE.md](docs/PIRATE_LORE.md), a
researched reference on Golden Age piracy.

## License

[MIT](LICENSE) © 2026 Spencer Churchill. The shanties are public domain.

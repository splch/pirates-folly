# SEAFARER — Manual

*A procedurally-generated pirate voyage for the Game Boy. Every sea is born
from an 8-digit seed; share a seed, share a world.*

## The story so far

You are a pirate captain with a small ship, a blank chart, and an ocean that
has never existed before. Somewhere out there, ringing the center of the
world, lie the **Nine Isles of Legend** — LIBERTALIA, WHYDAH DEEP, KRAKEN
SKERRY, THE LOCKER, OLD ROGER ROCK, KIDDS CACHE, FIDDLERS GREEN, DUTCHMAN
CAPE, and MAROON SPIT. Each is guarded. Each hides a fragment of a chart.
Assemble all nine and the final fleet will come for you. Sink it, and the
Treasure of the Nine Isles is yours.

## Controls

| Button | At sea | In port | Elsewhere |
|---|---|---|---|
| D-pad | Sail (momentum — ease off!) | Menus | Edit seed digits |
| A | Dock at a beach / fire cannons / **dig** on an isle | Confirm / buy (RIGHT) | New game (seed screen) |
| B | — | Back / set sail | — |
| START | **The chart** (your map fills in as you explore) | — | Continue a saved game |

## The seed screen

Eight hex digits, one ocean. **A** rolls a new voyage; **START** continues a
saved one (the game autosaves whenever you dock or leave port, and on
victory). `DEADBEEF` is a fine first sea.

## Captain's handbook

- **Chart everything.** Sailing into a new cell inks it into your map
  (START). Newly charted waters may hold pirates (~1 in 5) or storms.
- **Hull is life.** Ramming land, enemy shot, and storm-tossed drifting all
  cost hull. At 0 you wreck: lose half your gold, wake up in open water with
  a patched hull. Repairs at port cost 2 gold per point.
- **Broadside.** A fires your cannons — at the enemy if one is engaged,
  ahead otherwise. Pirates take 3 hits, isle guardians 5. A sunk ship spills
  gold. Enemy guns outrange yours; close the distance or run.
- **Storms.** Eight seconds of wind drift and dark skies. Keep steering —
  a ship that isn't answering the helm takes damage.
- **Trade.** Four goods (rum, silk, spice, cannon); every port drifts its
  own prices from the seed. Buy low, sell high, fill 50 tons of cargo.
- **The tavern knows things.** Rumors, the nearest port ("RUM COVE: 02 DAYS
  NW"), and a pointer to the nearest unclaimed Isle of Legend.
- **Digging.** An isle's beach only gives up its fragment once its guardian
  is sunk. Dock at the isle's beach to dig.
- **The final battle.** The ninth fragment calls up a two-wave fleet.
  Guardians shoot faster than pirates. Repair first.

## Technical notes

- DMG-first (4 shades), CGB-enhanced (color palettes; the game detects the
  hardware at boot). Runs on DMG, CGB, AGB, SGB, emulators, Analogue Pocket.
- MBC5+RAM+BATTERY, 32 KiB ROM (single bank, ~3 KB free), battery save with
  magic + version + checksum validation.
- The world is a pure function of the seed (16-bit folded): value noise on an
  8-tile lattice, bilinear elevation, thresholded into deep/shallow/sand/
  grass/forest/mountain. Nothing is stored but your changes.
- Music: six public-domain shanties — Drunken Sailor (title), Wellerman
  (sailing), Spanish Ladies (port), Blow the Man Down (battle), Rolling Home
  (victory), Leave Her Johnny (shipwreck) — plus SFX, on a hand-rolled
  3-channel driver (no hUGEDriver).
- Tests (PyBoy, headless): `tests/` — worldgen (m2), ports (m3), combat
  (m4), the Nine Isles (m5), sound, title, CGB/DMG, and `lint_worlds.py`,
  a seed sweep that validates spawns, isle land, and port census stats.

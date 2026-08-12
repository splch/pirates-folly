# SEAFARER

A procedurally-generated pirate exploration game for the Game Boy (DMG-first, CGB-enhanced).
See `../PIRATE_GAME_PLAN.md` for the full design and roadmap, `MANUAL.md` for
how to play, and `../PIRATE_LORE.md` for the Golden-Age source material behind
the names, rumors, and Isle legends.

## Current status: M6 — polish ✅ **v1.0**

- **Title screen** (boots to SEAFARER + a lone ship on the horizon; any
  A/START -> seed editor).
- **Sound**: hand-rolled 3-channel driver (pulse melody, pulse bass, noise
  percussion) playing public-domain shanties transcribed from ABC notation —
  Drunken Sailor (title), Wellerman (sailing), Spanish Ladies (port),
  Blow the Man Down (battle — auto-switches when enemies/storms threaten),
  Rolling Home chorus (victory), Leave Her Johnny (shipwreck) — plus a dig
  jingle and 9 SFX (cannon, hit, sink+coin, splash, storm, wreck, coin, bell,
  knock). All shanty streams statically validated: channels loop in lockstep.
- **CGB color pass**: boot-time CGB detect, 4 BG palettes (UI/sea/sand/land)
  + 2 OBJ palettes, per-tile attribute streaming alongside the tile pipeline,
  colored chart. DMG path untouched (attr writes guarded; verified bank 1 is
  never written on DMG).
- **Lore pass** (from `../PIRATE_LORE.md`): 16 tavern rumors (several old ones
  were silently truncated off-screen — all now fit), port-name tables enriched
  (JOLLY, DAVY, GROG, MAROON, KRAKEN / LOCKER, ROADS, REEF), and the Nine
  Isles have legendary names the tavern uses (LIBERTALIA:, WHYDAH DEEP:, ...).
- **World-lint** (`tests/lint_worlds.py`): sweeps 16 seeds headless — 144/144
  isles land-validated, 16/16 spawns on water, port census sane.

### Bugs found & fixed in M6

- **Transposed column streaming** (latent since M2): `GenColStage` loaded the
  vertical lattice neighbors as the horizontal lerp pair, so coasts generated
  while scrolling east/west differed from the pure world function —
  same seed, different world depending on scroll direction. Fixed; streamed
  columns now match full redraws exactly.
- **`DistrictHasLand` always returned true** (returned the tile id in `a`,
  and tile ids are never 0) — tavern port rumors could point at undockable
  districts. Now returns a real 0/1; lint: 6743 of 17186 hash-valid districts
  have land per the game's sample rule.
- **Seed fold collapsed repeated-pattern seeds** (`FFFFFFFF` = `00000000` =
  `AAAAAAAA` = ... -> `$0000`). `wSeed16` is now `Mix16(hi) + Mix16(lo)`;
  verified distinct folds across the lint sweep.
- **Final battle could fizzle**: `CellWatch` consumed a wave even when
  `SpawnGuardian` aborted on land. Waves now only count when they actually
  spawn; isle guardians retry every frame until they appear; spawn offsets
  extended with a near ring (60px) for landlocked isle cells.
- `LoadGame` computed isles from a stale `wSeed16` (masked by a redundant
  recompute at boot); now folds first.
- Missing `!` glyph added (charmap warnings silenced).

<details><summary>M5 notes (the Nine Isles)</summary>

The game now has an ending. Nine isles ring the world center, placed
deterministically per seed (angle table + hash jitter, land-validated). Entering
an isle's cell wakes its **guardian** (5 HP, faster guns). Sink it, dock at the
isle's beach, and **dig up a chart fragment**. Taverns point to the nearest
unclaimed isle ("AN ISLE OF LEGEND: n DAYS NE"). The 9th fragment triggers a
**two-wave final fleet battle**; sinking the last ship rolls the victory screen
(THE TREASURE OF THE NINE ISLES IS YOURS! + gold + THE END). Fragments,
guardian kills, and battle state all persist in the save (v2).

Verified headless (`/tmp/test_m5.py`): isle placement with real land, guardian
spawning, dig gating (blocked while the guardian lives), dig scene, fragment
collection, final-battle wave progression, victory screen. M2/M3/M4
regressions pass.

<details><summary>M4 notes (danger)</summary>

The ocean has teeth now. Charting a new cell rolls for encounters: **pirates**
(~19%, one at a time) pursue to broadside range and open fire; **A** fires your
cannons (aimed at the enemy if engaged, ahead otherwise) — three hits sinks a
pirate for gold loot. **Storms** (~5%) bring 8 s of wind drift, a darkened
palette, and hull damage if you stop steering. Enemy balls, storms, and
beaching all feed the hull → shipwreck flow.

Verified headless (`/tmp/test_m4.py`): enemy approach-and-hold AI (matches the
isolated-unit-test reference), enemy/player firing, sinking + loot, storm
drift/palette/end, collision damage. M2+M3 regressions pass.

<details><summary>M3 notes (ports & economy)</summary>

Boots to the seed editor; **A** starts a new game (or **START** continues a
loaded save). Sail the procedural ocean; **A** next to a beach in a port
district docks. Ports have generated names ("STORM WATCH"), a market (4 goods,
per-port price drift), repair, recruiting, and a tavern with flavor rumors plus
a live nearest-port pointer ("SHARK BAY: 02 DAYS NW"). Collisions damage the
hull; hull 0 = shipwreck (lose half your gold, respawn at sea). Games save to
battery RAM on dock/port-exit (magic + version + checksum validated on boot).

Verified headless (`/tmp/test_m3.py`): docking, port name generation, tavern
rumors incl. nearest-port direction/distance, trade buy/sell, menu flow,
save/load round trip (gold/cargo/position restored, editor continue hint).
M2 checks re-run clean.

<details><summary>M2 notes (infinite ocean)</summary>

<details><summary>M1 notes (sailing skeleton)</summary>

## Build

Requires RGBDS (prebuilt v1.0.3 binaries in `../tools/rgbds/bin/`).

```bash
make            # produces seafarer.gb (CGB-compatible, DMG-first)
```

## Test

Requires PyBoy (e.g. `python3 -m venv /tmp/gbenv && /tmp/gbenv/bin/pip install pyboy`).

```bash
for t in tests/test_*.py; do /tmp/gbenv/bin/python $t; done
/tmp/gbenv/bin/python tests/lint_worlds.py   # 16-seed world sweep
```

ROM budget (v1.0): ROM0 13401/16384 B used, WRAM0 485/8192 B, HRAM 10/127 B.

## Architecture (M0)

| File | Contents |
|---|---|
| `src/main.asm` | Entry/header, state machine (seed editor ⇄ map), VRAM-safe screen helpers |
| `src/joypad.asm` | Joypad read (held/new), direction auto-repeat |
| `src/rng.asm` | `Mul8`, `Mix16` (stateless coordinate hash), `Rand16` (xorshift runtime RNG) |
| `src/world.asm` | On-demand value-noise worldgen, staged streaming, chart, fog of war, spawn |
| `src/port.asm` | Ports: docking, menus, market, tavern/rumors, save/load (MBC5 SRAM) |
| `src/combat.asm` | Encounters, enemy AI, cannonballs, storms, combat rendering |
| `src/isles.asm` | Nine Isles placement, guardians, dig/victory scenes, final battle |
| `src/text.inc` | CHARMAP for text rendering (A-Z font at tiles 40-65) |
| `src/sail.asm` | Sailing mode: physics, camera, streaming pipeline, HUD, shadow OAM + HRAM DMA |
| `src/testmap.asm` | 64×64 test sea (M1 only; not in build) |
| `src/gen.asm` | Island generator: hash fill w/ radial falloff → CA smoothing → terrain tiles |
| `src/sound.asm` | Music driver (2 pulse + noise), shanty data, SFX table |
| `src/tiles.asm` | Hand-drawn terrain tiles + 3×5 hex font + CGB palettes/init |
| `src/defs.inc` | Shared constants; **generator tuning knobs live here** |
| `tests/` | PyBoy headless regression suites (m2-m5, sound, title, cgb) + world lint |

Generator phases (per 20×18 cell, deterministic from `wSeed16`):

1. **Fill**: `Mix16(seed ^ y·97 ^ … ^ x·61)` per tile vs. a chance that falls off with
   distance² from center (`GEN_BASE_CHANCE`, falloff = d2 − d2/4).
2. **Smooth**: `GEN_CA_ITERS` cellular-automata passes (land iff ≥5 of 9 neighborhood).
3. **Terrain**: land+water-neighbor → sand; water+land-neighbor → shallow; interior land →
   grass/forest/mountain sprinkle via a detail hash.

## Lessons / gotchas encoded here

- PyBoy 2.7 runs its bundled boot ROM: cart code starts at frame ~64, and `hook_register`
  needs a bank number. Test harnesses must tick past boot first.
- A reset `jp` at `$0000` makes the ROM robust for emulators that start at PC=0.
- Helper routines that clobber `a` (like `CellPtr`) need `push af` at call sites.
- JR range is ±128 — phase loops with big bodies must use `jp`.
- Exported local labels need their own `::` (e.g. `RunDmaROM.end::`).
- The GB CPU has no `neg` (that's Z80 ED-space) — use `cpl`+`inc` or restructure.
- Arcade thrust/drag: the toward-zero drag nudge must be skipped while thrusting,
  or thrust (+1/frame) can never overcome drag (-1/frame) at low speed.
- Sliding-window scrolling: tilemap col for world col tx is `tx & 31`, SCX = camX & $FF;
  stream the entering column/row on tile-boundary crossings, split runs at wrap.
- Mul8 clobbers b, c, d AND e — never hold anything in registers across helper
  calls; reload from WRAM. (Bit four times: LatHash's e, DistrictHash's return
  bc, FindNearestPort's candidate, EnemyDyByte's b.)
- The GB CPU has no `jp p`/`jp m` (sign conditions) — test `bit 7` instead.
- PyBoy hook callbacks don't fire on `EA` (`ld [a16],a`) instructions; register
  reads in callbacks can mislead — trust memory reads. When in doubt, extract
  the routine into an isolated test ROM and drive it directly.
- UI screens must zero SCX/SCY — sailing's camera scroll otherwise shifts them.
- Interpolation deltas of hash bytes (0..255) exceed signed 8-bit range; lerp with
  sign/magnitude form, not a signed-byte multiply.
- Test ROMs need a real entry at $0100 — PyBoy runs its bundled boot ROM, which
  hands off there (frame ~64); a $0000 jump only covers no-boot emulators.
- Initialize all 40 OAM entries, not just the ones you use — garbage sprites show
  up as stray dots otherwise.

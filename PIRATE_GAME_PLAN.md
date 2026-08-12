# Project: **SEAFARER** (working title)
### A procedurally-generated pirate exploration game for the Game Boy

Planning document. Hardware facts reference `GAMEBOY_DEV_GUIDE.md`; toolchain facts reference `RGBDS_GUIDE.md`.

---

## 1. Vision & Pillars

**Fantasy**: you are a pirate captain with a small ship, a blank map, and a whole ocean that has never existed before. Chart islands, find treasure, trade or plunder, upgrade your ship, and defeat the rival pirate fleet.

**Design pillars** (every feature decision gets checked against these):

1. **A world that fits in 4 bytes.** The entire ocean is derived from one 32-bit seed. Nothing about the world is stored — only what the player has *changed* or *discovered*.
2. **Exploration is the core verb.** Fog of war, filling in the map, spotting sails on the horizon, "X marks the spot." The map screen should feel like a pirate chart being inked in.
3. **Runs, not campaigns.** 45–90 minute sessions with a win condition (find the legendary Treasure of the Nine Isles) and permadeath-lite stakes. A seed can be shared/typed in — daily-run and race potential for free.
4. **DMG-true.** Must run perfectly on an original 1989 Game Boy. CGB color is an enhancement, never a requirement.

**Touchstones**: *Sid Meier's Pirates!* (structure: sail → port → quest → plunder), *Elite* (an entire galaxy from a seed — the original proof this works on 8-bit), *Wind Waker* (sailing + fog-of-war charting), *GBHack* (proof that heavy procgen + permadeath works on GB hardware), *Dragon Warrior Monsters* (how much a GB game can feel).

---

## 2. Target Hardware & Toolchain

### Hardware target

| Decision | Choice | Rationale |
|---|---|---|
| Base platform | **DMG** (4 shades) | Maximum compatibility (DMG, SGB, CGB, AGB, emulators, Analogue Pocket); forces disciplined budgets |
| CGB support | Enhanced (`$80` header flag) | Color palettes + double-speed generation when detected; game fully playable without |
| Cartridge | **MBC5+RAM+BATTERY** | 8 MiB ROM headroom, 32 KiB SRAM for saves + fog of war, guaranteed Double-Speed-safe, rumble optional |
| ROM size | 256 KiB (16 banks) target, room to grow | Code + data is small in procgen; art is the cost |

### Toolchain (decided)

- **RGBDS** (rgbasm/rgblink/rgbfix/rgbgfx) — full control over banks, timing, and memory; we have complete local docs. Assembly is the right call for a game whose core loop is timing-critical scrolling + on-demand generation.
- **hardware.inc** for register definitions.
- **BGB + SameBoy + Emulicious** for debugging (BGB's `LD B,B` breakpoints, Emulicious profiler); **mGBA** for quick sanity runs.
- **Aseprite** (or any PNG editor) → **rgbgfx** for tiles/tilemaps/palettes. Keep per-asset flags in `*.flags` at-files.
- **hUGETracker + hUGEDriver** for music (shanties!), CBT-FX or custom for SFX.
- **evunit** for unit-testing the generator and RNG in CI; **Mooneye/Blargg ROMs** for emulator sanity of the dev environment.
- **make** + `-M -MG -MP` dependency tracking; `rgblink -S romx=N` scramble builds in CI to catch bank-assumption bugs.

**Alternative considered**: GBDK-2020 C (GBHack proves it works for procgen roguelikes). Rejected for the main build because smooth scrolling + per-chunk generation + VRAM streaming wants cycle control, but a **GBDK prototype of the generator** is a sanctioned fast-path for tuning island shapes before porting to asm (see §8, M0).

---

## 3. The World: Procedural Architecture

This is the heart of the project. Everything derives from a **32-bit world seed** chosen on the title screen (auto-rolled from entropy, or typed in).

### 3.1 Two RNGs, never mixed

1. **Coordinate hash** (worldgen): a pure function `hash32(seed, x, y, salt)` — deterministic, stateless. SplitMix32-style integer mixing (multiply-xorshift constants) is ~40 cycles per call in SM83 asm — cheap enough to run per-cell during scrolling. *Never* use a stateful PRNG for worldgen; the world must be regenerable on demand with zero storage.
2. **Stateful PRNG** (runtime events: loot rolls, AI dice, weather): **xorshift32** (or 16-bit for speed where quality doesn't matter), seeded at new-game from `DIV` + joypad timing (GBHack's proven entropy trick: human START-press timing decorrelates runs).

### 3.2 World structure — three scales

```
WORLD   256 × 256 "cells"   (1 cell = 1 map-screen = 20×18 tiles)
CHUNK   generated on demand per cell, never stored whole
TILE    8×8 px, live viewport buffer in WRAM
```

- **Cell type** from `hash(seed, x, y)`: open sea (~72%), island cell (~20%), reef/rocks (~5%), port cell (~2.5%, must border land), special (~0.5%: sea monster lair, maelstrom, the Nine Isles).
- **Value noise** for coastlines: sample hash at cell corners, bilinear-interpolate in Q4.4 fixed point → per-tile elevation; threshold → water/sand/jungle/mountain. Islands emerge from thresholded noise + cellular-automata smoothing pass (4–5 rule, 2 iterations — affordable per-cell, ~1–2 ms).
- **Connectivity guarantee**: port cells are placed by hash *then* validated against a cheap local rule (has sea route to cell edge); the Nine Isles are placed by a fixed algorithm (seeded angular distribution around world center) so the win condition is always reachable. Playability proofs by construction, not by search.
- **Chunk generation on demand**: entering a cell, generate its 20×18 tile map into WRAM. ~2–5 ms worst case on DMG — hidden inside the screen-transition fade. Interior of islands (docks, treasure sites, caves) generated the same way with a different `salt`.

### 3.3 What *is* stored (the only persistent world data)

Per new game, in SRAM (32 KiB budget):

| Data | Size | Notes |
|---|---|---|
| World seed | 4 B | regenerates everything |
| Player state (pos, gold, crew, rum, hull, upgrades, flags) | ~64 B | |
| **Fog of war bitmap** | **8 KiB** | 256×256 cells = 65,536 bits — exactly one SRAM bank. Charted = 1 |
| Port/market deltas (prices drift from seed baseline) | ~1 KiB | sparse table, only visited ports |
| Quest/bounty state | ~256 B | |
| High-seas "encounter cooldown" cells | ~256 B | |
| Magic number + checksum + version | 16 B | GBHack pattern: validate before trusting, 2 rotating save slots + autosave on port dock |

Total < 10 KiB of 32 KiB. Room for a second save slot.

### 3.4 The map screen = the game

Full-screen chart (160×144 viewport into a 256×256-cell map, smooth-scrolled): inked-in islands where explored, sea monsters doodled at rumor cells, "X" for treasure maps owned, ship icon. This is pure BG-map work and sells the fantasy for near-zero runtime cost. **Build it early; it's the game's identity.**

---

## 4. Gameplay Systems (scoped)

### Core loop

```
SAIL (explore, chart, encounter)
  → PORT (sell loot, repair, recruit, hear rumor, buy map fragment)
    → QUEST/TREASURE (follow map X, island interior, boss/dig)
      → upgrade ship → sail further out (harder seas) → ... → Nine Isles finale
```

### MVP system set

- **Sailing**: 8-way movement, momentum + wind direction modifier, smooth pixel scrolling (SCX/SCY + tile-streaming), animated water (2-phase tile swap in VBlank).
- **Encounters at sea**: hash-spawned per cell with cooldown — merchant ships (trade or attack), pirates (fight or flee), storms (skill minigame), sea monsters (deep cells only).
- **Combat**: arcade broadside — positioning + timed volleys, damage to hull/sails/crew. Keep it on the sea layer; no separate combat screen for MVP.
- **Ports**: generated name (syllable table), market with 4 goods (rum, silk, spice, cannon) with seed-drifted prices, tavern rumors (point to undiscovered specials), shipyard upgrades (hull, sails, cannons, crew).
- **Treasure maps**: fragment rewards assemble into "cell X,Y + landmark hint"; digging triggers an island-interior minidungeon (one cell, ~3 screens, generator salt `0xTREASURE`).
- **Win**: collect 9 chart fragments (one per special isle, gated by escalating difficulty rings from world center) → final fleet battle → treasure.

### Explicitly cut from v1.0 (write down, resist creep)

Boarding actions, crew management beyond a number, melee combat, fishing minigame, multiplayer/link cable, SGB border, real-time day/night. (Link-cable 2P naval duel is the first post-1.0 candidate — serial protocol is simple, see dev guide §12.)

---

## 5. Technical Architecture

### Memory budget (DMG: 8 KiB WRAM)

| Region | Use |
|---|---|
| $C000–CFFF (WRAM0) | Current cell tile buffer (20×18 = 360 B), scroll streaming ring, game state structs, OAM shadow buffer (160 B, `ALIGN[8]`), entity table (16 × 16 B) |
| $D000–DFFF (WRAM0 cont. w/ `-w`) | Map-screen cell cache (1 KiB), generator scratch (1 KiB unionized), decompression/scratch unions |
| $FF80–FFFE (HRAM) | OAM DMA routine, joypad state, scroll regs cache, hot loop vars |

Unionized WRAM sections (`SECTION "Scratch", WRAM0, UNION`) for generator scratch vs. combat scratch vs. map-screen scratch — they never coexist.

### ROM bank plan (MBC5)

| Bank | Contents |
|---|---|
| 0 | Header, vectors, main loop, VBlank/STAT handlers, joypad, DMA, RNG/hash, generator core, far-call trampolines |
| 1–2 | Sailing mode (scroll engine, encounters, combat) |
| 3 | Port/market/tavern UI + island interiors |
| 4 | Map screen |
| 5–6 | Tilesets, tilemaps, attrmaps (rgbgfx output) |
| 7 | Music driver + songs, SFX |
| 8–15 | Text tables (names, rumors, dialog), quest data, spare |

Discipline: mode code calls across banks only through bank-0 trampolines; `ASSERT BANK(x) == BANK(y)` wherever co-banking is required. CI scramble builds (`-S romx=8,wramx`) prove no hidden assumptions.

### Rendering

- Sea/sailing: BG layer (tilemap $9800), 20×18 viewport, SCX/SCY fine scroll, column/row streaming on tile-boundary crossing (write during HBlank + VBlank; budget ~22 tile writes/frame on DMG CPU-copy — plan generator to fill WRAM, blit in VBlank).
- HUD: Window layer (WY=128 → bottom 2 rows), LCDC.1 toggled by LYC=LY STAT interrupt to keep sprites off the HUD (classic technique, dev guide §18).
- Ship/enemies/cannonballs: sprites (8×16 mode), ≤10/line enforced by design (max 4 ships + 4 balls + effects; flicker-rotation fallback).
- Screen transitions: BGP fade `$E4→$90→$40→$00` covering cell regeneration.
- CGB enhancements (runtime-detected): color palettes via rgbgfx `-c`, palette-swap day/dusk/night, Double Speed only during generation bursts.

### The frame contract

1. `halt` → VBlank handler: OAM DMA, HUD/window regs, scroll regs, water animation, VRAM blit queue drain.
2. Main: input → sailing physics → entity AI → encounter rolls → generator slice (time-boxed, resumable across frames for big jobs).

Generator is written **reentrant and sliceable**: per-cell generation is split into phases (coast hash → CA smoothing → detail sprinkle) that can run one phase per frame if a cell is entered mid-scroll.

---

## 6. Asset & Content Plan

- **Tiles** (2bpp, ~256-tile budget for sea set): water ×4 frames, coast edges/corners (16 tile marching-squares set from the CA output), sand, jungle, mountain, dock, ship-deck interior set, cave set, port buildings, map-screen set (ink style!), HUD/font (charmap-driven text, dev guide §5 charmaps).
- **Sprites**: player ship (4 dirs × 2 frames, 8×16 metasprites), merchant, pirate brig, sea monster, cannonball, explosion, seagull ambience.
- **Audio**: 3–4 hUGETracker shanties (title, sailing, port, battle), SFX (cannon, splash, coin, seagull, storm).
- **Text**: name syllable tables, 40-ish rumor templates, market UI strings. All via charmap, compressed if ROM gets tight.

---

## 7. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Generation too slow on DMG (visible hitch at cell borders) | Time-boxed slices; precompute the *next* cell in the direction of travel during the current one; CGB double-speed burst; worst case: fade covers it. Profile with Emulicious from day one |
| Unplayable/boring worlds | Connectivity by construction (§3.2); a "world lint" test ROM that generates N seeds headless and asserts ports/finale reachable (run in CI via evunit/SameBoy scripting) |
| Scope creep (it's a pirate game — everything is tempting) | §4 cut-list is law; every feature must serve pillar 1–4 |
| SRAM save corruption | Magic + checksum + dual slots (GBHack pattern); validate on boot; autosave only at ports |
| 10-sprites-per-line flicker | Design encounters to ≤8 objects/line; rotation flicker as fallback |
| VRAM streaming overruns | Blit queue with hard per-frame budget; scroll speed capped so streaming never exceeds budget |

---

## 8. Milestones

**M0 — Generator lab (1–2 weeks, GBDK or asm)**
Standalone ROM: shows one generated cell, seed typed via d-pad. Tune noise thresholds, CA rules, coast tile marching-squares. *Deliverable: pretty islands on demand, deterministic across reboots.*

**M1 — Sailing skeleton**
Scroll engine + streaming + ship physics + water animation + HUD window. Hand-built test sea. *Deliverable: it feels like sailing.*

**M2 — Infinite ocean**
Generator wired to scroll; cell transitions; fog-of-war bitmap; map screen. *Deliverable: the core fantasy works — sail anywhere, chart fills in, same seed = same world.*

**M3 — Ports & economy**
Docking, market, repair/recruit, rumors, save/load. *Deliverable: a playable loop.*

**M4 — Danger**
Encounters, combat, storms, damage/death, permadeath flow. *Deliverable: a game with stakes.*

**M5 — The Nine Isles (win condition)**
Treasure maps, island interiors, chart fragments, finale, ending. *Deliverable: feature-complete.*

**M6 — Polish & ship**
Music/SFX final, CGB color pass, difficulty tuning via world-lint stats, title/attract mode, manual text, romusage budget check, hardware testing (flashcart on real DMG + GBC + GBA). *Deliverable: v1.0 ROM.*

---

## 9. Reference Implementations & Reading

- **GBHack** (github.com/statico/gbhack) — closest prior art: procgen + permadeath on GB. Steal: xorshift16 + DIV/timing seeding, BSP dungeon idea for island interiors, SRAM save validation, banked-generator layout, 150-byte bitpacked FOV.
- **Elite galaxy generation** — the philosophical ancestor: everything from a seed, nothing stored.
- `GAMEBOY_DEV_GUIDE.md` §9 (scrolling/streaming), §18 (frame loop, shadow OAM, HUD window, save practices) — local.
- `RGBDS_GUIDE.md` §6/§9/§18 (sections, macros, build recipes) — local.
- GBDev Discord #gbdev — playtesting and generator tuning feedback.

**First concrete task**: build the RGBDS project skeleton (Makefile from RGBDS_GUIDE §18, hardware.inc, header section, CI scramble build), then M0's coordinate-hash + noise demo on hardware.

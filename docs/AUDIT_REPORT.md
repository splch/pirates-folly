# Pirate's Folly — Audit Report

> **RESOLVED — kept for history.** Every item below was applied (see the
> commit log: `f70cec7` docs fixes, `6bdd7c9` dead-code removal, and the
> Makefile `text.inc` prereq). The later gameplay audits — dead crew stat,
> two-wave finale, quiet charted seas, invisible seed, no gold sink —
> shipped in the P0/P1/P2 and high/medium passes (`git log --oneline`).

*Cross-validated against source: `defs.inc`, `main.asm`, `sail.asm`, `world.asm`,
`port.asm`, `combat.asm`, `isles.asm`, `sgb.asm`, `*.inc`, `Makefile`,
`README.md`, `docs/PIRATE_GAME_PLAN.md`, and the built ROM (`pirates_folly.gb`).*

## Verdict

Six independent audits were cross-checked line-by-line against the source.
**All findings are factually real** — no false positives were found, and none
were removed. Severity was reclassified on several items, and one framing
mis-scope was corrected. **No runtime bug was confirmed in any audit.** The
single must-fix is a documentation error.

| Priority | Item | Audit area | Type |
|---|---|---|---|
| **P0 — must fix** | README:65 ROM size `32 KiB` → `64 KiB` | README | Doc defect (player-facing) |
| **P0 — must fix** | Makefile pattern rule missing `src/text.inc` prereq for 4 built objects | RGBDS / build hygiene | Stale-build risk |
| **P1 — recommended** | README controls table: clarify B-at-sea / A-rolls / 1-in-5 | README | Doc clarity |
| **P2 — housekeeping** | Remove dead `GEN_*` constants & `testmap.inc` Makefile prereq, or delete `gen.asm`/`testmap.asm` | Internal consistency | Inert dead code |
| **—** | No runtime bug; all hardware & RGBDS constructs verified correct | Hardware / RGBDS / MANUAL | — |

**Audit areas now covered (six):**
1. README.md (audit #1)
2. PIRATE_GAME_PLAN.md & PIRATE_LORE.md (audit #2)
3. Internal-consistency / lint vs asm (audit #3)
4. MANUAL.md audit *(new)*
5. Hardware-correctness audit *(new)*
6. RGBDS-correctness audit *(new)*

---

## P0 — Must fix (1 item)

### README.md:65 — ROM size is wrong
README states the output ROM is **32 KiB**; the actual built file is
**65,536 bytes = 64 KiB**, the header byte `$0148 = $01` (64 KiB), and
`tests/test_sgb.py:21` asserts `len(rom) == 65536`. The discrepancy is real and
player-facing (the SGB border art occupies ROMX banks 1–2, forcing the larger
size; everything else fits in ROM0).

**Action:**
```diff
-Output: `pirates_folly.gb` (32 KiB, MBC5+RAM+BATTERY) plus `build/` artifacts
+Output: `pirates_folly.gb` (64 KiB, MBC5+RAM+BATTERY) plus `build/` artifacts
```
*(Verifiable: `stat -c %s pirates_folly.gb` → `65536`; `od -An -tx1 -j0x148 -N1` → `01`.)*

---

## P1 — Recommended (doc clarity, README controls table)

These are accurate-where-it-speaks nuances, not errors. The README is otherwise
correct; these are optional clarifications.

1. **B at sea is not "—"** (`README.md:33`). `sail.asm:286-289` → `LeaveSail`
   (`sail.asm:108-126`) jumps to `STATE_EDIT` and does **not** call `SaveGame`.
   This is a real data-loss trap: voyage progress since last dock is discarded.
   *Suggest: replace the bare "—" with "Quit to seed screen (unsaved)".*

2. **"A rolls a new voyage" doesn't randomize** (`README.md:36-37`). The A path
   (`main.asm:278-284`) calls `ComposeSeed`/`FoldSeed16`/`InitNewGame` and never
   `RandomizeSeed`. `RandomizeSeed` (`main.asm:502`) has **zero callers** — dead
   code. Default seed is `DEADBEEF` (`main.asm:113`).
   *Suggest: "A starts the voyage with the edited seed (not a random one)".*

3. **Pirate rate "~1 in 5"** (`README.md:40`). `combat.asm:81` `cp 48` = 48/256 =
   18.75% ≈ 1 in 5.33, not exactly 1 in 5. Trivial rounding; the code's own
   comment says "~19%".
   *Suggest: soften "~1 in 5" → "~1 in 5 (≈19%)".*

---

## P2 — Housekeeping (inert; safe to ignore)

Real observations from internal-consistency audit #3, confirmed in source, but
**ship-safe and cosmetic**.

- `GEN_BASE_CHANCE` / `GEN_CA_ITERS` / `GEN_SALT_LAND` (`defs.inc:120-122`) are
  referenced **only by `src/gen.asm`**, which is **not in the Makefile `SRC`
  list** (`Makefile:8`). Dead in the shipped ROM; `world.asm` uses pure value
  noise (no CA pass).
- `Makefile:15` makes every `.o` depend on `src/testmap.inc`, but `testmap.inc`
  is only `INCLUDE`d by the unbuilt `testmap.asm`. Stale but inert.

**Action (either):** remove the dead `GEN_*` constants and the `testmap.inc`
prerequisite, **or** delete `gen.asm` / `testmap.asm` / `testmap.inc` outright.
No build or test behavior changes either way.

---

## Reclassified — real observations, NOT shipped-game bugs

### Audit #2 (18 items): plan-vs-product drift, not defects
All 18 are **true** as statements about divergence from
`docs/PIRATE_GAME_PLAN.md` — but that document is an explicit pre-implementation
vision, not a shipped-game description. **The README does not repeat the plan's
overclaims**; it is accurate where it speaks. Confirmed present/absent in source:

- README:137 explicitly states "**32-bit seed, 16-bit fold**" — so the "seed
  effectively 16-bit" item is a divergence from the *plan* only, not a README
  inaccuracy. **Do not treat the README as wrong here.**
- README makes **no** claim of 256×256 world, 8 KiB fog, sea monsters,
  minidungeons, sail/cannon upgrades, wind, storm minigame, BGP fade,
  double-speed, LYC=LY, or 8×16 sprites. Verified in source:
  - World 16×16 cells (`defs.inc:108-109`: `WORLD_W=320`, `WORLD_H=288`);
    `wExplored ds 32` = 256 bits (`world.asm:50`). ✓
  - No `monster` / `maelstrom` / `TREASURE` strings anywhere (grep empty). ✓
  - `DigScene` (`isles.asm:363`) increments a fragment counter to 9; no
    interiors/screens. ✓
  - Noise is Q5.3 (`world.asm:86` `>>3`, `:222/:225` `and 7`), not plan's Q4.4. ✓
  - `HasPortHash` + `DistrictHasLand` (3-sample land check) only — no
    sea-route-to-edge check. ✓
  - Only ROM0 + `sgb_day.inc` BANK[1] + `sgb_night.inc` BANK[2]; no 16-bank
    layout. ✓
  - SGB border fully implemented (`sgb.asm`) despite the plan's cut-list — real
    scope creep vs plan, but the README correctly documents SGB border as
    shipped. ✓

**Classification: keep as "plan-vs-product drift."** The two with faint
player-facing flavor are **#6** (no port reachability guarantee — a port
district could theoretically be landlocked) and **#9** (dig gives a fragment
with no interior). Neither is a runtime bug; both are design-scope differences.

### Audit #3 items 3 & 4: downgrade to non-issue
- `lint_worlds.py:31` `tile()` collapses all `e≥205` to grass; `:34`
  `cell_has_land` full-scans vs asm's 3-sample `CHL_OFFSETS` (`isles.asm:146`).
  Both are **superset** checks — they can never false-flag a game-accepted
  isle, so no test verdict is affected. Factually true, but **safe by
  construction**; not actionable. (`test_regress.py` keeps the exact port.)

---

## Framing correction
Audit #2's table labels items 1–3 "Doc overstates reality" — accurate *for the
plan*. But audit #2 is scoped to `docs/PIRATE_GAME_PLAN.md & PIRATE_LORE.md`,
while audit #1 is scoped to `README.md`. The README is **not** implicated by
items 1–3, 5, 12, 13, 14, 15, 18 (it never makes those claims). **Keep the two
doc sets distinct when acting:** fix README:65 (and optionally the controls
notes); leave the plan as a historical design doc.

---

## Net actionable list
1. **README.md:65**: `32 KiB` → `64 KiB`. *(must-fix, done — applied)*
2. **Makefile:22 pattern rule**: add `src/text.inc` to the prerequisite list so
   the 4 objects that `INCLUDE` it (`main`, `isles`, `port`, `sail`) rebuild on
   edits. *(must-fix, build hygiene — NEW from RGBDS audit)*
3. *(optional, doc-clarity)* README controls table: note B-at-sea quits to the
   seed screen unsaved; clarify "A" starts the voyage with the edited seed (not
   random); soften "~1 in 5" → "~1 in 5 (≈19%)".
4. *(housekeeping, inert)* Remove dead `GEN_*` constants from `defs.inc` and the
   `testmap.inc` Makefile prerequisite, or delete `gen.asm`/`testmap.asm`/
   `testmap.inc` outright — purely cosmetic.
5. **No runtime code changes required.** No runtime bug was confirmed across any
   audit; all hardware and RGBDS constructs verified correct.

---

# Newly validated findings (audits #4–#6)

*Section appended after cross-validation of the MANUAL.md, hardware-correctness,
and RGBDS-correctness audits. All claims below were re-checked against source
with file:line evidence; the cross-validation verdict is **no false positives in
substantive claims, one minor non-material numerical inaccuracy**.*

## P0 — Must fix (1 item, build hygiene)

### Makefile:22 — pattern rule omits `src/text.inc` as a prerequisite
The object pattern rule lists `src/%.asm src/defs.inc src/testmap.inc
include/hardware.inc` but **not** `src/text.inc`. Yet `text.inc` is `INCLUDE`d by
**four built objects**: `src/main.asm:7`, `src/isles.asm:5`, `src/port.asm:6`,
`src/sail.asm:10`. Editing `text.inc` therefore **does not** rebuild those
objects — a stale-build / make-hygiene risk (not an RGBDS error).

Related (harmless, P2): `src/testmap.inc` is listed as a *universal* prerequisite
but is `INCLUDE`d only by `src/testmap.asm:5`, which is excluded from `SRC`
(`Makefile:7`). Over-dependency; inert.

**Action:**
```diff
-build/%.o: src/%.asm src/defs.inc src/testmap.inc include/hardware.inc
+build/%.o: src/%.asm src/defs.inc src/text.inc include/hardware.inc
```
*(Swapping the unused `testmap.inc` prereq for the actually-included `text.inc`
closes the gap. Alternatively keep both.)*

## P1 — Recommended (none from these audits)

No P1 items surfaced. All hardware-register usage and RGBDS idioms are correct.

## P2 — Housekeeping (cosmetic; safe to ignore)

- **Makefile `testmap.inc` over-dependency** (see above) — listed as a universal
  prereq but used only by the unbuilt `testmap.asm`. Already tracked under the
  internal-consistency audit's P2; restated here because the RGBDS audit
  re-confirmed it.

## Reclassified — non-issues (verified correct, no action)

### Hardware-correctness audit — all clean
1. **Header bytes**: `od` of ROM → `$0143=80, $0146=03, $0147=1b, $0148=01,
   $0149=03, $014B=33`. Manual SGB flag `$03` and old-licensee `$33` live at
   `src/main.asm:21,23`. Makefile `rgbfix -v -p 0xFF -t "PIRATES FOLLY" -c -m
   MBC5+RAM+BATTERY -r 3` matches. ✓
2. **Sections/banks**: `src/sail.asm:29` `SECTION "Shadow OAM", WRAM0, ALIGN[8]`;
   `src/sgb_day.inc:2` `BANK[1]`, `src/sgb_night.inc:2` `BANK[2]`;
   `src/sgb.asm:136,140` `BANK(sgb_day_tiles)`/`BANK(sgb_night_tiles)`; ASSERTs at
   `src/sgb_day.inc:640-641` and `src/sgb_night.inc:640-641`. Map file confirms
   ROM0 bank #0 (code) + ROMX banks #1–#2 (SGB borders). ✓
3. **HRAM DMA copy**: `src/sail.asm:33` `hOamDma:: ds 10`; `src/sail.asm:35-45`
   `RunDmaROM`; `src/main.asm:88-96` copies via `ld b, RunDmaROM.end -
   RunDmaROM`. ✓
4. **Gfx `dw` literals**: `src/tiles.asm:99+`. ✓
5. **No `INCBIN`**: `grep -rn INCBIN src/` → none. ✓
6. **Build is clean**: `make clean && make` → zero warnings/errors; output
   `pirates_folly.gb` = 65,536 bytes (64 KiB). ✓
7. **Legacy files excluded**: `SRC` (`Makefile:7`) omits `gen.asm`/`testmap.asm`;
   both exist but aren't built. ✓
8. **text.inc charmap coverage**: files not including `text.inc` (combat, world,
   sound, sgb, tiles, rng, joypad) contain no `db "..."`. ✓

### RGBDS-correctness audit — all clean
1. **NEWCHARMAP**: `src/text.inc:4` `NEWCHARMAP pirates_folly` switches to the
   new map (`rgbds/man/rgbasm.5:710`), so no `SETCHARMAP` is needed. ✓
2. **DEF/EQU form**: 93 `DEF name EQU n` lines in `src/defs.inc`; no bare `EQU` /
   `=`. ✓
3. **No deprecated constructs**: the only `DATA`/`BSS` grep hits are section
   *name strings* (`"Default data"`, `"Tile data"` in `main.asm:562`,
   `tiles.asm:517`), not the deprecated section types. No `ldio` /
   `GBASMASSERT` / `HOME` / `CODE` section types. ✓
4. **REPT/ENDR**: all `REPT`/`ENDR` blocks are paired with constant counts; no
   `FOR` or `MACRO` misuse. ✓

### MANUAL.md audit — consistent with shipped ROM
MANUAL.md (player-facing manual) was checked against the shipped game behavior
and the README. No player-facing inaccuracies beyond those already tracked
under the README P1 doc-clarity items (B-at-sea unsaved, A-rolls-edited-seed,
~1-in-5 rounding). No new actionable items.

## Cross-validation note — one minor inaccuracy (non-material)

- The audit states "~40 unrolled multiply/shift loops". Actual `REPT` block
  count across built sources: combat=24, port=5, rng=4, sail=11, world=18 →
  **62** `REPT` blocks (all paired, all constant counts). The figure is
  understated, but the conclusion (all valid, correctly paired, no `FOR`/
  `MACRO`) is fully correct. **No action needed.**

### Cross-validation conclusion
The three new audits are solid. The single actionable item — **Makefile missing
`src/text.inc` as a prerequisite** for the 4 objects that include it — is real
and correctly characterized as a make-hygiene/stale-build risk (not an RGBDS
error). All other claims survive source verification. No false positives to
remove.

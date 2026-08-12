# RGBDS — Complete Reference

Synthesized from the full RGBDS documentation set (man pages `rgbds(7)`, `rgbds(5)`, `rgbasm(1)`, `rgbasm(5)`, `rgblink(1)`, `rgblink(5)`, `rgbfix(1)`, `rgbgfx(1)`, `gbz80(7)`), source: `./rgbds/man/`.

---

## Table of Contents

1. [Overview & Pipeline](#1-overview--pipeline)
2. [rgbasm — Assembler CLI](#2-rgbasm--assembler-cli)
3. [Assembly Language Syntax](#3-assembly-language-syntax)
4. [Expressions](#4-expressions)
5. [Character Maps](#5-character-maps)
6. [Sections](#6-sections)
7. [Symbols](#7-symbols)
8. [Defining Data](#8-defining-data)
9. [The Macro Language](#9-the-macro-language)
10. [Flow Control: REPT/FOR/IF/INCLUDE](#10-flow-control)
11. [Diagnostics, Assertions & Options](#11-diagnostics-assertions--options)
12. [rgblink — Linker](#12-rgblink--linker)
13. [Linker Scripts](#13-linker-scripts)
14. [rgbfix — Header & Checksum Fixer](#14-rgbfix--header--checksum-fixer)
15. [rgbgfx — Graphics Converter](#15-rgbgfx--graphics-converter)
16. [gbz80 Instruction Set Notes](#16-gbz80-instruction-set-notes)
17. [Object File Format (rgbds(5))](#17-object-file-format)
18. [Build Workflows & Recipes](#18-build-workflows--recipes)

---

## 1. Overview & Pipeline

**RGBDS** (Rednex Game Boy Development System) is the standard Game Boy assembler toolchain. Four tools:

| Tool | Role |
|---|---|
| **rgbasm** | Assembler: `.asm` source → RGB object file (`.o`) |
| **rgblink** | Linker: object files → raw ROM image |
| **rgbfix** | Fixes ROM header (logo, checksums, MBC type, padding) |
| **rgbgfx** | PNG ↔ Game Boy 2bpp/1bpp tile data, tilemaps, attrmaps, palettes |

Minimal pipeline:

```bash
rgbasm -o game.o game.asm
rgblink -o game.gb game.o
rgbfix -v -p 0xFF game.gb
```

One-shot pipeline version (no intermediate files):

```bash
(rgbasm -o - - | rgblink -o - - | rgbfix -v -p 0) < game.asm > game.gb
```

**History**: xAsm/xLink/RGBFix by Carsten Sørensen (1996) → ASMotor (1997) → RGBDS by Justin Lloyd (1999) → rgbds-linux (2009) → Bentley's fork became reference (2010) → RGBGFX integrated (2016) → gbdev org (2020) → v1.0.0 with semver (2025). MIT licensed.

**Common CLI conventions** (all four tools):
- Short and long options (`-V` / `--version`); later options override earlier ones; unambiguous abbreviations allowed.
- `-` as a filename means stdin/stdout (use `./-` for a literal file named `-`).
- Numeric args accept decimal, `$`/`0x` hex, `&`/`0o` octal, `%`/`0b` binary; underscores allowed as digit separators.
- `@file` reads more options from an at-file (whitespace/newline separated, `#` comments, no shell expansion). `--` stops option processing.
- `-B` configures error backtraces (depth limit, `all`/`no-all` for quieted locations, `collapse`).
- `--color always|never|auto` (auto respects `NO_COLOR`/`FORCE_COLOR`/TTY).
- `-v` increases verbosity (up to 6 levels); verbose output is for humans, not scripts.
- Warnings: `-W<flag>`, `-Wno-<flag>`, `-Werror[=flag]`, meta-flags `-Wall`, `-Wextra` (rgbasm only), `-Weverything`. More specific flags beat meta-flags; later position wins ties.

---

## 2. rgbasm — Assembler CLI

```
rgbasm [options] asmfile
```

| Option | Meaning |
|---|---|
| `-o out` | Output object file |
| `-I path` | Add include path (searched by `INCLUDE`, `INCBIN`, `READFILE`, in order given) |
| `-P file` | Pre-include file (as if `INCLUDE`d before the source); repeatable |
| `-D name[=value]` | Define string symbol (`name EQUS "value"`, default `"1"`) |
| `-E` | Export **all** labels, including unreferenced/local |
| `-p value` | Pad value for `DS` in ROM sections (default 0x00) |
| `-Q precision` | Fixed-point fractional bits (default 16 → Q16.16; `.16` notation accepted) |
| `-r depth` | Recursion depth limit for macro/EQUS expansion before assuming infinite loop (default 64) |
| `-X max_errors` | Abort after N errors (default 100 on TTY, 0 otherwise; 0 = unlimited) |
| `-b chars` | Extra two chars for binary literals (besides 0/1) |
| `-g chars` | Extra four chars for gfx literals (besides 0–3) |
| `-w` | Disable all warnings |
| `-M file` | Write make(1) dependency file |
| `-MG` | Missing includes treated as auto-generated deps (with `-M`) |
| `-MC` | Implies `-MG`; continue past missing deps |
| `-MP` | Add phony targets for each dep |
| `-MT`/`-MQ target` | Add dep-rule target (`-MQ` escapes `$` for make) |
| `-s features:file` | Dump final assembler state: `equ`, `var`, `equs`, `char`, `macro`, or `all`; repeatable |

Notable warning flags (`-W`): `assert`, `backwards-for`(all), `builtin-args`(all), `charmap-redef`(all), `div`, `empty-data-directive`(all), `empty-macro-arg`(extra), `empty-strrpl`(all), `export-undefined`(all), `large-constant`, `macro-shift`(extra), `nested-comment`, `obsolete`, `numeric-string=0/1/2`, `purge=0/1/2`, `shift`, `shift-amount`, `truncation=0/1/2`, `unmapped-char=0/1/2`, `unmatched-directive`(extra), `unterminated-load`(extra), `user`.

---

## 3. Assembly Language Syntax

Line-based. Two line forms:

```
[label:] [directive] [; comment]
[label:] [instruction [:: instruction ...]] [; comment]
```

- Labels before most directives, but **not** before `IF/ELIF/ELSE/ENDC/REPT/FOR/ENDR/MACRO/ENDM`.
- `::` separates multiple instructions or data directives on one line.
- `;` inline comment; `/* ... */` block comment (cannot nest).
- `\` at end of line = line continuation (before any comment).
- Keywords are **case-insensitive**; identifiers are **case-sensitive**.
- `HIGH(HL)`/`LOW(HL)` can stand in for `H`/`L` where an `r8` is expected (except `LOW(AF)`).
- `!cc` means the opposite condition (`!nz` = `z`).

### Symbol interpolation

`{symbol}` pastes a symbol's contents into the source: strings as-is; numbers as `$`-prefixed hex. Nests (`{{meaning}}`). Works even in non-expanding contexts like `DEF {name} = ...`.

**Print formats**: `{fmt:symbol}` with parts `<sign><exact><align><pad><width><frac><prec><type>`:
- sign `+`/space; exact `#` (base prefix / `q` suffix / escapes); align `-`; pad `0`; width digits; frac `.N` digits; prec `qN`; **type**: `d u x X b o f s`.

```rgbasm
PRINTLN "{#05b:X} + {#x:Y} == {d:SUM}"
```

---

## 4. Expressions

Numeric expressions: **signed 32-bit math**. Zero = false, anything else = true. "Constant" = known at assembly time (labels usually aren't — resolved by the linker). Directives like `REPT`/`IF` require constants.

### Numeric literals

| Format | Syntax |
|---|---|
| Decimal | `123` |
| Hex | `$1A`, `0x1A` |
| Octal | `&52`, `0o52` |
| Binary | `%1010`, `0b1010` |
| Fixed-point | `1234.56789` |
| Precise fixed-point | `12.34q8` (explicit Q precision) |
| Character | `'A'` (via current charmap) |
| GB gfx literal | `` `01012323 `` → the 2 tile-data bytes for that pixel row (e.g. `` `01012323 `` = `$0F55`) |

Underscores as separators: `123_456`, `%1100_1001`.

### Operators (high → low precedence)

| Ops | Meaning |
|---|---|
| `( )`, `FUNC()` | Grouping, built-in call |
| `**` | Exponentiation (only **right-associative** op) |
| `+ - ~ !` | Unary |
| `* / %` | Mul, div (floor), mod (sign of divisor; `x/y*y + x%y == x`) |
| `<< >> >>>` | Shifts (sign-extended / zero-extended right) |
| `& \| ^` | Bitwise |
| `+ -` | Add/sub |
| `== != < > <= >=` | Comparisons → 0/1 |
| `&& \|\|` | Boolean (both operands always evaluated!) |

Constancy rules: `&&`/`&` with a constant-0 operand is constant 0; `||` with nonzero constant is constant 1; `!x` on any non-constant with known nonzero bits is 0.

### Integer functions

- `HIGH(n)` = `(n & $FF00) >> 8`; `LOW(n)` = `n & $FF`
- `BITWIDTH(n)` — bits to represent n (→ floor/ceil log2, clz idioms)
- `TZCOUNT(n)` — trailing zeros (ctz). `TZCOUNT(1.0)` = current fixed-point precision.

### Fixed-point

Default Q16.16 (change with `-Q`/`OPT Q`; per-literal `q` suffix). Int↔fixed: `x * 1.0` / `x / 1.0` or shifts. Functions (optional trailing precision arg): `DIV MUL FMOD POW LOG ROUND CEIL FLOOR SIN COS TAN ASIN ACOS ATAN ATAN2`. Trig uses **turns** (1.0 = full circle). Mixed int/fixed ops are allowed but precision is unchecked — garbage in, garbage out. `FMOD` takes the dividend's sign (opposite of `%`).

Table generation example:

```rgbasm
FOR angle, 0.0, 0.5, 0.5 / 128
    db MUL(SIN(angle) + 1.0, 128.0 / 2) / 1.0
ENDR
```

### String expressions

- Literals in double quotes; triple-quoted `"""..."""` multi-line; `#"..."` raw strings (no escapes/interpolation).
- Escapes: `\\ \" \' \{ \} \n \r \t \0`.
- `++` concatenates; `===` / `!==` compare strings.
- String→string: `STRCAT STRUPR STRLWR STRSLICE(str,start[,stop]) STRRPL STRFMT STRCHAR REVCHAR READFILE(name[,max])`.
- String→int: `STRLEN STRCMP STRFIND STRRFIND BYTELEN STRBYTE INCHARMAP CHARLEN CHARCMP CHARSIZE CHARVAL`.
- Indexes: 0-based from start, −1-based from end.

---

## 5. Character Maps

Map text to arbitrary byte sequences (GB text isn't ASCII):

```rgbasm
CHARMAP "A", 42
CHARMAP ":)", 39          ; multi-char keys OK
CHARMAP "<br>", 13, 10   ; multi-value OK
CHARMAP '€', $20ac
```

Longest match wins; unmapped chars pass through as source-encoded bytes. `'c'` literals use the charmap too.

Multiple charmaps + stack:
- `NEWCHARMAP name[, basename]` — create (optionally copied), switch to it.
- `SETCHARMAP name`, `PUSHC [name]`, `POPC`.
- Initial map is `main`. Modifications apply from that point on.

---

## 6. Sections

```
SECTION "name", TYPE
SECTION "name", TYPE[addr]
SECTION "name", TYPE[addr], BANK[n], ALIGN[bits, ofs]
```

| Type | Range | Banks | Notes |
|---|---|---|---|
| `ROM0` | $0000–$3FFF | 0 | ($0000–$7FFF with `rgblink -t`) |
| `ROMX` | $4000–$7FFF | 1–N | banked ROM |
| `VRAM` | $8000–$9FFF | 0–1 | bank 1 CGB-only (prohibited by `-d`) |
| `SRAM` | $A000–$BFFF | 0–N | cart RAM |
| `WRAM0` | $C000–$CFFF | 0 | (to $DFFF with `-w`) |
| `WRAMX` | $D000–$DFFF | 1–7 | CGB banked WRAM |
| `OAM` | $FE00–$FE9F | — | |
| `HRAM` | $FF80–$FFFE | — | |

- Only `ROM0`/`ROMX` produce ROM bytes; RAM sections only allocate labels.
- Omitting `[addr]` = "floating" (linker picks); omitting `BANK[]` = linker picks. `ALIGN[align, ofs]`: address's low `align` bits = `ofs`.
- Section names must be globally unique (unless unionized/fragments).
- `ENDSECTION` ends the current section without starting another.

### Section stack

`PUSHS` / `POPS` save & restore section context. `PUSHS "name", TYPE...` pushes + opens a new section in one step.

### LOAD blocks (RAM code)

Store code in ROM, execute from RAM, with labels resolved to the **RAM** addresses:

```rgbasm
SECTION "LOAD example", ROMX
CopyCode:
    ld de, RAMCode            ; ROM location
    ld hl, RAMLocation        ; RAM location
    ld c, RAMCode.end - RAMCode
.loop
    ld a, [de] :: inc de :: ld [hli], a :: dec c
    jr nz, .loop
    ret
RAMCode:
  LOAD "RAM code", WRAM0
RAMLocation:
    ; ... code assembled for WRAM addresses ...
  ENDL
.end
```

No nesting; no section changes inside; ended by `ENDL`, `SECTION`, `ENDSECTION`, or `POPS`. Can be `UNION`/`FRAGMENT`.

### Unionized sections

`SECTION "name", WRAM0, UNION` — same-named declarations (across files too) **overlay** each other instead of erroring. All declarations must share type; constraints must be compatible; size = largest declaration. Not allowed for ROM types. For cross-file shared scratch RAM.

### Section fragments

`SECTION "name", ROMX, FRAGMENT` — same-named declarations **concatenate** (linker order = object-file order on the command line). Same type/compatible-constraint rules.

### Fragment literals

Inline anonymous fragments with `[[ ... ]]`, usable anywhere a 16-bit constant (or `DW` item) is expected; evaluates to the fragment's address:

```rgbasm
    ld hl, [[ db "left\0" ]]
    call [[ ld de, $1003 :: jp Print ]]
```

Parent section becomes a FRAGMENT; literals nest arbitrarily.

---

## 7. Symbols

Names: letters, digits, `_ # $ @`, start with letter/underscore; labels may contain one `.`. `#name` = raw identifier (escapes keyword collision).

### Labels

- `Name:` defines; `Name::` defines + exports. Local labels contain a dot (`.loop`); shorthand `.x` = current scope `.x`. Scope set by last global label. Defining a local label may omit the colon.
- Evaluate to address (bank via `BANK()`); constant only if section address is fixed. Difference of two labels in the same section is always computable.

### Anonymous labels

`:` alone; referenced as `:+` (next), `:-` (previous), `:++`, `:--`, etc. Independent of scoping.

### Variables & constants

| Form | Kind | Redefinable |
|---|---|---|
| `DEF x = n` | Variable | Yes (compound ops `+= -= *= /= %= <<= >>= &= \|= ^=`) |
| `DEF x EQU n` | Numeric constant | No (use `REDEF`) |
| `DEF x RB/RW/RL n` | Offset constant (RS group) | No |
| `DEF x EQUS "..."` | String constant | No (use `REDEF`); **auto-expanded** at use sites |

RS group for struct offsets:

```rgbasm
    RSRESET
DEF str_pStuff RW 1    ; offset 0, _RS += 2
DEF str_tData  RB 256  ; offset 2
DEF str_bCount RB 1    ; offset 258
DEF str_SIZEOF RB 0    ; 259
```

(`RSSET n`, `RSRESET`; arg defaults to 1.)

EQUS expansion is disabled in name positions (`DEF(name)`, `DEF x EQU ...`, `FOR x`, `PURGE x`, `MACRO x`) and for `#raw` names. Recursive expansion depth-limited by `-r`.

### Export / import / purge

- `EXPORT sym1, sym2` — or `::` on labels, `EXPORT DEF/REDEF` for constants. Import is automatic on unknown symbols.
- `PURGE sym` removes a symbol entirely. Dangerous for referenced/exported symbols; purging labels is discouraged. EQUS not expanded in `PURGE` names.

### Predeclared symbols

| Symbol | Type | Contents |
|---|---|---|
| `@` | EQU | Current PC |
| `.` / `..` / `__SCOPE__` | EQUS | Current global / local / innermost label scope |
| `_RS` | var | RS counter |
| `_NARG` | EQU | Macro arg count (updated by `SHIFT`) |
| `__ISO_8601_LOCAL__`, `__ISO_8601_UTC__` | EQUS | Build timestamps |
| `__UTC_YEAR__` … `__UTC_SECOND__` | EQU | Build time fields |
| `__RGBDS_MAJOR__/__MINOR__/__PATCH__/__RC__` | EQU | Version |
| `__RGBDS_VERSION__` | EQUS | Version string |

Timestamps honor `SOURCE_DATE_EPOCH` for reproducible builds.

### Introspection functions

`DEF(sym)` (defined?), `ISCONST(arg)`, `BANK(@|"section"|label)`, `SECTION(sym)`, `SIZEOF("sect"|TYPE|reg)`, `STARTOF("sect"|TYPE)`.

---

## 8. Defining Data

| Directive | Meaning |
|---|---|
| `DB a, b, "str"` | Bytes (strings via charmap) |
| `DW w, ...` | 16-bit little-endian |
| `DL l, ...` | 32-bit little-endian |
| `DS n[, v...]` | Reserve n bytes, optionally filled with repeating values |
| `INCBIN "file"[, start[, len]]` | Raw binary include (searches `-I` paths) |
| `ALIGN align[, ofs]` | Mid-section alignment constraint |
| `DS ALIGN[align, ofs]` | Skip bytes until aligned |

- `DB`/`DW`/`DL` **without args** = reserve 1/2/4 bytes — the way to allocate in RAM sections (with labels).
- Strings in `DW`/`DL` are split per character unless parenthesized.
- ROM `DS` fill = `-p` pad value (unless overlay linking with `-O`).

### Unions (overlapping RAM)

```rgbasm
UNION
    wName:: ds 10
    wNickname:: ds 10
NEXTU
    wHealth:: dw
    wLives:: db
    ds 7
    wBonus:: db
ENDU
```

`NEXTU` resets PC to the union start; total size = largest block. Nestable; only space-allocating directives inside.

---

## 9. The Macro Language

```rgbasm
MACRO my_macro
    ld a, 80
    call MyFunc
ENDM
```

Invoked by name + comma-separated args. Arguments are **textual substitutions**, not evaluated expressions — parenthesize them in numeric contexts (`\1 * 3` with arg `1 + 2` expands to `1 + 2 * 3`).

Argument references:
- `\1`–`\9`, and `\<n>` for any index (negatives count from the end; expressions like `\<_NARG>`, `\<-1>`, even nested `\<\1>`).
- `\#` = all args, comma-separated.
- `\@` = unique per-invocation symbol suffix (gensym) — also unique per `REPT`/`FOR` iteration.
- In arg lists: `\,` literal comma; `\(` `\)` literal parens; parens group; quotes work normally.

`SHIFT [n]` renumbers args left by n (negative = right); `_NARG` tracks the count. Idiom: `REPT _NARG ... SHIFT ... ENDR` iterates over all args.

Macro definitions can't nest directly — workaround: define the inner macro via an `EQUS` string containing `MACRO...ENDM`.

---

## 10. Flow Control

### REPT / FOR

```rgbasm
REPT 4
    add a, c
ENDR

FOR N, 256          ; N = 0..255
    dw N * N
ENDR
FOR V, start, stop, step   ; half-open [start, stop)
```

- `REPT` count must be constant. `FOR` assigns a fresh variable each iteration (body writes to it are overwritten).
- `\@` works inside both; both nest; `BREAK` exits the loop early.
- `-Wbackwards-for` warns when start/stop don't match step direction.

### IF / ELIF / ELSE / ENDC

Condition must be constant. Nestable. `ELIF` blocks after `ELSE` are ignored; only the first `ELSE` counts.

### INCLUDE

`INCLUDE "file"` — textual include, searches cwd then `-I` paths. Nestable. (`INCLUDE?` = quiet in backtraces.)

---

## 11. Diagnostics, Assertions & Options

- `PRINT args...` (numbers as `$HEX`), `PRINTLN` (trailing newline). Use `STRFMT`/`{fmt:}` for other formats.
- `WARN "msg"` — warning, continues. `FAIL "msg"` — error, stops assembly.
- `ASSERT expr[, "msg"]` — evaluated by rgbasm if constant, else deferred to rgblink.
- `STATIC_ASSERT expr[, "msg"]` — rgbasm-only; errors if not constant.
- Severity override as first arg: `ASSERT WARN|FAIL|FATAL, expr[, msg]`.

### OPT — changing options mid-source

`OPT` can modify `b, g, p, Q, r, W` options:

```rgbasm
PUSHO
    OPT g.oOX, Wdiv      ; like `-g.oOX -Wdiv`
    DW `..ooOOXX
POPO
```

`PUSHO`/`POPO` = option stack; `PUSHO` can also take options directly.

### Quiet backtraces

Append `?` to `REPT?`, `FOR?`, `MACRO?`, `INCLUDE?`, or a macro invocation (`lb? hl, 1, 2`) to hide those locations from error backtraces. (`-B all` overrides.)

---

## 12. rgblink — Linker

```
rgblink [options] file.o ...
```

| Option | Meaning |
|---|---|
| `-o out` | ROM output |
| `-m file` | Map file (section/symbol placement) |
| `-M` | Map file: sections only, no symbols |
| `-n file` | Symbol file (`bank:addr` per line; for emulators/debuggers) |
| `-l script` | Linker script |
| `-O overlay` | Overlay sections onto an existing ROM image (all sections must be fully fixed; gaps filled from overlay) — for ROM patches |
| `-p val` | Padding value between sections (default 0) |
| `-t` | Tiny mode: ROM0 spans full 32 KiB; ROMX→ROM0 (bank-1-fixed ROMX only) |
| `-w` | WRAM0 spans 8 KiB; WRAMX→WRAM0 |
| `-d` | DMG mode: implies `-w`, also forbids VRAM bank 1 |
| `-x` | No end-of-file padding (implies `-t`; not a substitute for `rgbfix -p`) |
| `-S spec` | Scramble section placement (below) |

**Placement**: first-fit bin-packing heuristic, minimizing banks used. No guarantees beyond explicit constraints (bank/address/alignment).

**Scrambling** (`-S romx=64,wramx,sram=4`): spreads sections across a pool of banks to *catch broken bank assumptions* — use in CI to prove code doesn't rely on incidental co-placement. Regions: `romx` (max 65535), `sram` (max 255), `wramx` (max 7, default = max; ignored with `-w`/`-d`). Size 0 disables.

---

## 13. Linker Scripts

Centralized section placement (one script per rgblink run; `INCLUDE "path"` splits it). `;` comments; case-insensitive keywords.

```
ROMX $F                 ; select bank (type + number)
  "Some functions"      ; place section at current address
  ALIGN 8               ; advance current address to alignment
  "Some \"array\""

WRAMX 2
  org $d123             ; set current address (forward only)
  "Some variables"

ROMX FLOATING           ; type fixed, bank floating
  "Some data" OPTIONAL  ; OK if absent from object files
  ds $100               ; skip (gap stays allocatable)
```

- Bank number omittable for single-bank types (ROM0, WRAM0, OAM, HRAM; ROMX with `-t`; VRAM with `-d`; WRAMX with `-w`). SRAM always needs a number.
- Switching banks restores that bank's last current address.
- Script constraints must be consistent with the objects'.

---

## 14. rgbfix — Header & Checksum Fixer

```
rgbfix [options] file.gb ...
```

Modifies in place (or `-o out`). Only touches fields you specify.

| Option | Header field |
|---|---|
| `-v` / `--validate` | = `-f lhg` (fix logo + header checksum + global checksum) |
| `-f spec` | Per-item: `l` logo, `h` header checksum, `g` global checksum; uppercase = **trash** (binary inverse) |
| `-p val` | Pad ROM to valid size (32 KiB × 2ⁿ), sets size byte $148. **Recommended: 0xFF** (faster flashing, no nop-slide into VRAM) |
| `-t str` | Title ($134–$143; max 11/15/16 chars depending on `-i`/`-c`/`-C`) |
| `-i str` | Game ID ($13F–$142, ≤4 chars) |
| `-c` / `-C` | CGB flag $80 (compatible) / $C0 (only) |
| `-s` | SGB flag $03 (needs `-l 0x33`!) |
| `-l id` | Old licensee ($14B) — use 0x33 for new software |
| `-k str` | New licensee ($144–$145, 2 chars) |
| `-m type` | MBC/cartridge type ($147) — number or name (`-m MBC5+RAM+BATTERY`; `-m help` lists) |
| `-r size` | RAM size byte ($149) |
| `-n ver` | ROM version ($14C) |
| `-j` | Non-Japanese ($14A = 1) |
| `-L file` | Custom 48-byte 1bpp logo (48×8 px source) |

Warnings: `mbc`, `obsolete`, `overwrite`, `sgb`, `truncation`.

TPP1 homebrew mapper supported: `-m TPP1_1.0+...` (region byte $14A repurposed; `-j` ignored with warning).

---

## 15. rgbgfx — Graphics Converter

PNG → GB native data (and back). Default: split into 8×8 tiles → 2bpp tile data.

| Option | Meaning |
|---|---|
| `-o file` | Tile data output (2bpp; `-d 1` = 1bpp) |
| `-t file` / `-T` | Tilemap output / auto path (`base.tilemap`) |
| `-a file` / `-A` | Attrmap output / auto (CGB format: flip bits, bank, palette) |
| `-p file` / `-P` | Palette output / auto (`base.pal`) |
| `-q file` / `-Q` | Palette map (for >8 palettes; attrmap holds only 3 bits) |
| `-O` | Base auto paths on `-o` path instead of input path |
| `-u` | Deduplicate identical tiles (tile order not guaranteed) |
| `-m` (= `-XY`) | Deduplicate mirrored tiles too (records flips in attrmap) |
| `-X` / `-Y` | Mirror-dedupe on one axis only |
| `-Z` | Column-major traversal order |
| `-x n` | Trim last n tiles from output (after dedupe; `-Wtrim-nonempty`) |
| `-N n[,m]` | Max tiles per VRAM bank (0–256); enables bank bit in attrmap |
| `-n n` | Max palettes (≤256) |
| `-s n` | Colors per palette |
| `-b id[,id]` | Base tile IDs (bank 0, bank 1) for tilemap |
| `-l id` | Base palette ID for attrmap/palmap |
| `-B color` | Background color: all-bg tiles omitted (placeholders in maps) |
| `-L X,Y:W,H` | Process only a tile-rectangle slice of the image |
| `-i file` | Input tileset: share/force tiles from an existing .2bpp (pair with `-c gbc:…`) |
| `-c spec` | Palette spec: inline (`#fff,#0f0,...;` `#none` gaps), `embedded`, `dmg=E4`-style DMG mapping, `auto` (default), or `format:path` external |
| `-C` | Apply GBC color curve (colors look right on real hardware) |
| `-d 1\|2` | Bit depth |
| `-r width` | **Reverse mode**: GB data → PNG (0 = square-ish). Pass the same flags used for generation! |
| `@file` | Per-image flag files — keep flags next to assets |

Palette spec file formats: `act`, `aco`, `gbc` (rgbgfx `-p` dump), `gpl`, `hex`, `png`, `psp`.

**Palette generation** (when `-c` not given): any transparent pixel → color 0 of all palettes. Sorting: indexed PNG's internal order (deprecated), else exact-grayscale bins (darkest→color 0, = `dmg=E4`), else luminance (0.2126R+0.7152G+0.0722B), lightest first. Pagination is NP-complete; heuristic used. **If palette order matters (palette swaps!), always specify `-c` explicitly.**

**Output formats**: tile data = VRAM dump, 16 bytes/tile (8 with `-d 1`); palettes = little-endian RGB555, empty colors = 0xFFFF; tilemap/attrmap = 1 byte per tile, row-major (or column-major with `-Z`).

Typical asset pipeline:

```bash
rgbgfx tileset.png -o tileset.2bpp -O -P                          # tileset + palettes
rgbgfx level1.png -i tileset.2bpp -c gbc:tileset.pal \
       -t level1.tilemap -a level1.attrmap                      # level uses shared tiles
rgbgfx -u title.png -o title.2bpp -t title.tilemap              # deduped title screen
```

---

## 16. gbz80 Instruction Set Notes

gbz80(7) documents each instruction with **bytes** and **cycles in M-cycles** ("cycles at 1 MHz"; double in CGB double speed). Full semantics in `rgbds/man/gbz80.7`; opcode-level table in the companion `GAMEBOY_DEV_GUIDE.md` (§6).

Syntax conveniences accepted by rgbasm:

- ALU ops on A may omit the destination: `OR B` = `OR A, B`. `CPL A` = `CPL`.
- Memory bracket syntax: `LD [HLI],A` / `LD [HL+],A` / `LDI [HL],A` etc. all accepted; `LDH [C],A` = `LD [$FF00+C],A`.
- `JR Label` — you write the **target address**, rgbasm computes the signed offset (errors if out of −128..+127 range; `jr @` = infinite loop `18 FE`).
- `RST` accepts an expression; checked against valid vectors ($00…$38).
- `STOP n8` lets you override the default $00 second byte.
- `LD B,B` is a no-op but used by emulators as a **breakpoint** (BGB); `LD D,D` = debug message.
- Assembler emits checks via the linker: `ldh` operand range, `rst` vector validity, `bit/res/set` index 0–7 (see RPN opcodes $60–$62 below).
- `DAA` semantics (from gbz80(7)): after subtraction (N=1): adjustment = (H ? $06 : 0) + (C ? $60 : 0), subtracted from A. After addition: adjustment = (H or A&$F > 9 ? $06 : 0) + (C or A > $99 ? $60 : 0, setting C), added to A.

---

## 17. Object File Format

(rgbds(5), "RGB9" magic + revision.) For tool authors; summary:

- Header: magic, revision, symbol count, section count.
- **Source-file info nodes** (REPT/file/macro contexts, written in reverse order) — powers error backtraces.
- **Symbols**: name, type (local/import/export), definition context + line, section ID, value/offset.
- **Sections**: name, type (WRAM0/VRAM/ROMX/ROM0/HRAM/WRAMX/SRAM/OAM + union/fragment bits), size, fixed address/bank (or −1 = floating), alignment, and for ROM types: data + **patches**.
- **Patches**: location + PC context + type (byte, word LE, long LE, `jr`) + value as an **RPN expression** (evaluated by rgblink).
- **Assertions**: patch-like records with severity (warn/fail/fatal) + message.
- RPN opcodes: arithmetic/logic/comparison/shift ops; `BANK(symbol|section|@)`; `SIZEOF`/`STARTOF(section|type)`; `ldh`/`rst`/bit-index checks; `HIGH`/`LOW`/`BITWIDTH`/`TZCOUNT`; integer literals; symbol values.

This design is why rgbasm expressions involving labels "just work" — they're deferred to link time as RPN.

---

## 18. Build Workflows & Recipes

### Makefile sketch

```make
RGBASM  := rgbasm
RGBLINK := rgblink
RGBFIX  := rgbfix
RGBGFX  := rgbgfx

game.gb: main.o graphics.o audio.o
	$(RGBLINK) -o $@ -n game.sym -m game.map -p 0xFF $^
	$(RGBFIX) -v -p 0xFF -t MYGAME -m MBC5 -c $@

%.o: %.asm $(ASSETS)
	$(RGBASM) -o $@ -Wall -Wextra -I include/ -M $*.d -MG -MP -MQ $@ $<

%.2bpp: %.png
	$(RGBGFX) -o $@ $<

-include *.d
```

### Recommended practices

- `INCLUDE "hardware.inc"` for register names (https://github.com/gbdev/hardware.inc).
- Assemble with `-Wall -Wextra`; fix or explicitly disable warnings.
- `-S romx=N` scramble builds in CI to catch accidental same-bank assumptions.
- `ASSERT`/`STATIC_ASSERT` liberally: bank-matching for far calls, table sizes, alignment.
- Unionized WRAM sections for cross-module scratch memory; `UNION`/`NEXTU` for per-state structs.
- Keep one `SECTION "Header", ROM0[$100]` with `ds $150 - @, 0` and let rgbfix fill the header.
- Use `-p 0xFF` padding everywhere (rgblink + rgbfix).
- Version-stamp ROMs with `__RGBDS_VERSION__` / `__ISO_8601_LOCAL__` (and set `SOURCE_DATE_EPOCH` for reproducible builds).
- `-s all:state.asm` dumps the final symbol/macro/charmap state — useful for debugging macro-heavy code.
- rgbgfx at-files (`image.png.flags`) keep per-asset conversion flags next to the asset instead of in the Makefile.

### Documentation map (local)

| File | Contents |
|---|---|
| `rgbds/man/rgbasm.5` | Full assembly language |
| `rgbds/man/rgbasm.1` | Assembler CLI + warnings |
| `rgbds/man/rgblink.1` / `.5` | Linker CLI / linker script format |
| `rgbds/man/rgbfix.1` | Header fixer |
| `rgbds/man/rgbgfx.1` | Graphics converter |
| `rgbds/man/gbz80.7` | CPU instruction reference |
| `rgbds/man/rgbds.5` | Object file format |
| `rgbds/man/rgbds.7` | Overview, pipeline, history |
| `rgbds/man/rgbasm-old.5` | Legacy syntax (historical) |

Online: https://rgbds.gbdev.io/docs

# Game Boy Game Development — Complete Reference

Synthesized from: **Pan Docs** (gbdev.io/pandocs), the **GB CPU Manual v1.01** (DP), and **Awesome Game Boy Development** (gbdev/awesome-gbdev). Local copies live in `./pandocs`, `./pdfs/GBCPUman.pdf`, and `./awesome-gbdev`.

---

## Table of Contents

1. [Hardware Overview & Specifications](#1-hardware-overview--specifications)
2. [Toolchain & Ecosystem](#2-toolchain--ecosystem)
3. [Memory Map](#3-memory-map)
4. [The Cartridge Header](#4-the-cartridge-header)
5. [Cartridges & Memory Bank Controllers (MBCs)](#5-cartridges--memory-bank-controllers)
6. [CPU: Registers, Flags & Instruction Set](#6-cpu-registers-flags--instruction-set)
7. [Interrupts](#7-interrupts)
8. [Timer & Divider Registers](#8-timer--divider-registers)
9. [Graphics (PPU)](#9-graphics-ppu)
10. [Audio (APU)](#10-audio-apu)
11. [Joypad Input](#11-joypad-input)
12. [Serial Data Transfer (Link Cable)](#12-serial-data-transfer-link-cable)
13. [Game Boy Color Features](#13-game-boy-color-features)
14. [Super Game Boy](#14-super-game-boy)
15. [Power-Up Sequence & Console Detection](#15-power-up-sequence--console-detection)
16. [Power Management (HALT/STOP)](#16-power-management-haltstop)
17. [Hardware Bugs & Pitfalls](#17-hardware-bugs--pitfalls)
18. [Practical Game Development](#18-practical-game-development)
19. [Accessories](#19-accessories)
20. [Resources & Further Reading](#20-resources--further-reading)

---

## 1. Hardware Overview & Specifications

The Game Boy family:

| | DMG (1989) | MGB (Pocket) | SGB | CGB (Color) |
|---|---|---|---|---|
| CPU | 8-bit Sharp SM83 core ("8080-like"), all models | | | |
| Master clock | 4.194304 MHz | 4.194304 MHz | Derived from SNES (~2.4% fast on SGB1; SGB2 is correct) | 4.19 MHz, switchable to 8.388608 MHz (Double Speed) |
| System clock | 1/4 master clock (1.048576 MHz = 1 M-cycle ≈ 0.954 µs) | | | |
| Work RAM | 8 KiB | 8 KiB | 8 KiB | 32 KiB (4 + 7×4 KiB banked) |
| Video RAM | 8 KiB | 8 KiB | 8 KiB | 16 KiB (2×8 KiB banks) |
| Resolution | 160×144 | 160×144 | 160×144 in 256×224 SNES border | 160×144 |
| Objects (sprites) | 8×8 or 8×16; max 40/screen, **10/scanline** (all models) | | | |
| Palettes | BG: 1×4, OBJ: 2×3 | same | BG/OBJ: 1+4×3, border 4×15 | BG: 8×4, OBJ: 8×3 (15-bit RGB, 32768 colors) |
| Colors | 4 shades of green | 4 shades of gray | on TV | 15-bit RGB555 |
| Frame rate | 59.73 Hz (≈16.74 ms/frame, NOT exactly 60 Hz) | | ~61.1 Hz (SGB1) | 59.73 Hz |
| Sound | 4 channels, stereo | 4 ch. | 4 GB ch. + SNES audio | 4 ch., stereo |

**Timing fundamentals:**

- 1 **M-cycle** = 4 T-cycles ("dots" in PPU parlance) = 4/4.194304 MHz ≈ 0.954 µs (DMG, CGB normal speed).
- 1 **scanline** = 456 dots = 114 M-cycles.
- 1 **frame** = 154 scanlines = 70,224 dots ≈ 16.74 ms → 59.7275 fps.
- All CPU instruction times are multiples of 4 T-cycles (1 M-cycle). The CPU performs like a ~4 MHz Z80.
- In CGB Double Speed mode the CPU, timers/divider, serial port, and OAM DMA run twice as fast; the PPU, VRAM HDMA, and all APU timings/frequencies are unaffected. A "dot" is always a 2²² Hz unit.

---

## 2. Toolchain & Ecosystem

### Assemblers (ASM development)

- **RGBDS** (github.com/gbdev/rgbds) — the de-facto standard assembler/linker package (`rgbasm`, `rgblink`, `rgbfix`, `rgbgfx`). Docs: rgbds.gbdev.io.
- **ASMotor** — by the original RGBDS author.
- **wla-dx** — multi-platform cross-assembler.
- **hardware.inc** (github.com/gbdev/hardware.inc) — standard include file with symbolic names for every hardware register. Use it in every RGBDS project.

### C development

- **GBDK-2020** (github.com/gbdk-2020/gbdk-2020) — maintained C toolchain (SDCC-based) with compiler, assembler, linker, and libraries. Extensive API docs and examples.
- **ZGB** — game engine built on GBDK.
- **GB Studio** — drag-and-drop game creator (no coding).
- Experimental: Wiz (high-level asm), gbforth (Forth), Rust-GB, llvm/clang-gbz80.

### Emulators / debugging

- **BGB** — accurate emulation + excellent debugger (Windows/Wine).
- **SameBoy** — extremely accurate, powerful debugger (macOS/Linux).
- **Emulicious** — accurate, profiler, source-level debugging for ASM and C (VS Code adapter).
- **mGBA**, **Gambatte**, **Binjgb**, **Mooneye GB** (test-focused), **MetroBoy** (circuit-level simulation).

### Graphics & asset tools

- **RGBDS's rgbgfx** — converts PNG to 2bpp tile data/tilemaps/attrmaps/palettes (bundled with RGBDS).
- **Tilemap Studio**, **Game Boy Tile Designer (GBTD)** & **Map Builder (GBMB)** (Harry Mulder), **gimp-tilemap-gb** plugins, **png2gb**, **SuperFamiconv**, **bmp2cgb**.
- Online tile viewer/editor: huderlem.com/demos/gameboy2bpp.html.

### Music / sound

- **hUGETracker** + hUGEDriver — the modern standard tracker + driver.
- **GBT PLAYER**, **DevSoundX**, **GBSoundSystem** (Paragon 5), **Carillon**, **XPMCK** / **mmlgb** (MML), **CBT-FX** (SFX).

### Testing

- **Mooneye Test Suite**, **Blargg's tests**, **SameSuite**, **144p Test Suite** (video/audio calibration).
- **evunit** — unit testing for assembly.
- **romusage** — estimates free ROM space from map files.

### Learning

- **GB ASM Tutorial** (gbdev.io/gb-asm-tutorial) — step-by-step RGBDS course.
- **GBDK-2020 docs & examples**.
- Community: gbdev.io, GBDev Discord.

---

## 3. Memory Map

16-bit address bus. All addresses in hex.

| Start | End | Description | Notes |
|---|---|---|---|
| 0000 | 3FFF | 16 KiB ROM bank 00 | From cartridge, usually fixed |
| 4000 | 7FFF | 16 KiB ROM bank 01–NN | Switchable via MBC |
| 8000 | 9FFF | 8 KiB VRAM | CGB: bank 0/1 switchable (VBK) |
| A000 | BFFF | 8 KiB external (cartridge) RAM | Switchable bank if any |
| C000 | CFFF | 4 KiB WRAM (bank 0) | |
| D000 | DFFF | 4 KiB WRAM (bank 1) | CGB: switchable bank 1–7 (SVBK) |
| E000 | FDFF | Echo RAM (mirror of C000–DDFF) | Prohibited by Nintendo; don't use |
| FE00 | FE9F | OAM (object attribute memory) | 40 objects × 4 bytes |
| FEA0 | FEFF | Not usable | Returns $FF during OAM block; revision-dependent junk otherwise |
| FF00 | FF7F | I/O registers | |
| FF80 | FFFE | HRAM (High RAM) | Fast, only memory usable during OAM DMA |
| FFFF | FFFF | IE (Interrupt Enable) register | |

### I/O register ranges

| Range | Purpose |
|---|---|
| FF00 | Joypad (P1/JOYP) |
| FF01–FF02 | Serial transfer (SB, SC) |
| FF04–FF07 | Timer & divider (DIV, TIMA, TMA, TAC) |
| FF0F | Interrupt flag (IF) |
| FF10–FF26 | Audio (NR10–NR52) |
| FF30–FF3F | Wave pattern RAM |
| FF40–FF4B | LCD control/status/scroll/palettes |
| FF46 | OAM DMA |
| FF4C–FF4D | CGB: KEY0 (CPU mode), KEY1 (speed switch) |
| FF4F | CGB: VRAM bank select (VBK) |
| FF50 | Boot ROM mapping control (BANK) |
| FF51–FF55 | CGB: VRAM DMA (HDMA1–5) |
| FF56 | CGB: Infrared port (RP) |
| FF68–FF6B | CGB: BG/OBJ palette index+data |
| FF6C | CGB: Object priority mode (OPRI) |
| FF70 | CGB: WRAM bank select (SVBK) |

### VRAM layout (per 8 KiB bank)

- **8000–97FF**: tile data — 384 tiles × 16 bytes, conceptually three "blocks" of 128 tiles:
  - Block 0: 8000–87FF (tile IDs 0–127 in "$8000 addressing")
  - Block 1: 8800–8FFF (IDs 128–255 / −128 to −1)
  - Block 2: 9000–97FF (IDs 0–127 in "$8800 addressing")
  - Tile ID from address: `ID = (address / 16) mod 256`.
- **9800–9BFF** and **9C00–9FFF**: two 32×32-byte tile maps (each entry = 1 tile index). Map entry address bitfield: `1 0 0 1 1 T YYYYY XXXXX` (T = which map). In CGB bank 1 these hold the BG attribute maps instead.
- CGB VRAM bank 1 has the same layout; its tile area doubles tile storage to 768 tiles.

### Reserved areas in ROM bank 0

- **RST vectors**: $00, $08, $10, $18, $20, $28, $30, $38.
- **Interrupt vectors**: $40 (VBlank), $48 (STAT), $50 (Timer), $58 (Serial), $60 (Joypad).
- **Cartridge header**: $0100–$014F (see §4).
- Unused vector space may be repurposed if the corresponding features aren't used.

### Echo RAM (E000–FDFF)

Mirror of C000–DDFF (address bits wrap). Prohibited; some emulators/flashcarts behave differently. Don't use it.

### FEA0–FEFF

Prohibited. Reads during OAM block return $FF; on DMG/MGB/SGB reads during Mode 2 trigger the OAM corruption bug; otherwise revision-specific garbage.

---

## 4. The Cartridge Header

Located at **$0100–$014F**. `rgbfix` can generate/fix most of it automatically.

| Address | Field | Details |
|---|---|---|
| 0100–0103 | Entry point | Usually `nop` + `jp $0150`. Boot ROM jumps here. |
| 0104–0133 | **Nintendo logo** | Must match the 48-byte dump below or the boot ROM locks up |
| 0134–0143 | Title | Uppercase ASCII, $00-padded. 16 chars max (fewer if later fields used) |
| 013F–0142 | Manufacturer code | 4-char ASCII (newer carts); else part of title |
| 0143 | **CGB flag** | $80 = CGB-enhanced (backwards compatible); $C0 = CGB-only; $00 = DMG only. Bit 7 set → value written to KEY0 |
| 0144–0145 | New licensee code | 2 ASCII chars; only used if old licensee = $33. Use "00" for homebrew |
| 0146 | **SGB flag** | $03 = supports SGB functions; anything else = SGB ignores command packets |
| 0147 | **Cartridge type** | MBC/hardware code — see table below |
| 0148 | **ROM size** | Size = 32 KiB × (1 << value). $00=32K(2 banks), $01=64K(4), $02=128K(8), $03=256K(16), $04=512K(32), $05=1M(64), $06=2M(128), $07=4M(256), $08=8M(512) |
| 0149 | **RAM size** | $00=none, $02=8 KiB (1 bank), $03=32 KiB (4 banks), $04=128 KiB (16 banks), $05=64 KiB (8 banks). $01 is unused/invalid |
| 014A | Destination code | $00 = Japan, $01 = overseas |
| 014B | Old licensee code | $33 → use new licensee code instead. Must be $33 for SGB |
| 014C | Mask ROM version | Usually $00 |
| 014D | **Header checksum** | Verified by boot ROM; ROM locks up if wrong |
| 014E–014F | Global checksum | 16-bit big-endian sum of all ROM bytes (except these two). Not verified by hardware (only by Pokémon Stadium's GB Tower) |

### Nintendo logo bytes (0104–0133)

```
CE ED 66 66 CC 0D 00 0B 03 73 00 83 00 0C 00 0D
00 08 11 1F 88 89 00 0E DC CC 6E E6 DD DD D9 99
BB BB 67 63 6E 0E EC CC DD DC 99 9F BB B9 33 3E
```

CGB and later boot ROMs only verify the **first 24 bytes** (top half) of the logo.

### Header checksum (014D)

```c
uint8_t checksum = 0;
for (uint16_t addr = 0x0134; addr <= 0x014C; addr++)
    checksum = checksum - rom[addr] - 1;
```

### Cartridge type codes (0147)

| Code | Type | Code | Type |
|---|---|---|---|
| $00 | ROM ONLY | $13 | MBC3+RAM+BATTERY |
| $01 | MBC1 | $19 | MBC5 |
| $02 | MBC1+RAM | $1A | MBC5+RAM |
| $03 | MBC1+RAM+BATTERY | $1B | MBC5+RAM+BATTERY |
| $05 | MBC2 | $1C | MBC5+RUMBLE |
| $06 | MBC2+BATTERY | $1D | MBC5+RUMBLE+RAM |
| $08 | ROM+RAM (rare) | $1E | MBC5+RUMBLE+RAM+BATTERY |
| $09 | ROM+RAM+BATTERY (rare) | $20 | MBC6 |
| $0B–$0D | MMM01 (+RAM, +BATTERY) | $22 | MBC7+SENSOR+RUMBLE+RAM+BATTERY |
| $0F | MBC3+TIMER+BATTERY | $FC | POCKET CAMERA |
| $10 | MBC3+TIMER+RAM+BATTERY | $FD | BANDAI TAMA5 |
| $11 | MBC3 | $FE | HuC3 |
| $12 | MBC3+RAM | $FF | HuC1+RAM+BATTERY |

(MBC3 with 64 KiB SRAM = MBC30, used only by Japanese Pokémon Crystal.)

---

## 5. Cartridges & Memory Bank Controllers

The cartridge is an expansion board: ROM + optional RAM + an MBC chip that bank-switches the 0000–7FFF and A000–BFFF windows. **Writes to the ROM area (0000–7FFF) control the MBC registers.** Cartridge RAM is as fast as internal WRAM and is often battery-backed for saves.

**General best practices:**

- Enable RAM with `$0A` written to the RAM-enable range before use; **disable it afterwards** (write $00) to protect against corruption on power-down.
- On first run, validate SRAM with a known magic sequence before trusting save data (SRAM powers up random).
- Only **MBC5** is guaranteed to support CGB Double Speed timing.
- Selecting an out-of-range RAM bank wraps: `addr = ((a − $A000) + bank × $2000) % ram_size`.

### No MBC (ROM ONLY)

Games ≤ 32 KiB. ROM mapped directly at 0000–7FFF. Optionally 8 KiB RAM at A000–BFFF via a discrete logic decoder.

### MBC1 (max 2 MiB ROM / 32 KiB RAM)

Registers (all default $00 at power-up; ROM bank register treats $00 as $01):

| Range | Register |
|---|---|
| 0000–1FFF | RAM enable: write any value with low nibble = $A to enable, anything else disables |
| 2000–3FFF | ROM bank number (5 bits, $01–$1F; $00 → $01). For >5-bit banks, secondary register supplies bits 5–6 |
| 4000–5FFF | RAM bank number (2 bits, 32 KiB carts) **or** upper 2 bits of ROM bank (≥1 MiB carts) |
| 6000–7FFF | Banking mode select: 0 = simple (0000–3FFF fixed to bank 0, RAM fixed to bank 0); 1 = advanced (secondary register banks both the 0000–3FFF ROM region and RAM) |

Quirks:

- Bank $00 can never appear at 4000–7FFF via the main register ($00 → $01 translation). On ≤256 KiB ROMs you *can* map bank 0 by setting only the discarded 5th bit ($10 → bank $00 after masking).
- On large carts, banks $20/$40/$60 are unreachable at 4000–7FFF (the translation sees low 5 bits = 0 → maps $21/$41/$61); they are only reachable at 0000–3FFF in mode 1.
- **MBC1M** multi-game carts wire the secondary register to bank bits 4–5 and use mode 1 to switch between games (bank $10/$20/$30 bases). Identifiable by a Nintendo header in bank $10.

### MBC2 (max 256 KiB ROM, 512×4-bit built-in RAM)

- Built-in RAM: 512 nibbles at A000–A1FF (echoed 15× through BFFF). Only the low 4 bits of each byte are defined.
- One address range does double duty; **address bit 8** selects the function:
  - **Bit 8 = 0** (e.g. $0000–00FF, $0200–02FF…): RAM enable — low nibble $A enables, else disables.
  - **Bit 8 = 1** (e.g. $2100): ROM bank number (4 bits; $00 → $01; max 16 banks).

### MBC3 (+ RTC) (max 2 MiB ROM / 32 KiB RAM)

| Range | Register |
|---|---|
| 0000–1FFF | RAM & timer enable ($0A enables RAM **and** RTC registers) |
| 2000–3FFF | ROM bank number (7 bits, $01–$7F; $00 → $01). Banks $20/$40/$60 work fine (unlike MBC1) |
| 4000–5FFF | RAM bank $00–$07 select, **or** RTC register select $08–$0C |
| 6000–7FFF | Latch clock data: write $00 then $01 to snapshot the RTC into readable registers |

RTC registers (accessed at A000–BFFF when selected):

| Select | Name | Range |
|---|---|---|
| $08 | RTC S (seconds) | 0–59 |
| $09 | RTC M (minutes) | 0–59 |
| $0A | RTC H (hours) | 0–23 |
| $0B | RTC DL (day counter low) | 0–255 |
| $0C | RTC DH: bit 0 = day counter bit 8; bit 6 = Halt (1 = stop timer); bit 7 = day counter carry (set on overflow until cleared) | |

- Day counter: 9 bits, 0–511 days; carry bit set on overflow.
- Set the Halt flag before writing RTC registers.
- Wait 4 µs between separate RTC accesses.
- For >511-day spans, accumulate an offset in battery RAM each time a nonzero day count is read.
- **MBC30**: identical but 4 MiB ROM / 64 KiB RAM (Japanese Pokémon Crystal only).

### MBC5 (max 8 MiB ROM / 128 KiB RAM)

The simplest and most modern; guaranteed Double-Speed-safe.

| Range | Register |
|---|---|
| 0000–1FFF | RAM enable ($xA enables) |
| 2000–2FFF | ROM bank low 8 bits — **bank $00 really is bank $00** (no translation!) |
| 3000–3FFF | ROM bank 9th bit |
| 4000–5FFF | RAM bank number ($00–$0F) |

**Rumble carts**: bit 3 of the RAM bank register drives the rumble motor (1 = on). Vary intensity by pulsing it.

### MBC6 (Net de Get only)

Two independent 8 KiB ROM bank windows ($4000–5FFF bank A, $6000–7FFF bank B) and two 4 KiB RAM windows ($A000–AFFF, $B000–BFFF), plus an 8 Mbit Macronix flash chip for downloadable minigames. RAM enable at 0000–03FF; bank registers at 0400–0BFF; flash enable at 0C00–0FFF.

### MBC7 (Kirby Tilt 'n' Tumble)

2-axis ADXL202E accelerometer + 256-byte EEPROM (93LC56). A000–BFFF exposes 16 register slots (address bits 4–7):

- Ax0x: write $55 (erase latch); Ax1x: write $AA (latch accelerometer). Must erase before re-latching.
- Ax2x/Ax3x: accel X low/high (16-bit, centered ≈ $81D0, gravity ≈ $70/g). Lower = right.
- Ax4x/Ax5x: accel Y low/high. Lower = bottom.
- Ax8x: EEPROM access registers (slow bit-banged serial).
- **Don't HALT within 1.2 ms of latching** — HALT stops the PHI cartridge clock the sensor needs, adding noise.

### Other MBCs (brief)

- **MMM01**: complex MBC1 variant with mid-game remapping; used by a few Taito carts.
- **HuC1**: MBC1-like + IR port (used by some Hudson games).
- **HuC-3**: MBC + RTC + IR + speaker (Hudson).
- **M161**, **TAMA5** (Bandai, RTC + extra MCU), **Pocket Camera** (MBC-like with camera image RAM) — niche; see Pan Docs.

---

## 6. CPU: Registers, Flags & Instruction Set

The CPU is a Sharp **SM83**: an 8080/Z80 hybrid. All assemblers use Z80-style syntax. No IX/IY, no second register set, no IN/OUT (memory-mapped I/O instead), no ED/DD/FD prefixes.

### Registers

| 16-bit | Hi | Lo | Function |
|---|---|---|---|
| AF | A | F | Accumulator & flags |
| BC | B | C | General purpose |
| DE | D | E | General purpose |
| HL | H | L | General purpose / memory pointer |
| SP | — | — | Stack pointer (grows **downward**; init to top of RAM, e.g. $E000 or $D000) |
| PC | — | — | Program counter |

### Flags (F register, bits 7–4 only; low nibble always reads 0)

| Bit | Flag | Meaning |
|---|---|---|
| 7 | **Z** | Zero — set iff result is zero (or operands equal for CP) |
| 6 | **N** | Subtraction — set by subtract ops (BCD) |
| 5 | **H** | Half carry — carry out of bit 3 (BCD) |
| 4 | **C** | Carry — set when: 8-bit add > $FF; 16-bit add > $FFFF; subtraction/comparison borrows (A < operand, like Z80/x86, **unlike** 6502/ARM); rotate/shift shifts out a 1 |

N and H exist only for **DAA** (BCD adjust). DAA works only for 8-bit ops; it's ineffective for 16-bit arithmetic and limited for INC/DEC (which don't touch C).

### Instruction timing notation

Times below are **T-cycles / M-cycles**. Conditional instructions show `taken/not-taken`. Everything is a multiple of 1 M-cycle (4 T).

### Operand encodings

- `r8`: B=0, C=1, D=2, E=3, H=4, L=5, (HL)=6, A=7
- `r16`: BC=0, DE=1, HL=2, SP=3; `r16stk`: BC, DE, HL, AF; `r16mem`: (BC), (DE), (HL+), (HL−)
- `cond`: NZ=0, Z=1, NC=2, C=3
- `n`/`e` = following byte; `nn` = following 2 bytes little-endian. `e` is a **signed** offset.

### Complete instruction table

#### 8-bit loads

| Instruction | Opcode | Cycles (T) | Notes |
|---|---|---|---|
| LD r, n | B 06, C 0E, D 16, E 1E, H 26, L 2E, (HL) 36, A 3E | 8; (HL) 12 | |
| LD r, r' | 40–7F (exc. 76=HALT) | 4; 8 if either is (HL) | |
| LD A, (BC) / (DE) / (HL+) / (HL−) | 0A / 1A / 2A / 3A | 8 | (HL±) post-inc/dec HL |
| LD (BC), A / (DE), A / (HL+), A / (HL−), A | 02 / 12 / 22 / 32 | 8 | |
| LD A, (nn) | FA | 16 | |
| LD (nn), A | EA | 16 | |
| LDH A, (n) | F0 | 12 | reads $FF00+n |
| LDH (n), A | E0 | 12 | writes $FF00+n |
| LDH A, (C) | F2 | 8 | reads $FF00+C |
| LDH (C), A | E2 | 8 | writes $FF00+C |
| LD (nn), SP | 08 | 20 | |

#### 16-bit loads

| Instruction | Opcode | Cycles (T) | Flags |
|---|---|---|---|
| LD rr, nn | BC 01, DE 11, HL 21, SP 31 | 12 | |
| LD SP, HL | F9 | 8 | |
| LD HL, SP+e | F8 | 12 | Z=0 N=0, H/C from low-byte add of SP+e |
| PUSH rr (AF,BC,DE,HL) | F5, C5, D5, E5 | 16 | |
| POP rr | F1, C1, D1, E1 | 12 | POP AF forces low nibble of F to 0 |

#### 8-bit arithmetic / logic

| Instruction | Reg opcodes | Imm8 | Cycles | Flags Z N H C |
|---|---|---|---|---|
| ADD A, r | 80–87 | C6 | 4 (8 for (HL)); imm 8 | Z 0 H C |
| ADC A, r | 88–8F | CE | same | Z 0 H C |
| SUB A, r | 90–97 | D6 | same | Z 1 H C |
| SBC A, r | 98–9F | DE | same | Z 1 H C |
| AND A, r | A0–A7 | E6 | same | Z 0 1 0 |
| XOR A, r | A8–AF | EE | same | Z 0 0 0 |
| OR A, r | B0–B7 | F6 | same | Z 0 0 0 |
| CP A, r | B8–BF | FE | same | Z 1 H C (result discarded) |
| INC r | 04 0C 14 1C 24 2C 34 3C | — | 4; (HL) 12 | Z 0 H — (C preserved) |
| DEC r | 05 0D 15 1D 25 2D 35 3D | — | 4; (HL) 12 | Z 1 H — (C preserved) |

#### 16-bit arithmetic

| Instruction | Opcode | Cycles | Flags |
|---|---|---|---|
| ADD HL, rr | 09, 19, 29, 39 | 8 | Z preserved, N=0, H, C |
| INC rr | 03, 13, 23, 33 | 8 | none |
| DEC rr | 0B, 1B, 2B, 3B | 8 | none |
| ADD SP, e | E8 | 16 | Z=0 N=0, H/C from low byte |

#### Rotates, shifts, bit ops (accumulator)

| Instruction | Opcode | Cycles | Flags |
|---|---|---|---|
| RLCA | 07 | 4 | Z=0 N=0 H=0 C |
| RRCA | 0F | 4 | same |
| RLA | 17 | 4 | same (rotates through carry) |
| RRA | 1F | 4 | same |
| DAA | 27 | 4 | Z — 0 C |
| CPL | 2F | 4 | — 1 1 — |
| SCF | 37 | 4 | — 0 0 1 |
| CCF | 3F | 4 | — 0 0 C |
| NOP | 00 | 4 | |
| HALT | 76 | 4 | see §16/§17 |
| STOP | 10 00 | 4 | 2-byte; see §16 |
| DI | F3 | 4 | IME := 0 immediately |
| EI | FB | 4 | IME := 1 **after the next instruction** |

#### CB-prefixed (2-byte) opcodes

All: Z N H C per operation. Register forms 8 T-cycles; (HL) forms 16 T (BIT (HL) = 12).

| Group | Opcodes | Operation / flags |
|---|---|---|
| RLC r | CB 00–07 | Rotate left circular. Z 0 0 C |
| RRC r | CB 08–0F | Rotate right circular. Z 0 0 C |
| RL r | CB 10–17 | Rotate left through carry. Z 0 0 C |
| RR r | CB 18–1F | Rotate right through carry. Z 0 0 C |
| SLA r | CB 20–27 | Shift left (0 into bit 0). Z 0 0 C |
| SRA r | CB 28–2F | Shift right arithmetic (bit 7 kept). Z 0 0 C |
| SWAP r | CB 30–37 | Swap nibbles. Z 0 0 0 |
| SRL r | CB 38–3F | Shift right logical (0 into bit 7). Z 0 0 C |
| BIT b, r | CB 40–7F | Test bit b. Z=¬bit, N=0, H=1, C preserved |
| RES b, r | CB 80–BF | Reset bit b. No flags |
| SET b, r | CB C0–FF | Set bit b. No flags |

#### Jumps, calls, returns, restarts

| Instruction | Opcode | Cycles (taken/not) |
|---|---|---|
| JP nn | C3 | 16 |
| JP cc, nn | NZ C2, Z CA, NC D2, C DA | 16 / 12 |
| JP HL | E9 | 4 |
| JR e | 18 | 12 |
| JR cc, e | NZ 20, Z 28, NC 30, C 38 | 12 / 8 |
| CALL nn | CD | 24 |
| CALL cc, nn | NZ C4, Z CC, NC D4, C DC | 24 / 12 |
| RET | C9 | 16 |
| RET cc | NZ C0, Z C8, NC D0, C D8 | 20 / 8 |
| RETI | D9 | 16 (EI + RET) |
| RST $00/$08/…/$38 | C7/CF/D7/DF/E7/EF/F7/FF | 16 |

`rst` is a 1-byte call to a fixed vector — smaller and faster than `call`.

#### Invalid opcodes (hard-lock the CPU!)

$D3, $DB, $DD, $E3, $E4, $EB, $EC, $ED, $F4, $FC, $FD.

### Z80 comparison cheat-sheet (moved/changed opcodes)

| Opcode | Z80 | GB CPU |
|---|---|---|
| 08 | EX AF,AF' | LD (nn),SP |
| 10 | DJNZ | STOP |
| 22/2A/32/3A | LD (nn),HL / HL,(nn) / (nn),A / A,(nn) | LD (HL+),A / A,(HL+) / (HL−),A / A,(HL−) |
| D9 | EXX | RETI |
| E0/E2/F0/F2 | RET/JP PO,P | LDH (FF00+n)/(FF00+C) forms |
| E8 | RET PE | ADD SP,e |
| EA/FA | JP PE/M | LD (nn),A / A,(nn) |
| F8 | RET M | LD HL,SP+e |
| CB 3x | SLL | SWAP |

---

## 7. Interrupts

### Registers

- **IME** (internal CPU flag, unreadable): master enable. Modified only by `ei` (IME:=1, delayed by one instruction), `di` (IME:=0), `reti` (= `ei` + `ret`), and interrupt dispatch (IME:=0). IME=0 at game start.
- **IE — $FFFF**: per-source enable. Bit 0 VBlank, 1 STAT (LCD), 2 Timer, 3 Serial, 4 Joypad.
- **IF — $FF0F**: per-source request flags (same bit layout). A bit is set on the rising edge of the corresponding internal request line. Software may also write IF to request/discard interrupts.

A handler executes only when **IME = 1 AND IE bit = 1 AND IF bit = 1**. A set IF bit with IME/IE clear pends until allowed.

### Dispatch

1. CPU clears the IF bit (acknowledge) and IME (no nesting by default).
2. 2 wait M-cycles, pushes PC (2 M-cycles), jumps to vector (1 M-cycle). Total **5 M-cycles** overhead.
3. Handler runs; return with `reti` (re-enables IME) or `ret` after `ei`.

### Vectors & priority

| Priority | Vector | Source |
|---|---|---|
| 1 (highest) | $0040 | **VBlank** — PPU entered Mode 1 (LY=144). ~59.7 Hz handheld, ~61.1 Hz SGB |
| 2 | $0048 | **STAT** — selectable LCD conditions (Mode 0/1/2, LYC=LY) |
| 3 | $0050 | **Timer** — TIMA overflowed |
| 4 | $0058 | **Serial** — transfer complete (8 bits shifted) |
| 5 (lowest) | $0060 | **Joypad** — any selected P1 bit 0–3 went high→low (button press; beware switch bounce) |

**Nesting**: call `ei` inside a handler to allow further interrupts.

### STAT interrupt details

The four STAT sources (enabled via STAT bits 3–6) are ORed into one line; interrupt fires on its **rising edge**:

- **STAT blocking**: if a second source raises the line while already high, no new interrupt occurs (e.g. Mode 0 + Mode 1 both enabled → no Mode 1 interrupt that frame boundary).
- **Spurious STAT interrupt (DMG quirk)**: writing STAT (even $00) during OAM scan/HBlank/VBlank/LYC=LY can trigger an interrupt as if $FF were written for one M-cycle. GBC in DMG mode lacks this quirk (games *Road Rash* and *Xerd no Densetsu* rely on it and break on GBC).

Typical use: set LYC to a scanline, enable the LYC=LY source, and modify scroll/palette/LCDC mid-frame for raster effects.

---

## 8. Timer & Divider Registers

Distinct from the MBC3 RTC — this is the built-in programmable timer.

| Reg | Addr | Description |
|---|---|---|
| **DIV** | FF04 | Divider. Increments at 16384 Hz (≈16779 on SGB1; 32768 in CGB double speed). **Any write resets it to $00.** Also reset by STOP/speed switch. DIV is the visible upper byte of the internal "system counter" |
| **TIMA** | FF05 | Timer counter; increments at the TAC-selected rate. On overflow → reloaded from TMA and timer interrupt requested |
| **TMA** | FF06 | Timer modulo. E.g. TMA=$FE → interrupt every 2 increments (divides clock by 2) |
| **TAC** | FF07 | Bit 2 = timer enable; bits 1–0 = clock select. DIV always runs regardless |

TAC clock select:

| Bits | Increment every | Freq (normal speed) | Freq (CGB double) |
|---|---|---|---|
| 00 | 256 M-cycles | 4096 Hz | 8192 Hz |
| 01 | 4 M-cycles | 262144 Hz | 524288 Hz |
| 10 | 16 M-cycles | 65536 Hz | 131072 Hz |
| 11 | 64 M-cycles | 16384 Hz | 32768 Hz |

### Obscure timer behavior

- TIMA ticks on **falling edges** of the selected system-counter bit ANDed with TAC enable. Consequences:
  - Writing DIV (resetting the counter) can cause an immediate TIMA increment if the watched bit was set.
  - Changing TAC's clock select from a set bit to a clear one causes an increment.
  - On DMG, disabling the timer while the selected bit is set causes one increment (not on CGB).
- **Overflow sequence**: when TIMA overflows, it reads $00 for one M-cycle; TMA is copied and IF bit 2 set **one M-cycle later**.
  - Writing TIMA during the overflow cycle **cancels** the reload and the interrupt.
  - Writing TIMA during the reload cycle is ignored (TMA wins).
  - Writing TMA during the reload cycle updates the value TIMA receives.
- If TMA is written on the same M-cycle TIMA is reloaded, the **old** TMA value is transferred.

---

## 9. Graphics (PPU)

### Concepts

- **Tile**: 8×8 pixels, 2 bits per pixel (2bpp) → color indices 0–3. No color stored; palettes map indices to colors. In objects, index 0 = transparent.
- **Background**: a 32×32 tilemap (256×256 px) of tile indices; scrollable in hardware via SCX/SCY; wraps at edges.
- **Window**: a second, non-scrollable tilemap layer composited above BG; only its top-left position is controllable (WX, WY). Used for status bars/HUDs.
- **Objects (sprites)**: up to 40 movable 8×8 or 8×16 px elements; max **10 per scanline**.

### Tile data format

- 16 bytes per tile at $8000–$97FF (384 tiles; 768 on CGB across 2 banks).
- Each row = 2 bytes: first byte = bit 0 of each pixel's color index, second byte = bit 1. Bit 7 = leftmost pixel.
- Example: bytes `$3C $7E` → binary `00111100`/`01111110` → indices `0 2 3 3 3 3 2 0`.
- **Addressing modes** (BG/Window only, selected by LCDC bit 4):
  - **$8000 mode** (LCDC.4=1): unsigned, base $8000. Tiles 0–255 → blocks 0+1.
  - **$8800 mode** (LCDC.4=0): signed, base $9000. Tiles 0–127 → block 2; 128–255 (i.e. −128…−1) → block 1.
  - **Objects always use $8000 addressing.**

### Tile maps

- Two 32×32 maps at $9800–9BFF and $9C00–9FFF; each byte is a tile index. BG map chosen by LCDC.3; Window map by LCDC.6.
- Visible area: 160×144 window into the 256×256 map; wraps around.
- Entry address: `$9800 + Y×32 + X` (plus $0400 for the second map).

### OAM (FE00–FE9F) — 40 objects × 4 bytes

| Byte | Meaning |
|---|---|
| 0 | **Y position** = screen Y + 16. Y=0 hides; Y=16 = top of screen; Y=160 hides. |
| 1 | **X position** = screen X + 8. X=0 or X≥168 hides **but still counts toward the 10-per-line limit** — hide via Y instead |
| 2 | Tile index (unsigned, $8000 method). In 8×16 mode: top tile = index & $FE, bottom = index \| $01 (hardware ignores bit 0) |
| 3 | Attributes: bit 7 = priority (1 = BG/win colors 1–3 drawn over OBJ); bit 6 = Y flip; bit 5 = X flip; bit 4 = DMG palette (0=OBP0, 1=OBP1); bit 3 = CGB VRAM bank; bits 2–0 = CGB palette (0–7) |

**Priority rules:**

- **Selection** (10/line limit): PPU scans OAM in order; first 10 objects whose Y range covers LY win. Off-screen X still counts.
- **Drawing** (overlap): DMG — smaller X wins; tie → earlier OAM entry. CGB — earlier OAM entry always wins (unless OPRI set to DMG-style).
- Object-vs-object priority is resolved **before** BG-vs-object priority; a high-priority object with "BG over OBJ" set can mask lower-priority objects behind BG.

### Palettes (DMG mode)

- **BGP ($FF47)**: BG/Window palette. 2 bits per color index: bits 1–0 = color for index 0 … bits 7–6 = index 3. Shade values: 0 white, 1 light gray, 2 dark gray, 3 black. Canonical "normal" value: $E4 (11 10 01 00).
- **OBP0 ($FF48), OBP1 ($FF49)**: object palettes; same encoding, but bits 1–0 ignored (index 0 transparent).
- Changing palettes mid-frame or during gameplay = cheap effects: fades, damage flashes, palette swaps.

### LCDC ($FF40) — LCD control

| Bit | Function |
|---|---|
| 7 | **LCD & PPU enable**. ⚠ Turn off **only during VBlank** — disabling mid-frame can burn a black line into the LCD (Nintendo rejected games for this). Re-enabling shows a blank first frame. While off: VRAM/OAM fully accessible |
| 6 | Window tile map: 0 = $9800, 1 = $9C00 |
| 5 | Window enable (overridden by bit 0 = 0 on DMG) |
| 4 | BG & Window tile data: 0 = $8800 signed mode, 1 = $8000 unsigned mode |
| 3 | BG tile map: 0 = $9800, 1 = $9C00 |
| 2 | OBJ size: 0 = 8×8, 1 = 8×16 |
| 1 | OBJ enable. Can be toggled mid-frame to keep objects off a status bar |
| 0 | DMG: BG & Window enable (0 = blank white). CGB: BG master priority (0 = objects always on top) |

LCDC is never locked by the PPU — it can be written any time, even mid-scanline.

### STAT ($FF41) — LCD status

| Bits | Function |
|---|---|
| 6 | LYC=LY interrupt enable |
| 5 | Mode 2 (OAM scan) interrupt enable |
| 4 | Mode 1 (VBlank) interrupt enable |
| 3 | Mode 0 (HBlank) interrupt enable |
| 2 | LYC=LY flag (read-only, constantly updated) |
| 1–0 | PPU mode (read-only; reads 0 when LCD off) |

### LY / LYC

- **LY ($FF44, read-only)**: current scanline, 0–153. 144–153 = VBlank. (Writing resets it — dangerous, avoid.)
- **LYC ($FF45)**: compared against LY each line; sets STAT bit 2 and can trigger STAT interrupt.

### PPU modes & frame timing

Each of 154 lines per frame: line = 456 dots.

| Mode | Name | Duration | CPU-accessible video memory |
|---|---|---|---|
| 2 | OAM scan | 80 dots | VRAM, CGB palettes |
| 3 | Pixel transfer | 172–289 dots (variable) | **None** (VRAM, OAM, CGB palette RAM all locked) |
| 0 | HBlank | 376 − mode 3 | VRAM, OAM, CGB palettes |
| 1 | VBlank | 10 lines (4560 dots) | VRAM, OAM, CGB palettes |

**Mode 3 penalties** (lengthen Mode 3, shorten HBlank):

- Fine scroll: SCX % 8 dots at line start (plus 12 dots base: two tile fetches).
- Window: 6 dots when window starts on the line.
- Objects: 6–11 dots per object on the line (6 flat + 0–5 fetch wait; object at X=0 always costs 11).

**Access rules** (violations: writes ignored, reads return $FF/garbage):

- VRAM accessible in modes 0, 1, 2 — not 3.
- OAM accessible in modes 0, 1 — not 2 or 3.
- Both fully accessible while the LCD is off.
- Do VRAM updates in VBlank; for mid-frame updates, synchronize to HBlank via STAT mode 0 (e.g. `di` + `halt` with only the Mode 0 STAT interrupt enabled gives modes 0+2 = 165–288 dots of VRAM time).

Typical VRAM-wait loop:

```rgbasm
.waitVRAM
    ldh a, [rSTAT]     ; $FF41
    and  STATF_BUSY    ; bit 1
    jr   nz, .waitVRAM
```

### Scrolling (SCY $FF42, SCX $FF43)

- Top-left of the 160×144 viewport in the 256×256 BG map; wraps (mod 256).
- Writable mid-frame (even during Mode 3); scroll registers are re-read per tile fetch, but SCX's low 3 bits only at line start. → Raster/wavy effects by changing SCX per line.
- Pre-CGB-D models read Y separately per bitplane (ultra-precise SCY writes can desync planes).

### Window (WY $FF4A, WX $FF4B)

- Top-left of window at screen position (WX−7, WY). Visible range: WX 0–166, WY 0–143. WX=7, WY=0 covers the whole screen.
- Not scrollable; uses its own internal line counter that increments only on lines where the window is actually rendered — hiding the window mid-frame and re-showing it resumes the same window row (stretch artifact).
- Best practices: write WX/WY/LCDC only during VBlank or HBlank; to hide the window for part of the screen, set WX high rather than clearing LCDC.5.
- Quirks: WX=0 shifts window left by SCX%8; on DMG WX=166 makes the window span the screen offset by one line; DMG also has a single-pixel artifact when disabling the window exactly on a tile boundary.

### OAM DMA ($FF46)

Writing $XX starts copying $XX00–$XX9F → $FE00–$FE9F (source may be ROM or RAM, $00–$DF). Takes 160 M-cycles (640 dots; 320 in double speed).

- **During DMA the CPU can only execute from/access HRAM** ($FF80–FFFE) on DMG. On CGB, ROM and WRAM are on separate buses, but busy-waiting in HRAM is still recommended (stack is in WRAM).
- **Interrupts during DMA are dangerous** (they touch WRAM/ROM) — run DMA from the VBlank handler or under `di`.
- The PPU also misreads OAM during DMA: objects appear hidden (Mode 2) or get wrong tile/attributes (Mode 3). Hence: run DMA during VBlank (Mode 1).

Canonical HRAM DMA routine (copy to HRAM at init, call during VBlank):

```rgbasm
run_dma:                     ; must reside in HRAM
    ld   a, HIGH(OamBuffer)
    ldh  [rDMA], a           ; $FF46 — transfer starts after this instruction
    ld   a, 40               ; 40 × 4 = 160 M-cycles
.wait
    dec  a                   ; 1 M-cycle
    jr   nz, .wait           ; 3 M-cycles
    ret
```

Compact 5-byte-saving variant: pass B=delay count, C=$46 in BC from ROM code and `jp` to the HRAM tail (`ldh [c], a` / `dec b` / `jr nz` / `ret z` — the slower conditional ret avoids a stack read on DMA's last cycle).

### Rendering pipeline (Pixel FIFO) — summary

- Two FIFOs (BG and OBJ), ≤16 pixels each; pixels carry color index, palette, and priority info.
- BG fetcher: Get tile → Get data low → Get data high → Sleep → Push (8 px when FIFO empty); ~2 dots per step.
- One pixel popped per dot in Mode 3; OBJ FIFO pixels win unless transparent (index 0) or BG priority applies.
- Fetcher X: `((SCX/8) + fetcherX) & $1F`; fetcher Y: `(LY + SCY) & 255`. Window uses its own X/Y counters.
- Deep FIFO details matter mainly for emulator authors; game devs only need the mode/penalty model above.

### CGB graphics additions

- **VBK ($FF4F)**: VRAM bank 0/1 select. Bank 1: 384 extra tiles + BG attribute maps.
- **BG attribute map** (bank 1, mirrors tilemap layout): bit 7 = priority (BG colors 1–3 over OBJ), bit 6 = Y flip, bit 5 = X flip, bit 3 = tile VRAM bank, bits 2–0 = BG palette 0–7. (Bit 4 unused.)
- **CGB BG-vs-OBJ priority** (3 flags: LCDC.0, OAM attr bit 7, BG attr bit 7): BG color index 0 → OBJ always wins; LCDC.0=0 → OBJ always wins; both attr bits clear → OBJ wins; otherwise BG wins.
- **Color palettes**: 8 BG + 8 OBJ palettes × 4 colors, RGB555 little-endian, in two 64-byte CRAM banks accessed via index/data registers:
  - **BCPS/BGPI ($FF68)**: bit 7 = auto-increment, bits 5–0 = address. **BCPD/BGPD ($FF69)**: data. Auto-increment advances after each *write* (even failed ones), never on reads.
  - **OCPS/OBPI ($FF6A) / OCPD/OBPD ($FF6B)**: same for OBJ palettes. OBJ color 0 unused (transparent).
  - CRAM data registers are locked during Mode 3 (reads $FF, writes ignored); index registers are always accessible.
  - Boot ROM initializes all BG colors to white but leaves OBJ CRAM random — always initialize it.
- **Color appearance**: GBC screen is unlit; $10–$1F all look near-white; pigment mixing skews colors (e.g. $03EF neon green on VGA → washed-out yellow on GBC). Old GBAs render $00–$07 nearly black — consider `GBA = GBC × 3/4 + $08` per component when AGB is detected.

### CGB VRAM DMA (HDMA1–5, $FF51–$FF55)

- HDMA1/2: source (0000–7FF0 or A000–DFF0; low 4 bits ignored). HDMA3/4: destination in VRAM (8000–9FF0; bits 12–4 respected).
- **HDMA5 ($FF55)**: write to start. Bits 6–0 = length/16 − 1 ($10–$800 bytes). Bit 7 = mode:
  - **0 = General purpose**: copies everything at once, halting the CPU (~8 µs per $10 block = 8 M-cycles normal, 16 fast M-cycles double speed). Use only with LCD off, in VBlank, or for short blocks in HBlank. Reads $FF when done.
  - **1 = HBlank DMA**: copies $10 bytes per HBlank (LY 0–143 only; pauses in VBlank, resumes at LY 0). Don't switch source/dest banks mid-transfer. Terminate early by writing bit 7 = 0. **Don't start HBlank DMA during HBlank.** Reading bit 7: 1 = inactive, 0 = active.
- Up to ~2280 bytes (≈142 tiles) fit in one VBlank.
- Older MBCs/ROMs may not keep up with the 2 bytes/µs rate.

---

## 10. Audio (APU)

Four channels, mixed to stereo (mono on the speaker). Register naming: `NRxy` (x = channel or 5 for global, y = slot). Common pattern: NRx0 channel-specific, NRx1 length, NRx2 volume/envelope, NRx3 period low, NRx4 trigger + length enable + period high.

| Channel | Type | Extras |
|---|---|---|
| CH1 | Pulse | Frequency sweep |
| CH2 | Pulse | — |
| CH3 | Wave (programmable) | 32×4-bit wave RAM, coarse volume |
| CH4 | Noise (LFSR) | 7/15-bit modes |

### Global registers

**NR52 ($FF26) — Audio master control**

- Bit 7: APU power (R/W). Off saves ~16% power; clears all APU registers (except NR52, length timers on DMG) and makes them read-only. Does **not** clear wave RAM or DIV-APU. Turn on with $80, then re-init all sound registers.
- Bits 3–0 (read-only): CH4–CH1 active status.

**NR51 ($FF25) — Panning**: bit per channel per side (bits 7–4 = CH4–CH1 left, bits 3–0 = CH4–CH1 right). Toggling a bit for a channel whose DAC is on causes a pop.

**NR50 ($FF24) — Master volume & VIN**: bit 7/3 = VIN left/right (cartridge audio in — unused commercially; keep 0), bits 6–4 / 2–0 = left/right volume 0–7 (0 = level 1, i.e. very quiet but never fully muted; 7 = full).

### CH1 — Pulse with sweep

**NR10 ($FF10) — Sweep**: bits 6–4 pace (in 128 Hz ticks; 0 disables), bit 3 direction (0 = period increases/pitch falls, 1 = decreases), bits 2–0 step. Each iteration: `L(t+1) = L(t) ± L(t) / 2^step`, written back to NR13/14. Overflow past $7FF turns the channel off — **even with pace 0**. Period 0 sticks forever; subtraction can't underflow. Writing direction from subtract→add after a calculation instantly kills the channel.

**NR11 ($FF11) — Duty & length**: bits 7–6 duty cycle (00 = 12.5%, 01 = 25%, 10 = 50%, 11 = 75%; 25% and 75% sound identical), bits 5–0 initial length (write-only; higher = shorter note).

**NR12 ($FF12) — Volume & envelope**: bits 7–4 initial volume, bit 3 direction (0 = decrease, 1 = increase), bits 2–0 sweep pace (envelope ticks at 64 Hz; volume steps every N ticks; 0 = off). Setting bits 3–7 = 0 turns the DAC (and channel) off → pop. Writes while playing require retrigger.

**NR13 ($FF13)** = period low 8 bits (write-only). **NR14 ($FF14)**: bit 7 trigger, bit 6 length enable, bits 2–0 period high 3 bits.

**Period semantics** (pulse & wave): the period register holds a *negative* duration. Tone frequency:

- Pulse: `f = 131072 / (2048 − period)` Hz (sample rate = 1048576/(2048−period), 8 steps/wave)
- Wave: `f = 65536 / (2048 − period)` Hz (32 steps/wave) — same period value = one octave lower than pulse

Period changes take effect only after the current sample ends.

**Trigger** (NR14 bit 7): enables channel (if DAC on), resets expired length timer, loads period divider, resets envelope, reloads volume, resets sweep (shadow register ← period; overflow check runs immediately if step ≠ 0).

### CH2 — Pulse

NR21–NR24 ($FF16–$FF19) = NR11–NR14 equivalents, minus sweep.

### CH3 — Wave

- **NR30 ($FF1A)**: bit 7 = DAC enable (turning off kills channel; often toggled around wave RAM writes; causes a pop).
- **NR31 ($FF1B)**: length (0–255, ticks at 256 Hz).
- **NR32 ($FF1C)**: bits 6–5 output level: 00 mute, 01 100%, 10 50% (shift right 1), 11 25% (shift right 2). Shifts the *digital* value.
- **NR33/NR34 ($FF1D/$FF1E)**: period + trigger/length-enable (as CH1).
- **Wave RAM ($FF30–FF3F)**: 16 bytes = 32 4-bit samples, played high nibble first. ⚠ On trigger, playback starts at sample **1** (low nibble of first byte) — sample 0 only plays on wrap-around.
- Accessing wave RAM while CH3 plays misbehaves (DMG: only the byte CH3 is reading is accessible; AGB: reads $FF/writes ignored). Access it only while CH3 is inactive.
- ⚠ **DMG retrigger corruption**: retriggering CH3 exactly while it reads wave RAM corrupts the first four bytes (mirrors the aligned 4-byte group being read). Avoid: write $00 then $80 to NR30 before retriggering. (Famous *DuckTales* bug.)
- Sample playback trick: rewrite wave RAM as soon as it's consumed.

### CH4 — Noise

- **NR41 ($FF20)**: length (0–63).
- **NR42 ($FF21)**: volume & envelope (as NR12).
- **NR43 ($FF22)**: bits 7–4 clock shift, bit 3 LFSR width (0 = 15-bit, 1 = 7-bit — more tonal/regular), bits 2–0 clock divider (0 treated as 0.5). LFSR clock = `262144 / (divider × 2^shift)` Hz. Shift 14/15 = channel never clocked. Shifted-out bit 0 = output select (0 → amplitude 0, else NR42 volume).
  - ⚠ 15→7-bit switch can lock the LFSR (silence); retrigger to reset.
- **NR44 ($FF23)**: bit 7 trigger, bit 6 length enable.

### APU internals & quirks

- **DIV-APU**: a counter clocked by falling edges of DIV bit 4 (bit 5 in double speed) → 512 Hz. Frame sequencer ticks: length at 256 Hz (every 2), sweep at 128 Hz (every 4), envelope at 64 Hz (every 8). Writing DIV can advance it early.
- **DACs**: channel x's DAC on iff `NRx2 & $F8 != 0` (CH3: NR30 bit 7). Envelope reaching 0 does **not** disable the DAC. Disabled channel with enabled DAC outputs "analog 1" (DC offset, removed by the high-pass filter).
- **Pops**: caused by DAC on/off, NR51 panning changes, NR50 volume changes. Avoid: silence via $08→NRx2 + retrigger with $80→NRx4 instead of killing the DAC.
- **High-pass filter**: constantly pulls output toward 0; charge factor 0.999958 per 4.19 MHz cycle on DMG (0.998943 on MGB/CGB; more aggressive on GBA).
- **Length timer**: ticks up at 256 Hz from initial value; channel off at 64 (CH1/2/4) or 256 (CH3).
- **Zombie mode**: writing NRx2 while playing manually bumps volume in model-dependent ways; the only portable trick is increase-mode/period-0 writes ($V8 init, then $08 to increment).
- **PCM12 ($FF76) / PCM34 ($FF77)** (CGB, read-only): live digital outputs of CH1/2 and CH3/4 (nibbles) — debugging aid.
- GBA audio differs: digital mixing, no real DACs, CH3 DAC inverted (disconnect CH3 via NR51 before wave RAM writes), stronger HPF.
- SGB1 runs the whole APU ~2.4% fast (higher pitch); SGB2 is correct.

---

## 11. Joypad Input

**P1/JOYP ($FF00)**:

| Bits | Function |
|---|---|
| 5 | Select buttons (0 = selected): Start, Select, B, A |
| 4 | Select d-pad (0 = selected): Down, Up, Left, Right |
| 3–0 | Read-only inputs: bit 3 = Start/Down, 2 = Select/Up, 1 = B/Left, 0 = A/Right |

- **Pressed = 0** (active low). Writing $30 (neither selected) reads low nibble $F.
- Read several times in a row and use the last read (lets the multiplexer/bounce settle).
- Joypad interrupt: any selected input going low (press) — useful mainly to wake from STOP. Beware switch bounce (not present on GBA SP).

Standard read routine (returns B = held, C = newly pressed; store previous in `wJoyHeld`):

```rgbasm
ReadJoypad:
    ld   a, P1F_GET_DPAD      ; $20: select d-pad
    ldh  [rP1], a
    ldh  a, [rP1]             ; a few reads to stabilize
    ldh  a, [rP1]
    cpl
    and  $0F                  ; A = d-pad bits
    swap a
    ld   b, a
    ld   a, P1F_GET_BTN       ; $10: select buttons
    ldh  [rP1], a
    ldh  a, [rP1]
    ldh  a, [rP1]
    cpl
    and  $0F
    or   b                    ; A = all 8 buttons (bit 7..0 = D U L R Ss s B A... )
    ld   b, a                 ; B = currently held
    ldh  a, [rP1]             ; (order: store, compute pressed)
    ld   a, P1F_GET_NONE
    ldh  [rP1], a             ; deselect
    ld   a, [wJoyHeld]
    cpl
    and  b                    ; newly pressed = held AND NOT previously held
    ld   c, a
    ld   a, b
    ld   [wJoyHeld], a
    ret
```

(Adjust bit order to taste; hardware.inc defines `PADF_*`/`PADB_*` masks.)

---

## 12. Serial Data Transfer (Link Cable)

Byte-at-a-time synchronous transfer; the Game Boy supplying the clock is the master.

- **SB ($FF01)**: data register; shifts left each clock — bit 7 out, received bit into bit 0. After 8 clocks, SB = received byte.
- **SC ($FF02)**: bit 7 = transfer enable/active; bit 1 = CGB fast clock; bit 0 = clock select (1 = internal/master, 0 = external/slave).

Master flow: load SB, write SC = $81; on completion SC bit 7 clears and the serial interrupt fires. Slave flow: load SB, write SC = $80, wait for interrupt.

Clock rates: DMG fixed 8192 Hz (~1 KB/s). CGB: 8192 Hz (normal), 16384 Hz (double speed), 262144 Hz (bit 1 set, normal), 524288 Hz (bit 1, double). External clocks: DMG tolerates up to ~500 kHz; no minimum.

Robustness:

- **Timeouts**: with external clock, a missing peer means the transfer never completes — always run a timeout counter and abort.
- **Disconnects**: master reads 1-bits ($FF bytes) when unplugged; a mid-transfer disconnect pulls up over ~20 µs.
- **Sync**: master should delay briefly after each transfer so the slave can prepare the next byte (slave must have bit 7 set before the master starts); alternate internal/external clock per byte if needed.
- Check only SC bit 7 for completion.

---

## 13. Game Boy Color Features

### Unlocking & detection

- Set header byte $0143 to $80 (compatible) or $C0 (CGB-only), else the CGB runs in DMG compatibility mode.
- Detect hardware from boot-time registers: **A = $11** → CGB or GBA; then **B bit 0**: 0 = CGB, 1 = GBA (for GBA palette correction).
- DMG-mode detection: A = $01 (DMG/SGB) or $FF (MGB/SGB2); C = $13 (handheld) vs $14 (SGB).

### Double Speed mode (KEY1, $FF4D)

- Bit 7 (R): current speed (1 = double). Bit 0 (R/W): arm switch.
- Switch procedure: `IE = 0`, `P1 = $30`, `KEY1 = $01`, then `STOP`. Bit 0 auto-clears; CPU pauses 2050 M-cycles (DIV frozen).
- Doubles: CPU, timers/DIV, serial, OAM DMA. Unaffected: PPU/LCD, HDMA, all audio.
- More power draw; avoid switching mid-gameplay (display glitches during the switch).

### WRAM banking (SVBK, $FF70)

32 KiB total: bank 0 fixed at C000–CFFF; banks 1–7 selectable at D000–DFFF via SVBK bits 0–2 (writing 0 selects bank 1).

### Misc CGB registers

- **KEY0 ($FF4C)**: CPU mode; written by boot ROM only, locked afterwards (bit 2 = DMG compat).
- **OPRI ($FF6C)**: object priority mode (0 = CGB OAM-order, 1 = DMG X-coordinate). Set by boot ROM; effective only pre-boot-unmap/PGB.
- **RP ($FF56)**: IR port. Bits 7–6 = read enable ($C0), bit 1 = receiving (0 = signal), bit 0 = LED on. Reset to $00 after use (power). Receiver auto-adapts to sustained signals — pulse transmissions. GBA has no IR port.
- Undocumented R/W scratch: FF72, FF73, FF74 (CGB mode only), FF75 bits 4–6.

### DMG compatibility mode palettes

The CGB boot ROM auto-colorizes DMG-only games: BGP/OBP0/OBP1 become indices into CGB CRAM; palette chosen from a title-checksum table (licensee must be Nintendo) with user override via button combos during the logo. Full table on TCRF.

---

## 14. Super Game Boy

The SGB is a SNES cartridge containing a full GB SoC plus the ICD2 bridge chip; games run at SNES-derived clock (~2.4% fast on SGB1; SGB2 uses its own crystal).

- **Unlock**: header SGB flag ($0146) = $03 **and** old licensee ($014B) = $33.
- **Detect**: boot-time C register = $14 (A distinguishes SGB $01 vs SGB2 $FF). Legacy method: MLT_REQ command then watch for incrementing joypad IDs.
- **Command packets**: 16-byte packets sent via joypad register writes (bits 4/5 pulses), packet header byte = (command × 8) + length. Commands: palette setup (PAL01/PAL23/PAL03/PAL12, PAL_SET, PAL_TRN, PAL_PRI), attribute maps for colorizing the 20×18-char screen (ATTR_BLK/LIN/DIV/CHR/TRN/SET), SOUND (SNES SFX), SOU_TRN, custom border (CHR_TRN + PCT_TRN via VRAM transfer), DATA_SND/DATA_TRN (write SNES WRAM), JUMP (run SNES code), MLT_REQ (2/4-player joypads), ICON_EN, MASK_EN, OBJ_TRN (SNES sprites), ATRC_EN, TEST_EN.
- Features: colorized screen (static attribute regions only — no per-sprite colors), custom 4bpp border, up to 24 SNES objects, multiplayer, SNES sound effects/sequencer, even running code on the SNES CPU.
- Only the SGB2 has a link port.

---

## 15. Power-Up Sequence & Console Detection

1. Internal boot ROM (mapped over cartridge ROM) unpacks + scrolls the Nintendo logo, plays "ba-ding!", re-reads the logo and verifies it plus the header checksum. Failures lock the console (CGB checks only the logo's first half).
2. CGB boot ROM additionally: compatibility palettes for DMG games, KEY0/OPRI setup, optional palette picker.
3. Boot ROM unmaps itself via $FF50 and execution continues at $0100. The value written to $FF50 lands in A: $01 (DMG/SGB), $FF (MGB/SGB2), $11 (CGB/AGB).

**Register state at hand-off (key values):**

| Reg | DMG/SGB | MGB/SGB2 | CGB | AGB |
|---|---|---|---|---|
| A | $01 | $FF | $11 | $11 |
| B | $00 | $00 | $00 | $01 |
| C | $13/$14 | $13/$14 | $00 | $00 |
| D | $00 | $00 | $FF | $FF |
| E | $D8/$00 | $D8/$00 | $56 | $56 |
| HL | $014D/$C060 | $014D/$C060 | $000D | $000D |
| SP | $FFFE | $FFFE | $FFFE | $FFFE |
| PC | $0100 | $0100 | $0100 | $0100 |

Hardware regs (DMG): P1 $CF, SC $7E, DIV $AB, TAC $F8, IF $E1, NR52 $F1, LCDC $91, BGP $FC, OBP0/1 $FF.

**Reliance warning**: don't depend on any of this except the documented detection values (A for model, C for SGB, B for GBA). Flashcart menus and emulators vary. WRAM/HRAM power-up contents are **random** — initialize everything (some emulators can break on uninitialized reads; use that during development). Cartridge SRAM is random on first power — guard saves with a magic constant.

---

## 16. Power Management (HALT/STOP)

### HALT

- Suspends the CPU until any interrupt becomes pending (`IE & IF ≠ 0`), saving 5–50% power. Wake-up occurs even with IME = 0 (no handler called in that case).
- Canonical frame loop: enable VBlank interrupt; handler sets a flag (or just returns via `reti`); main loop executes `halt` once per frame.
- Never busy-wait on LY when you can `halt`.

```rgbasm
; VBlank-only sync
.waitVBlank
    halt                      ; resumes after VBlank handler runs
    jr   .waitVBlank          ; loop back for next frame work
```

(With a flag byte, remember the handler must `reti` or `ei`+`ret`.)

### STOP

- Very low power standby; wakes on joypad line going low (select buttons/d-pad via P1 first: write $00/$10/$20).
- On CGB, STOP after arming KEY1 = speed switch instead (see §13).
- ⚠ DMG: disabling the LCD before STOP leaves the LCD driving a black line — **hardware damage risk**. On CGB, STOP with LCD on = black screen (except Mode 3 keeps drawing).
- STOP behavior is notoriously context-dependent (can degenerate to HALT or NOP, and its second byte isn't always ignored) — follow the Pan Docs flowchart; no licensed game uses STOP except for CGB speed switching.

### Other savings

- APU off when unused: write $00 to NR52 (back on with $80; re-init registers). ~16% savings.
- Prefer normal speed on CGB when performance allows.
- Tight assembly beats high-level code for battery life.

---

## 17. Hardware Bugs & Pitfalls

| Bug | Summary | Mitigation |
|---|---|---|
| **LCD off outside VBlank** | Can burn a black line into the LCD | Only clear LCDC.7 during Mode 1 |
| **OAM corruption bug (DMG only)** | Mode-2 access to OAM range, or `inc/dec rr`, `ld [hl±],a`, `pop/push`, `ret/call/rst`, or executing code with a 16-bit register/PC/SP in $FE00–FEFF corrupts OAM rows (write: row's first word ← `((a^c)&(b^c))^c`, rest copied from previous row; read: `b\|(a&c)`) | Don't touch OAM (or FEA0–FEFF) during Mode 2; keep SP/PC/HL out of $FE00–FEFF |
| **VRAM/OAM lockout** | Writes ignored, reads $FF during Mode 3 (VRAM) / Modes 2–3 (OAM) | Update in VBlank/HBlank; use OAM DMA |
| **halt bug** | `halt` with IME=0 and an interrupt pending: PC fails to increment → next byte executes twice; `ei;halt` re-runs halt after the handler; `halt;rst` returns to the rst | Standard idiom is safe; be careful with `di`-based waits |
| **STAT blocking** | STAT line already high → missed interrupts for subsequent sources | Don't enable adjacent mode sources together; structure handlers accordingly |
| **Spurious STAT IRQ (DMG)** | Writing STAT during active display phases can fire an IRQ as if $FF written | Avoid mid-display STAT writes; or account for it |
| **Timer edge quirks** | Writing DIV/TAC can spuriously increment TIMA; overflow reload timing (see §8) | Re-init TIMA after changing DIV/TAC |
| **CH3 wave RAM corruption (DMG)** | Retriggering CH3 during sample read corrupts wave RAM bytes 0–3 | Write $00 then $80 to NR30 before retriggering |
| **LFSR lockup** | 15→7-bit switch with all-1 low bits silences CH4 | Retrigger CH4 after changing NR43 bit 3 |
| **Audio pops** | DAC toggles, NR51/NR50 changes | Silence via envelope-off + retrigger; avoid hard DAC kills |
| **Window glitches** | WX=0 scroll shift; WX=166 full-screen+1 line (DMG); LCDC.5 toggle artifacts | Move WX/WY in VBlank; hide window via large WX |
| **OAM DMA conflicts** | CPU limited to HRAM; interrupts crash into DMA | DMA from VBlank handler in HRAM |
| **Invalid opcodes** | $D3,$DB,$DD,$E3,$E4,$EB,$EC,$ED,$F4,$FC,$FD hard-lock | Assembler will never emit them from valid mnemonics |
| **OBJ per-line limit** | >10 objects/line → later OAM entries dropped; X-off-screen objects still count | Hide with Y=0; flicker/rotate OAM order |
| **FEA0–FEFF** | Prohibited region, revision-specific junk | Never use |
| **Echo RAM** | Mirror of WRAM; some flashcarts conflict with SRAM | Never use |
| **SCX low-3-bits latch** | Fine scroll only sampled at line start | For per-pixel wobble, rewrite SCX at HBlank, not mid-line |
| **CGB CRAM init** | OBJ palette RAM random at boot | Always initialize palettes |
| **Uninitialized RAM** | Random on hardware; emulators differ | Init everything; test with "break on uninitialized read" |

---

## 18. Practical Game Development

### Minimal RGBDS ROM skeleton

```rgbasm
INCLUDE "hardware.inc"

SECTION "Header", ROM0[$100]
    jp EntryPoint
    ds $150 - @, 0        ; room for header (use rgbfix to fill)

SECTION "Main", ROM0[$150]
EntryPoint:
    di
    ld   sp, $E000        ; stack at top of WRAM
    ; --- wait for VBlank, then LCD off for full VRAM access ---
.waitVBlank
    ldh  a, [rLY]
    cp   144
    jr   c, .waitVBlank
    xor  a
    ldh  [rLCDC], a       ; LCD off (safe: we're in VBlank)

    ; --- init: copy tiles to VRAM, fill tilemap, init palettes ---
    ; CopyTiles / FillMap routines here (VRAM fully accessible now)
    ld   a, %11100100     ; BGP: 3→black … 0→white
    ldh  [rBGP], a
    ldh  [rOBP0], a

    ; --- copy OAM DMA routine to HRAM ---
    ld   de, run_dma
    ld   hl, hOamDma
    ld   b, run_dma.end - run_dma
.copyDma
    ld   a, [de]
    inc  de
    ldh  [hli], a
    dec  b
    jr   nz, .copyDma

    ; --- enable VBlank interrupt ---
    xor  a
    ldh  [rIF], a
    ld   a, IEF_VBLANK
    ldh  [rIE], a
    ei

    ; --- LCD on: BG on, OBJ on, $8000 tile data ---
    ld   a, LCDCF_ON | LCDCF_BGON | LCDCF_OBJON | LCDCF_BG8000
    ldh  [rLCDC], a

MainLoop:
    halt                  ; sleep until VBlank
    ; game logic here (runs once per frame):
    call ReadJoypad
    call UpdateGame
    call hOamDma          ; shadow OAM → OAM via DMA (in VBlank)
    jr   MainLoop
```

Build:

```bash
rgbasm -o game.o game.asm
rgblink -o game.gb game.o
rgbfix -v -p 0xFF game.gb   # fix header checksums; set title etc. via flags
```

### The canonical frame loop

1. `halt` (or VBlank interrupt) for frame sync.
2. During VBlank (~1.1 ms, ~1140 M-cycles): OAM DMA, VRAM/tilemap/palette updates, scroll register writes.
3. Rest of frame: game logic, input, physics, AI, audio driver tick.

VBlank budget: ~2280 bytes via CGB HDMA, or ~¼ of that with CPU copies on DMG — plan asset streaming accordingly (decompress to WRAM during gameplay, blit in VBlank).

### Common techniques

- **Shadow OAM**: keep a 160-byte OAM buffer in WRAM (`ALIGN 8`); write sprites freely during gameplay, DMA it in VBlank.
- **Metasprites**: compose large characters from several 8×8/8×16 objects; store per-frame object lists (Y, X, tile, attr) in ROM.
- **Flicker on overflow**: rotate the OAM start index each frame so >10-object lines alternate which objects disappear.
- **HUD/status bar**: use the Window (e.g. WX=7, WY=128) — zero CPU cost, immune to SCX/SCY. To hide objects behind it, toggle LCDC.1 at the right scanline via LYC=LY interrupt.
- **Raster effects**: LYC=LY or Mode 0 STAT interrupts to change SCX/SCY/BGP per line (wavy scroll, perspective floors, palette gradients, screen splits).
- **Parallax**: multiple LYC zones with different SCX increments.
- **Screen transitions/fades**: step BGP through $E4→$90→$40→$00 (DMG) or interpolate RGB555 palettes (CGB).
- **Smooth motion**: objects move in pixel units; BG moves in pixels via SCX/SCY; when crossing tile boundaries, stream new tilemap columns/rows into VRAM during HBlank/VBlank.
- **Bank switching discipline**: keep the main loop + interrupt handlers + common routines in bank 0; call into banked code through trampoline stubs.
- **HRAM uses**: OAM DMA routine, hot variables (fast `ldh` access), time-critical inner loops.
- **Saves**: battery RAM at A000–BFFF; enable → write → disable; magic number + checksum + multiple save slots; MBC3 RTC for real-time events.

### Performance rules of thumb

- Copy via `ld a,[hl+]`/`ld [hl+],a` unrolled loops, or stack-pointer blasting (`ld sp, src` / `pop` …) for max throughput.
- `rst` for the hottest calls; `ldh` for I/O; keep hot data in HRAM.
- 16-bit math is expensive — prefer byte values, LUTs, and fixed-point.
- Align buffers to 256-byte pages so `inc l` suffices instead of `inc hl`.
- Multiply: LUTs or shift-add; no hardware multiply/divide.

---

## 19. Accessories

- **Game Boy Printer**: serial-protocol thermal printer. Communication over the link port with magic bytes ($88,$33), command packets (INIT, DATA, PRINT, INQUIRY), checksums; print with margins/palette/exposure. Used by GB Camera and a few games.
- **Game Boy Camera**: MBC-like cart with a 128×128 CMOS sensor; image RAM banked into A000–BFFF; registers control exposure, gain, edge enhancement, dithering. Photos extractable from saves (gbcamextract).
- **4-Player Adapter**: link-cable hub protocol with ID assignment and packet forwarding.
- **Game Genie / Game Shark**: cheat devices intercepting ROM reads; codes = address/value/compare encodings.

See Pan Docs chapters for protocol-level detail.

---

## 20. Resources & Further Reading

**Local (this repo):**

- `pandocs/src/` — full Pan Docs source (every chapter referenced above).
- `pdfs/GBCPUman.pdf` — GB CPU Manual v1.01 (instruction reference, SGB command details, timing diagrams).
- `awesome-gbdev/README.md` — curated links: tools, emulators, tutorials, homebrew source, disassemblies.

**Online:**

- Pan Docs (rendered): https://gbdev.io/pandocs
- GB opcode tables (incl. octal view): https://gbdev.io/gb-opcodes/optables
- RGBDS docs + gbz80(7) instruction reference: https://rgbds.gbdev.io/docs
- GB ASM Tutorial: https://gbdev.io/gb-asm-tutorial
- GBDK-2020: https://github.com/gbdk-2020/gbdk-2020
- hardware.inc: https://github.com/gbdev/hardware.inc
- Boot ROM disassemblies: https://codeberg.org/ISSOtm/gb-bootroms
- Test ROMs: mooneye-gb, SameSuite, Blargg's tests, 144p Test Suite
- DeadCScroll (raster effect sample): https://github.com/gb-archive/DeadCScroll
- Optimization: pokecrystal wiki "Optimizing assembly code"; WikiTI Z80 Optimization (adapt to SM83)
- Community: gbdev.io + GBDev Discord

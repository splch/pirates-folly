; Tile data: 8 terrain/UI tiles at $8000, 16 hex-font tiles at $8000+256.
; Hand-drawn with rgbasm gfx literals (backtick rows = 2 bytes each).

INCLUDE "hardware.inc"
INCLUDE "defs.inc"

SECTION "Tile loader", ROM0

LoadTiles::
    ld a, 3
    ld [$2000], a              ; map the data bank (tiles/sound/text live
                               ; in ROMX bank 3; it stays mapped except
                               ; during SGB border transfers)
    ld hl, TerrainTiles
    ld de, $8000
    ld bc, 8 * 16
    call CopyVRAM
    ld hl, ShipTiles
    ld de, $8000 + 8 * 16
    ld bc, 4 * 16
    call CopyVRAM
    ld hl, PortTiles
    ld de, $8000 + 13 * 16
    ld bc, 2 * 16
    call CopyVRAM
    ld hl, HexFont
    ld de, $8000 + 16 * 16
    ld bc, 16 * 16
    call CopyVRAM
    ld hl, LetterTiles
    ld de, $8000 + 32 * 16
    ld bc, 36 * 16
    call CopyVRAM
    ld hl, SplashTile
    ld de, $8000 + 15 * 16
    ld bc, 16
    call CopyVRAM
    ld hl, SkullTile
    ld de, $8000 + 68 * 16
    ld bc, 16
    call CopyVRAM
    ld hl, BallTile
    ld de, $8000 + 12 * 16
    ld bc, 16
    ; fall through
CopyVRAM::
    ld a, [hli]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, CopyVRAM
    ret

; ---------------------------------------------------------------------------
; CGB support (M6): palettes + one-time attribute-bank clear. LCD must be off.
; No-op unless the boot ROM left $11 in a (wIsCGB).
; ---------------------------------------------------------------------------
CGBInit::
    ld a, [wIsCGB]
    cp $11
    ret nz
    ; clear attribute banks of both BG maps ($9800/$9C00)
    VBK1
    xor a
    ld hl, $9800
    ld bc, 2048                  ; b = 8 pages, c wraps 256..1
.clr
    ld [hli], a
    dec c
    jr nz, .clr
    dec b
    jr nz, .clr
    VBK0
    ; BG palettes 0-3
    ld a, $80                      ; index 0, auto-increment
    ldh [rBGPI], a
    ld hl, CGB_BGP
    ld b, 32
.bgl
    ld a, [hli]
    ldh [rBGPD], a
    dec b
    jr nz, .bgl
    ; OBJ palettes 0-1
    ld a, $80
    ldh [rOBPI], a
    ld b, 16
.obl
    ld a, [hli]
    ldh [rOBPD], a
    dec b
    jr nz, .obl
    ret

PUSHS "CGB palette data", ROMX, BANK[3]
CGB_BGP:
    dw $7FFF, $5294, $2108, $0000  ; 0 UI: white/lt gray/dk gray/black
    dw $7F94, $7A8A, $5964, $34A1  ; 1 sea: foam -> deep navy
    dw $53BF, $32FC, $19F4, $0D0A  ; 2 sand: pale dune -> wet brown
    dw $43D6, $22CA, $11A4, $14E9  ; 3 land: light green -> rock
CGB_OBP:
    dw $7FFF, $2A5F, $1150, $0000  ; obj0 player: white/tan/brown/black
    dw $7FFF, $5294, $0850, $0000  ; obj1 pirate: white/gray/dark red/black
POPS

; 2-frame water animation: [deepA][shallowA][deepB][shallowB], 16 bytes each.
; SailVBlank copies one 32-byte pair over tiles 1-2 every 16 frames.
PUSHS "Water anim data", ROMX, BANK[3]
WaterFrames::
    dw `00000000
    dw `00000000
    dw `00100000
    dw `00000000
    dw `00000010
    dw `00000000
    dw `10000000
    dw `00000000
    dw `00000000
    dw `01001000
    dw `00000000
    dw `00010010
    dw `00000000
    dw `01001000
    dw `00000000
    dw `00010010
    ; phase B
    dw `00000000
    dw `00000000
    dw `00000001
    dw `00000000
    dw `01000000
    dw `00000000
    dw `00001000
    dw `00000000
    dw `00000000
    dw `00010010
    dw `00000000
    dw `01001000
    dw `00000000
    dw `00010010
    dw `00000000
    dw `01001000
POPS

; tiles 13-14: port marker (chart) + dock planks (in-world)
PortTiles:
    ; 13 TILE_PORT: little harbor house
    dw `00000000
    dw `00033000
    dw `00322300
    dw `03222230
    dw `32222223
    dw `33333333
    dw `33033033
    dw `33033033
    ; 14 TILE_DOCK: plank pier
    dw `33333333
    dw `30003000
    dw `33333333
    dw `03000300
    dw `33333333
    dw `30003000
    dw `33333333
    dw `00000000

; 8x8 ship, one tile per heading: N, E, S, W (tiles 8-11)
ShipTiles:
    ; N
    dw `00033000
    dw `00322300
    dw `03211230
    dw `03211230
    dw `03211230
    dw `03222230
    dw `00322300
    dw `00033000
    ; E
    dw `00000000
    dw `00033000
    dw `03322330
    dw `03122133
    dw `03122133
    dw `03322330
    dw `00033000
    dw `00000000
    ; S
    dw `00033000
    dw `00322300
    dw `03222230
    dw `03211230
    dw `03211230
    dw `03211230
    dw `00322300
    dw `00033000
    ; W
    dw `00000000
    dw `00033000
    dw `03322330
    dw `33122130
    dw `33122130
    dw `03322330
    dw `00033000
    dw `00000000

; Extra HUD letters: X, Y, S, P (tiles 32-35)
LetterTiles:
    dw `30300000
    dw `30300000
    dw `03000000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30300000
    dw `30300000
    dw `03000000
    dw `03000000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `03300000
    dw `30000000
    dw `03300000
    dw `00300000
    dw `33000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33000000
    dw `30300000
    dw `33000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
; 36 '>'
    dw `30000000
    dw `03000000
    dw `00300000
    dw `03000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
; 37 '.'
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
; 38 ':'
    dw `00000000
    dw `03000000
    dw `00000000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
; 39 space
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
; 40 A
    dw `03000000
    dw `30300000
    dw `33300000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 41 B
    dw `33000000
    dw `30300000
    dw `33000000
    dw `30300000
    dw `33000000
    dw `00000000
    dw `00000000
    dw `00000000
; 42 C
    dw `03300000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `03300000
    dw `00000000
    dw `00000000
    dw `00000000
; 43 D
    dw `33000000
    dw `30300000
    dw `30300000
    dw `30300000
    dw `33000000
    dw `00000000
    dw `00000000
    dw `00000000
; 44 E
    dw `33300000
    dw `30000000
    dw `33000000
    dw `30000000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 45 F
    dw `33300000
    dw `30000000
    dw `33000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
; 46 G
    dw `03300000
    dw `30000000
    dw `30300000
    dw `30300000
    dw `03300000
    dw `00000000
    dw `00000000
    dw `00000000
; 47 H
    dw `30300000
    dw `30300000
    dw `33300000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 48 I
    dw `33300000
    dw `03000000
    dw `03000000
    dw `03000000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 49 J
    dw `00300000
    dw `00300000
    dw `00300000
    dw `30300000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
; 50 K
    dw `30300000
    dw `30300000
    dw `33000000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 51 L
    dw `30000000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 52 M
    dw `30300000
    dw `33300000
    dw `33300000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 53 N
    dw `30300000
    dw `31300000
    dw `33300000
    dw `32300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 54 O
    dw `03000000
    dw `30300000
    dw `30300000
    dw `30300000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
; 55 P
    dw `33000000
    dw `30300000
    dw `33000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
; 56 Q
    dw `03000000
    dw `30300000
    dw `30300000
    dw `03000000
    dw `00300000
    dw `00000000
    dw `00000000
    dw `00000000
; 57 R
    dw `33000000
    dw `30300000
    dw `33000000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 58 S
    dw `03300000
    dw `30000000
    dw `03000000
    dw `00300000
    dw `33000000
    dw `00000000
    dw `00000000
    dw `00000000
; 59 T
    dw `33300000
    dw `03000000
    dw `03000000
    dw `03000000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
; 60 U
    dw `30300000
    dw `30300000
    dw `30300000
    dw `30300000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 61 V
    dw `30300000
    dw `30300000
    dw `30300000
    dw `30300000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
; 62 W
    dw `30300000
    dw `30300000
    dw `33300000
    dw `33300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 63 X
    dw `30300000
    dw `30300000
    dw `03000000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; 64 Y
    dw `30300000
    dw `30300000
    dw `03000000
    dw `03000000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
; 65 Z
    dw `33300000
    dw `00300000
    dw `03000000
    dw `30000000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 66 '/'
    dw `00300000
    dw `00300000
    dw `03000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000

; 67 '!'
    dw `03000000
    dw `03000000
    dw `03000000
    dw `03000000
    dw `03000000
    dw `00000000
    dw `03000000
    dw `00000000

SECTION "Tile data", ROMX, BANK[3]

TerrainTiles:
; 0 TILE_BLANK
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
; 1 TILE_DEEP — open water, sparse light dots
    dw `00000000
    dw `00000000
    dw `00100000
    dw `00000000
    dw `00000010
    dw `00000000
    dw `10000000
    dw `00000000
; 2 TILE_SHALLOW — coastal water, wave speckle
    dw `00000000
    dw `01001000
    dw `00000000
    dw `00010010
    dw `00000000
    dw `01001000
    dw `00000000
    dw `00010010
; 3 TILE_SAND
    dw `11111111
    dw `11211111
    dw `11111121
    dw `11111111
    dw `12111111
    dw `11111211
    dw `11111111
    dw `11121111
; 4 TILE_GRASS
    dw `22222222
    dw `22322222
    dw `22222232
    dw `22222222
    dw `23222222
    dw `22223222
    dw `22222222
    dw `22322222
; 5 TILE_FOREST
    dw `33333333
    dw `32233333
    dw `32223333
    dw `33333333
    dw `33333223
    dw `33332223
    dw `33333333
    dw `33333333
; 6 TILE_MOUNTAIN — dark with bright peaks
    dw `33333333
    dw `33033033
    dw `30030003
    dw `30030003
    dw `33333333
    dw `33303303
    dw `33003003
    dw `33333333
; 7 TILE_CURSOR — underline bar
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `33333333

HexFont:
; 3x5 pixel glyphs, top-left of the tile. 16 tiles: 0-9, A-F.
; 0
    dw `33300000
    dw `30300000
    dw `30300000
    dw `30300000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 1
    dw `03000000
    dw `33000000
    dw `03000000
    dw `03000000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 2
    dw `33300000
    dw `00300000
    dw `33300000
    dw `30000000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 3
    dw `33300000
    dw `00300000
    dw `03300000
    dw `00300000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 4
    dw `30300000
    dw `30300000
    dw `33300000
    dw `00300000
    dw `00300000
    dw `00000000
    dw `00000000
    dw `00000000
; 5
    dw `33300000
    dw `30000000
    dw `33300000
    dw `00300000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 6
    dw `33300000
    dw `30000000
    dw `33300000
    dw `30300000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 7
    dw `33300000
    dw `00300000
    dw `00300000
    dw `03000000
    dw `03000000
    dw `00000000
    dw `00000000
    dw `00000000
; 8
    dw `33300000
    dw `30300000
    dw `33300000
    dw `30300000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; 9
    dw `33300000
    dw `30300000
    dw `33300000
    dw `00300000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; A
    dw `03000000
    dw `30300000
    dw `33300000
    dw `30300000
    dw `30300000
    dw `00000000
    dw `00000000
    dw `00000000
; B
    dw `33000000
    dw `30300000
    dw `33000000
    dw `30300000
    dw `33000000
    dw `00000000
    dw `00000000
    dw `00000000
; C
    dw `03300000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `03300000
    dw `00000000
    dw `00000000
    dw `00000000
; D
    dw `33000000
    dw `30300000
    dw `30300000
    dw `30300000
    dw `33000000
    dw `00000000
    dw `00000000
    dw `00000000
; E
    dw `33300000
    dw `30000000
    dw `33000000
    dw `30000000
    dw `33300000
    dw `00000000
    dw `00000000
    dw `00000000
; F
    dw `33300000
    dw `30000000
    dw `33000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000

SECTION "Ball tile", ROMX, BANK[3]
BallTile:
    dw `00000000
    dw `00033000
    dw `00322300
    dw `03222230
    dw `03222230
    dw `00322300
    dw `00033000
    dw `00000000

SECTION "Splash tile", ROMX, BANK[3]
SplashTile:
    dw `00000000
    dw `03000030
    dw `00000000
    dw `30033003
    dw `00000000
    dw `03300330
    dw `00000000
    dw `00000000

SECTION "Skull tile", ROMX, BANK[3]
SkullTile:
    dw `00000000
    dw `03333300
    dw `33333330
    dw `33033033
    dw `33333330
    dw `03333300
    dw `00330300
    dw `00000000

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
    ld hl, ShoreTiles
    ld de, $8000 + 96 * 16
    ld bc, 6 * 16
    call CopyVRAM
    ld hl, ShoreSprites
    ld de, $8000 + 104 * 16
    ld bc, 17 * 16
    call CopyVRAM
    ld hl, SkullTile
    ld de, $8000 + 68 * 16
    ld bc, 16
    call CopyVRAM
    ld hl, BallTile
    ld de, $8000 + 12 * 16
    ld bc, 16
    call CopyVRAM
    ld hl, VariantTiles
    ld de, $8000 + 121 * 16
    ld bc, 4 * 16
    call CopyVRAM
    ; --- synthesize the transition tiles (Bayer-dither mixes) ---
    ld hl, TerrainTiles + 16         ; DEEP
    ld de, TerrainTiles + 32         ; SHALLOW
    ld b, 4
    ld a, TILE_DEEP_SH25
    call SynthTile
    ld hl, TerrainTiles + 16
    ld de, TerrainTiles + 32
    ld b, 8
    ld a, TILE_DEEP_SH50
    call SynthTile
    ld hl, TerrainTiles + 32         ; SHALLOW
    ld de, TerrainTiles + 16         ; DEEP
    ld b, 4
    ld a, TILE_SH_DEEP25
    call SynthTile
    ld hl, TerrainTiles + 32         ; SHALLOW
    ld de, TerrainTiles + 48         ; SAND
    ld b, 8
    ld a, TILE_SH_SAND50
    call SynthTile
    ld hl, TerrainTiles + 48         ; SAND
    ld de, TerrainTiles + 32         ; SHALLOW
    ld b, 4
    ld a, TILE_SAND_SH25
    call SynthTile
    ld hl, TerrainTiles + 48         ; SAND
    ld de, TerrainTiles + 64         ; GRASS
    ld b, 4
    ld a, TILE_SAND_GR25
    call SynthTile
    ld hl, TerrainTiles + 48
    ld de, TerrainTiles + 64
    ld b, 8
    ld a, TILE_SAND_GR50
    call SynthTile
    ld hl, TerrainTiles + 64         ; GRASS
    ld de, TerrainTiles + 48         ; SAND
    ld b, 4
    ld a, TILE_GR_SAND25
    call SynthTile
    ret

; 4x4 ordered-dither matrix (values 0-15); a pixel takes Q when its entry
; is below the ratio (4 = 25%, 8 = 50%, 12 = 75%).
BAYER4: db 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5

; in: hl = parent P (16 bytes), de = parent Q (16 bytes), b = Q ratio
; (4/8/12), a = destination tile id. Synthesizes into wMixBuf, then VRAM.
SynthTile:
    push af
    call MixTile
    pop af
    ld l, a
    ld h, 0
    REPT 4
    add hl, hl
    ENDR                            ; hl = tile id * 16
    ld de, $8000
    add hl, de
    push hl
    pop de
    ld hl, wMixBuf
    ld bc, 16
    jp CopyVRAM

; in: hl = P, de = Q, b = Q ratio. Fills wMixBuf (16 bytes).
MixTile:
    xor a
    ld [wMixRow], a
.rowLoop
    ld a, [hli]
    ld [wMixP], a
    ld a, [hli]
    ld [wMixP+1], a
    ld a, [de]
    inc de
    ld [wMixQ], a
    ld a, [de]
    inc de
    ld [wMixQ+1], a
    xor a
    ld [wMixI], a
.pxLoop
    ; selector: BAYER4[(row&3)*4 + (i&3)] < ratio ?
    ld a, [wMixRow]
    and 3
    add a
    add a
    ld c, a
    ld a, [wMixI]
    and 3
    add c
    ld e, a
    ld d, 0
    push hl
    ld hl, BAYER4
    add hl, de
    ld a, [hl]
    pop hl
    cp b
    jr c, .useQ
    ; take P's top bits into the output, then shift all four planes
    ld a, [wMixO]
    add a
    ld c, a
    ld a, [wMixP]
    add a
    ld [wMixP], a
    jr nc, .pLo
    inc c
.pLo
    ld a, c
    ld [wMixO], a
    ld a, [wMixO+1]
    add a
    ld c, a
    ld a, [wMixP+1]
    add a
    ld [wMixP+1], a
    jr nc, .pHi
    inc c
.pHi
    ld a, c
    ld [wMixO+1], a
    jr .shiftQ
.useQ
    ld a, [wMixO]
    add a
    ld c, a
    ld a, [wMixQ]
    add a
    ld [wMixQ], a
    jr nc, .qLo
    inc c
.qLo
    ld a, c
    ld [wMixO], a
    ld a, [wMixO+1]
    add a
    ld c, a
    ld a, [wMixQ+1]
    add a
    ld [wMixQ+1], a
    jr nc, .qHi
    inc c
.qHi
    ld a, c
    ld [wMixO+1], a
    ld a, [wMixP]
    add a
    ld [wMixP], a
    ld a, [wMixP+1]
    add a
    ld [wMixP+1], a
    jr .next
.shiftQ
    ld a, [wMixQ]
    add a
    ld [wMixQ], a
    ld a, [wMixQ+1]
    add a
    ld [wMixQ+1], a
.next
    ld a, [wMixI]
    inc a
    ld [wMixI], a
    cp 8
    jp nz, .pxLoop
    ; store the row's two bytes
    ld a, [wMixRow]
    add a
    ld e, a
    ld d, 0
    push hl
    ld hl, wMixBuf
    add hl, de
    ld a, [wMixO]
    ld [hli], a
    ld a, [wMixO+1]
    ld [hl], a
    pop hl
    ld a, [wMixRow]
    inc a
    ld [wMixRow], a
    cp 8
    jp nz, .rowLoop
    ret

; in: hl = src, de = dst, bc = count (must be a multiple of 8).
; Unrolled 8x: 3 instructions per byte instead of 7.
CopyVRAM::
    srl b
    rr c
    srl b
    rr c
    srl b
    rr c                         ; bc = count / 8
.loop
    REPT 8
    ld a, [hli]
    ld [de], a
    inc de
    ENDR
    dec bc
    ld a, b
    or c
    jr nz, .loop
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
    ; BG palettes 0-3 (AGB-corrected when the boot ROM flagged an AGB:
    ; its screen renders low 5-bit values nearly black, pandocs suggests
    ; per-field v -> 3v/4 + 8)
    ld a, $80                      ; index 0, auto-increment
    ldh [rBGPI], a
    ld c, LOW(rBGPD)
    ld hl, CGB_BGP
    ld b, 32                       ; 32 words = 8 palettes x 4 colors
.bgl
    call PalWord
    dec b
    jr nz, .bgl
    ; OBJ palettes 0-1
    ld a, $80
    ldh [rOBPI], a
    ld c, LOW(rOBPD)
    ld b, 8
.obl
    call PalWord
    dec b
    jr nz, .obl
    ret

; Write one RGB555 word from [hl+] to palette data register [c],
; AGB-corrected when wIsAGB. clobbers a, d, e (hl advanced by 2)
PalWord:
    ld a, [hli]
    ld e, a
    ld a, [hli]
    ld d, a                        ; de = color word (d high, e low)
    ld a, [wIsAGB]
    and a
    jr z, .plain
    push bc
    push hl
    ld h, d
    ld l, e
    call AGBFixColor
    ld d, h
    ld e, l
    pop hl
    pop bc
.plain
    ld a, e
    ldh [c], a
    ld a, d
    ldh [c], a
    ret

; in/out: hl = RGB555 color, each 5-bit field v -> (3v >> 2) + 8.
; clobbers a, b, c, d, e
AGBFixColor:
    push hl
    ld a, l
    and 31
    call .fix5
    ld c, a                        ; red'
    pop hl
    push hl
    SR16 h, l, 5
    ld a, l
    and 31
    call .fix5
    ld d, a                        ; green'
    pop hl
    SR16 h, l, 10
    ld a, l
    and 31
    call .fix5
    ld e, a                        ; blue'
    ; recombine: h = (green' >> 3) | (blue' << 2), l = (green' << 5) | red'
    ld h, 0
    ld l, d
    SR16 h, l, 3
    ld a, e
    add a
    add a
    or h
    ld h, a
    ld a, d
    REPT 5
    add a, a
    ENDR
    or c
    ld l, a
    ret
.fix5                            ; a = v (0..31) -> (3v >> 2) + 8 (max 31)
    ld b, a
    add a
    add b
    srl a
    srl a
    add 8
    ret

PUSHS "CGB palette data", ROMX, BANK[3]
CGB_BGP:
    dw $7FFF, $5294, $2108, $0000  ; 0 UI: white/lt gray/dk gray/black
    dw $7F75, $6A6D, $4D67, $2CA3  ; 1 deep sea: foam -> navy
    dw $53BF, $32FC, $19F4, $0D0A  ; 2 sand: pale dune -> wet brown
    dw $2F33, $1E6B, $1186, $0CE3  ; 3 grass: light meadow -> loam
    dw $73D7, $5B0F, $4209, $2924  ; 4 shallow: lagoon -> teal
    dw $1E09, $1565, $0CE3, $0882  ; 5 forest: canopy -> undergrowth
    dw $6F7B, $4E31, $3129, $1C84  ; 6 mountain: snow -> slate
    dw $7FFF, $5294, $2108, $0000  ; 7 spare (UI copy)
CGB_OBP:
    dw $7FFF, $2A5F, $1150, $0000  ; obj0 player: white/tan/brown/black
    dw $7FFF, $5294, $0850, $0000  ; obj1 pirate: white/gray/dark red/black
POPS

; 4-phase water animation: [deep][shallow] per phase, 16 bytes each.
; SailVBlank copies one 32-byte pair over tiles 1-2 every 16 frames.
; Every row is 4-periodic (abcdabcd), so drifting right one pixel per
; phase loops exactly (rotation == shift across tile boundaries).
; ROM0: AnimWater (also ROM0) reads it for both sailing and shore mode.
PUSHS "Water anim data", ROM0
WaterFrames::
    ; --- phase 0 ---
    ; deep
    dw `00000000
    dw `00110011
    dw `00000000
    dw `00000000
    dw `01100110
    dw `00000000
    dw `00000000
    dw `00000000
    ; shallow
    dw `00100010
    dw `00000000
    dw `01100110
    dw `00000000
    dw `00010001
    dw `00000000
    dw `01100110
    dw `00000000
    ; --- phase 1 (drifted right 1 px) ---
    dw `00000000
    dw `10011001
    dw `00000000
    dw `00000000
    dw `00110011
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00010001
    dw `00000000
    dw `00110011
    dw `00000000
    dw `10001000
    dw `00000000
    dw `00110011
    dw `00000000
    ; --- phase 2 ---
    dw `00000000
    dw `11001100
    dw `00000000
    dw `00000000
    dw `10011001
    dw `00000000
    dw `00000000
    dw `00000000
    dw `10001000
    dw `00000000
    dw `10011001
    dw `00000000
    dw `01000100
    dw `00000000
    dw `10011001
    dw `00000000
    ; --- phase 3 ---
    dw `00000000
    dw `01100110
    dw `00000000
    dw `00000000
    dw `11001100
    dw `00000000
    dw `00000000
    dw `00000000
    dw `01000100
    dw `00000000
    dw `11001100
    dw `00000000
    dw `00100010
    dw `00000000
    dw `11001100
    dw `00000000
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
    ; 14 TILE_DOCK: plank pier with nail heads
    dw `33333333
    dw `30203020
    dw `33333333
    dw `32030203
    dw `33333333
    dw `30203020
    dw `33333333
    dw `00000000

; 8x8 ship, one tile per heading: N, E, S, W (tiles 8-11)
; light sail (1), deck (2), hull outline (3)
ShipTiles:
    ; N
    dw `00003000
    dw `00031300
    dw `00311130
    dw `00311130
    dw `00322230
    dw `00322230
    dw `00033000
    dw `00000000
    ; E
    dw `00000000
    dw `00333300
    dw `03112230
    dw `03112230
    dw `03112230
    dw `00333300
    dw `00000000
    dw `00000000
    ; S
    dw `00000000
    dw `00033000
    dw `00322230
    dw `00322230
    dw `00311130
    dw `00311130
    dw `00031300
    dw `00003000
    ; W
    dw `00000000
    dw `00333300
    dw `03221130
    dw `03221130
    dw `03221130
    dw `00333300
    dw `00000000
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
; 1 TILE_DEEP — open water: sparse 4-periodic wavelets (WaterFrames phase 0)
    dw `00000000
    dw `00110011
    dw `00000000
    dw `00000000
    dw `01100110
    dw `00000000
    dw `00000000
    dw `00000000
; 2 TILE_SHALLOW — wavelets + glints: visibly busier (WaterFrames phase 0)
    dw `00100010
    dw `00000000
    dw `01100110
    dw `00000000
    dw `00010001
    dw `00000000
    dw `01100110
    dw `00000000
; 3 TILE_SAND — clustered grain with shell flecks
    dw `11111111
    dw `12111211
    dw `11111111
    dw `11212111
    dw `11110111
    dw `12111212
    dw `11111111
    dw `01121111
; 4 TILE_GRASS — blade tufts (2px strokes)
    dw `22222222
    dw `22322223
    dw `22322232
    dw `22222222
    dw `23222322
    dw `23222322
    dw `22222222
    dw `22232222
; 5 TILE_FOREST — canopy blobs over dark undergrowth
    dw `33333333
    dw `32233233
    dw `32223323
    dw `33333333
    dw `33233223
    dw `32333223
    dw `33333333
    dw `33333333
; 6 TILE_MOUNTAIN — snow-capped crags: triangular peaks, bright cap
    dw `33333333
    dw `33033033
    dw `32233223
    dw `32333233
    dw `33333333
    dw `33303303
    dw `33223322
    dw `33323332
; 7 TILE_CURSOR — underline bar
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `33333333

; tiles 121-124: sea-terrain visual variants (DecorateTile, world.asm).
; Render-only substitutes for the canonical tiles 2-5.
VariantTiles:
; 121 TILE_SHALLOW2 — foam-flecked shallow (near-coast band)
    dw `00100010
    dw `00000000
    dw `01100110
    dw `00000100
    dw `00010001
    dw `00100000
    dw `01100110
    dw `00000000
; 122 TILE_SAND2 — shells and pebbles
    dw `11111111
    dw `12111211
    dw `11011111
    dw `11212111
    dw `11110111
    dw `12131212
    dw `11111111
    dw `01121110
; 123 TILE_GRASS2 — flowered tufts
    dw `22222222
    dw `22322221
    dw `22322222
    dw `22212222
    dw `23222322
    dw `23222322
    dw `22221222
    dw `22232222
; 124 TILE_FOREST2 — sparse canopy, gaps of undergrowth
    dw `33333333
    dw `33233333
    dw `32233332
    dw `33333333
    dw `33332233
    dw `33332233
    dw `33333333
    dw `33333333

HexFont:
; 3x5 pixel glyphs, top-left of the tile. 16 tiles: 0-9, A-F.
; NOTE: A-F exist twice — here (tiles 26-31, so hex nibbles print as
; value + TILE_HEX0) and as letters A-F (tiles 40-45, charmap). 96 B of
; duplicated tile data buys much simpler hex-print code everywhere; ROM is
; not tight enough to matter. Deliberate — don't merge them.
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

; Shore mode art lives in ROM0: LoadTiles reads it with any bank mapped.
SECTION "Shore tile data", ROM0
ShoreTiles:
; 96 TILE_SH_GRASS — fine meadow speckle
    dw `22222222
    dw `22232222
    dw `22222222
    dw `22222232
    dw `22322222
    dw `22222222
    dw `22232222
    dw `22222222
; 97 TILE_SH_GRASS2 — grassy tufts
    dw `22222222
    dw `22322322
    dw `22222222
    dw `22232232
    dw `22222222
    dw `22322232
    dw `22222222
    dw `22232222
; 98 TILE_SH_TREE — canopy + trunk (blocks movement)
    dw `00233200
    dw `02333320
    dw `23333332
    dw `23333332
    dw `02333320
    dw `00233200
    dw `00033000
    dw `00033000
; 99 TILE_SH_ROCK — boulder (blocks movement)
    dw `00000000
    dw `00233200
    dw `02322320
    dw `23222232
    dw `32222223
    dw `32222223
    dw `03222230
    dw `00333300
; 100 TILE_SH_FLOWER — meadow flowers (walkable)
    dw `22222222
    dw `22212222
    dw `22121222
    dw `22212222
    dw `22222222
    dw `22222212
    dw `22221212
    dw `22222222
; 101 TILE_SH_MTN — craggy peak (blocks movement)
    dw `00000000
    dw `00033000
    dw `00322300
    dw `03211230
    dw `32122123
    dw `32222223
    dw `33333333
    dw `00000000

SECTION "Shore sprite data", ROM0
ShoreSprites:
; 104 player N (walking pirate, back view)
    dw `00000000
    dw `00033000
    dw `00333300
    dw `00011000
    dw `00222200
    dw `00222200
    dw `00022000
    dw `00200200
; 105 player E
    dw `00000000
    dw `00033000
    dw `00333300
    dw `00011300
    dw `00222100
    dw `00222200
    dw `00022000
    dw `00200200
; 106 player S
    dw `00000000
    dw `00033000
    dw `00333300
    dw `00122100
    dw `00222200
    dw `00222200
    dw `00022000
    dw `00200200
; 107 player W
    dw `00000000
    dw `00033000
    dw `00333300
    dw `00311000
    dw `00122000
    dw `00222000
    dw `00022000
    dw `00200200
; 108 TILE_DINGHY — rowboat with oars, top-down
    dw `00000000
    dw `00000000
    dw `00333300
    dw `03222230
    dw `13211231
    dw `03222230
    dw `00333300
    dw `00000000
; 109 TILE_SITE_CHEST — treasure chest
    dw `00000000
    dw `00333300
    dw `03222230
    dw `32222223
    dw `33333333
    dw `32122123
    dw `32222223
    dw `03333330
; 110 TILE_SITE_DEBRIS — washed-up barrel
    dw `00000000
    dw `00333300
    dw `03222230
    dw `32122123
    dw `32222223
    dw `32122123
    dw `03222230
    dw `00333300
; 111 TILE_SITE_GIBBET — gallows with a hanging man
    dw `00333300
    dw `00010010
    dw `00010110
    dw `00010200
    dw `00010200
    dw `00010000
    dw `00333300
    dw `00000000
; 112 TILE_SITE_SKULL — skull on a pole
    dw `00000000
    dw `00033000
    dw `00311300
    dw `00333000
    dw `00020000
    dw `00020000
    dw `00020000
    dw `00222200
; 113 TILE_DIGX — X marks the spot
    dw `00000000
    dw `03000030
    dw `00300300
    dw `00033000
    dw `00033000
    dw `00300300
    dw `03000030
    dw `00000000
; 114 TILE_SNAKE — coiled, head raised
    dw `00000000
    dw `00133000
    dw `01313000
    dw `00300000
    dw `00033300
    dw `00000300
    dw `00333000
    dw `00000000
; 115 TILE_SKEL — shambling skeleton, ribs and arms
    dw `00033000
    dw `00311300
    dw `00033000
    dw `00020000
    dw `02222200
    dw `00202000
    dw `00202000
    dw `00200200
; 116 TILE_COIN
    dw `00000000
    dw `00033000
    dw `00322300
    dw `03222230
    dw `03222230
    dw `00322300
    dw `00033000
    dw `00000000
; 117 TILE_TAVERN — a foaming mug, head spilling over
    dw `00000000
    dw `00110000
    dw `00333300
    dw `03222233
    dw `03222230
    dw `03222230
    dw `00333300
    dw `00000000
; 118 TILE_MARKET — a stack of coin with a glint
    dw `00000000
    dw `00011000
    dw `00322300
    dw `03222230
    dw `00033000
    dw `00322300
    dw `03222230
    dw `00000000
; 119 TILE_SHIPYARD — an anchor
    dw `00030000
    dw `00333000
    dw `00030000
    dw `03333330
    dw `03030030
    dw `03030030
    dw `00333000
    dw `00000000
; 120 TILE_HARBOR — the harbor bell, clapper out
    dw `00030000
    dw `00333000
    dw `03222230
    dw `03222230
    dw `03222230
    dw `03333330
    dw `00030000
    dw `00020000

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
    dw `03000030
    dw `00300300
    dw `00033000
    dw `03333330
    dw `00033000
    dw `00300300
    dw `03000030
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

SECTION "Mixer scratch", WRAM0
wMixP:   ds 2
wMixQ:   ds 2
wMixO:   ds 2
wMixRow: db
wMixI:   db
wMixBuf: ds 16

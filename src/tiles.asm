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
    ld hl, ScreenTiles
    ld de, $8000 + 134 * 16
    ld bc, 3 * 16
    call CopyVRAM
    ld hl, WaterFrames + 32        ; initial phase-0 pixels for the
    ld de, $8000 + 137 * 16        ; variant waters (AnimWater syncs them)
    ld bc, 32
    call CopyVRAM
    ld hl, WaterFrames + 64
    ld de, $8000 + 155 * 16
    ld bc, 16
    call CopyVRAM
    ld hl, EmblemTiles
    ld de, $8000 + TILE_EMBLEM * 16
    ld bc, 16 * 16
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

; 139-154 TILE_EMBLEM: skull & crossbones, 4x4 tiles (title screen)
EmblemTiles:
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000033
    dw `00000033
    dw `00000033
    dw `00000000
    dw `00033333
    dw `03333333
    dw `33333333
    dw `33333333
    dw `30000333
    dw `30000333
    dw `30000333
    dw `00000000
    dw `33333000
    dw `33333330
    dw `33333333
    dw `33333333
    dw `33300003
    dw `33300003
    dw `33300003
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `33000000
    dw `33000000
    dw `33000000
    dw `00000033
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `33333333
    dw `33333330
    dw `33333330
    dw `03333333
    dw `03333033
    dw `00333033
    dw `00033333
    dw `33333333
    dw `33333333
    dw `03333333
    dw `03333333
    dw `33333330
    dw `03303330
    dw `03303300
    dw `33333000
    dw `33000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00003330
    dw `00003333
    dw `00003333
    dw `00000033
    dw `00000033
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33000000
    dw `33330000
    dw `33333300
    dw `00333333
    dw `00003333
    dw `00033333
    dw `00000003
    dw `00000003
    dw `00000033
    dw `00003333
    dw `00333333
    dw `33333300
    dw `33330000
    dw `33333000
    dw `33000000
    dw `33000000
    dw `33330000
    dw `33330000
    dw `03330000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00033303
    dw `00033333
    dw `00033333
    dw `00000333
    dw `00000333
    dw `00000000
    dw `00000000
    dw `03333333
    dw `33333000
    dw `33300000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333330
    dw `00033333
    dw `00000333
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33300000
    dw `33300000
    dw `33333000
    dw `03333000
    dw `00333000
    dw `00000000
    dw `00000000

PUSHS "CGB palette data", ROMX, BANK[3]
CGB_BGP:
    dw $7FFF, $5294, $2108, $0000  ; 0 UI: white/lt gray/dk gray/black
    dw $7FDA, $7AEE, $69C6, $4903  ; 1 deep sea: foam -> navy
    dw $53BF, $32DB, $1DF4, $112C  ; 2 sand: pale dune -> wet brown
    dw $3BB6, $26ED, $1A08, $1144  ; 3 grass: light meadow -> loam
    dw $7BF8, $634A, $4E45, $3542  ; 4 shallow: lagoon -> teal
    dw $2F0D, $2269, $15A5, $0D03  ; 5 forest: canopy -> undergrowth
    dw $7BBD, $5E94, $418C, $28C6  ; 6 mountain: snow -> slate
    dw $7FFF, $5294, $2108, $0000  ; 7 spare (UI copy)
CGB_OBP:
    dw $7FFF, $32DA, $1550, $0000  ; obj0 player: white/tan/brown/black
    dw $7FFF, $5294, $0850, $0000  ; obj1 pirate: white/gray/dark red/black
POPS

; 4-phase water animation: [deep][shallow][deep2][shallow3][deep3] per
; phase, 16 bytes each. AnimWater copies one 80-byte phase over tiles 1-2,
; 137-138, and 155 every 16 frames.
; Every row is 4-periodic (abcdabcd), so drifting right one pixel per
; phase loops exactly (rotation == shift across tile boundaries).
; ROM0: AnimWater (also ROM0) reads it for both sailing and shore mode.
PUSHS "Water anim data", ROM0
WaterFrames::
    ; --- phase 0 ---
    ; deep
    dw `00000000
    dw `00000000
    dw `01100110
    dw `10001000
    dw `00000000
    dw `00000000
    dw `00100010
    dw `00000000
    ; shallow
    dw `00000000
    dw `01000100
    dw `01100110
    dw `10001000
    dw `00000000
    dw `00000000
    dw `00100010
    dw `00000000
    ; deep2
    dw `00000000
    dw `00000000
    dw `00000000
    dw `11001100
    dw `00010001
    dw `00000000
    dw `01000100
    dw `00000000
    ; shallow3
    dw `00000000
    dw `00100010
    dw `00000000
    dw `11001100
    dw `00010001
    dw `00000000
    dw `01000100
    dw `00000000
    ; deep3
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `01100110
    dw `10001000
    dw `00000000
    ; --- phase 1 ---
    ; deep
    dw `00000000
    dw `00000000
    dw `00110011
    dw `01000100
    dw `00000000
    dw `00000000
    dw `00010001
    dw `00000000
    ; shallow
    dw `00000000
    dw `00100010
    dw `00110011
    dw `01000100
    dw `00000000
    dw `00000000
    dw `00010001
    dw `00000000
    ; deep2
    dw `00000000
    dw `00000000
    dw `00000000
    dw `01100110
    dw `10001000
    dw `00000000
    dw `00100010
    dw `00000000
    ; shallow3
    dw `00000000
    dw `00010001
    dw `00000000
    dw `01100110
    dw `10001000
    dw `00000000
    dw `00100010
    dw `00000000
    ; deep3
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00110011
    dw `01000100
    dw `00000000
    ; --- phase 2 ---
    ; deep
    dw `00000000
    dw `00000000
    dw `10011001
    dw `00100010
    dw `00000000
    dw `00000000
    dw `10001000
    dw `00000000
    ; shallow
    dw `00000000
    dw `00010001
    dw `10011001
    dw `00100010
    dw `00000000
    dw `00000000
    dw `10001000
    dw `00000000
    ; deep2
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00110011
    dw `01000100
    dw `00000000
    dw `00010001
    dw `00000000
    ; shallow3
    dw `00000000
    dw `10001000
    dw `00000000
    dw `00110011
    dw `01000100
    dw `00000000
    dw `00010001
    dw `00000000
    ; deep3
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `10011001
    dw `00100010
    dw `00000000
    ; --- phase 3 ---
    ; deep
    dw `00000000
    dw `00000000
    dw `11001100
    dw `00010001
    dw `00000000
    dw `00000000
    dw `01000100
    dw `00000000
    ; shallow
    dw `00000000
    dw `10001000
    dw `11001100
    dw `00010001
    dw `00000000
    dw `00000000
    dw `01000100
    dw `00000000
    ; deep2
    dw `00000000
    dw `00000000
    dw `00000000
    dw `10011001
    dw `00100010
    dw `00000000
    dw `10001000
    dw `00000000
    ; shallow3
    dw `00000000
    dw `01000100
    dw `00000000
    dw `10011001
    dw `00100010
    dw `00000000
    dw `10001000
    dw `00000000
    ; deep3
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `11001100
    dw `00010001
    dw `00000000
POPS

; tiles 13-14: port marker (chart) + dock planks (in-world)
PortTiles:
    ; 13 TILE_PORT: little harbor house — gabled roof, door and window
    dw `00000000
    dw `00033000
    dw `00333300
    dw `03322330
    dw `33322333
    dw `03222230
    dw `03232330
    dw `03333330
    ; 14 TILE_DOCK: wooden pier — plank bands, dark seams, one nail each
    dw `22222222
    dw `22322222
    dw `33333333
    dw `22222222
    dw `22222232
    dw `33333333
    dw `22222222
    dw `22322222

; 8x8 ship, one tile per heading: N, E, S, W (tiles 8-11)
; light sail (1), deck (2), hull outline (3); pointy bow, square stern,
; sail billows full amidships
ShipTiles:
    ; N
    dw `00033000
    dw `00311300
    dw `03111130
    dw `03111130
    dw `03111130
    dw `03211230
    dw `03222230
    dw `00333300
    ; E
    dw `00000000
    dw `03333300
    dw `32222223
    dw `32111113
    dw `32111113
    dw `32222223
    dw `03333300
    dw `00000000
    ; S
    dw `00333300
    dw `03222230
    dw `03211230
    dw `03111130
    dw `03111130
    dw `03111130
    dw `00311300
    dw `00033000
    ; W
    dw `00000000
    dw `00333330
    dw `32222223
    dw `31111123
    dw `31111123
    dw `32222223
    dw `00333330
    dw `00000000

; Extra HUD letters: X, Y, S, P (tiles 32-35) — same glyphs as 63/64/58/55
LetterTiles:
    dw `30003000
    dw `30003000
    dw `03030000
    dw `00300000
    dw `03030000
    dw `30003000
    dw `30003000
    dw `00000000
    dw `30003000
    dw `30003000
    dw `03030000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00000000
    dw `03333000
    dw `30000000
    dw `30000000
    dw `03330000
    dw `00030000
    dw `00030000
    dw `33330000
    dw `00000000
    dw `33330000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `00000000
; 36 '>'
    dw `30000000
    dw `03000000
    dw `00300000
    dw `00030000
    dw `00300000
    dw `03000000
    dw `30000000
    dw `00000000
; 37 '.'
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `03300000
    dw `03300000
    dw `00000000
; 38 ':'
    dw `00000000
    dw `03300000
    dw `03300000
    dw `00000000
    dw `03300000
    dw `03300000
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
    dw `03330000
    dw `30003000
    dw `30003000
    dw `33333000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `00000000
; 41 B
    dw `33330000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `00000000
; 42 C
    dw `03330000
    dw `30003000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `30003000
    dw `03330000
    dw `00000000
; 43 D
    dw `33330000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `00000000
; 44 E
    dw `33333000
    dw `30000000
    dw `30000000
    dw `33330000
    dw `30000000
    dw `30000000
    dw `33333000
    dw `00000000
; 45 F
    dw `33333000
    dw `30000000
    dw `30000000
    dw `33330000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `00000000
; 46 G
    dw `03330000
    dw `30003000
    dw `30000000
    dw `30333000
    dw `30003000
    dw `30003000
    dw `03330000
    dw `00000000
; 47 H
    dw `30003000
    dw `30003000
    dw `30003000
    dw `33333000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `00000000
; 48 I
    dw `03330000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `03330000
    dw `00000000
; 49 J
    dw `00333000
    dw `00030000
    dw `00030000
    dw `00030000
    dw `00030000
    dw `30030000
    dw `03300000
    dw `00000000
; 50 K
    dw `30003000
    dw `30030000
    dw `30300000
    dw `33000000
    dw `30300000
    dw `30030000
    dw `30003000
    dw `00000000
; 51 L
    dw `30000000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `33333000
    dw `00000000
; 52 M
    dw `30003000
    dw `33033000
    dw `30303000
    dw `30303000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `00000000
; 53 N
    dw `30003000
    dw `30003000
    dw `33003000
    dw `30303000
    dw `30033000
    dw `30003000
    dw `30003000
    dw `00000000
; 54 O
    dw `03330000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `03330000
    dw `00000000
; 55 P
    dw `33330000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `00000000
; 56 Q
    dw `03330000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30303000
    dw `30030000
    dw `03303000
    dw `00000000
; 57 R
    dw `33330000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `30300000
    dw `30030000
    dw `30003000
    dw `00000000
; 58 S
    dw `03333000
    dw `30000000
    dw `30000000
    dw `03330000
    dw `00030000
    dw `00030000
    dw `33330000
    dw `00000000
; 59 T
    dw `33333000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00000000
; 60 U
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `03330000
    dw `00000000
; 61 V
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `03030000
    dw `00300000
    dw `00000000
; 62 W
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30303000
    dw `30303000
    dw `33033000
    dw `30003000
    dw `00000000
; 63 X
    dw `30003000
    dw `30003000
    dw `03030000
    dw `00300000
    dw `03030000
    dw `30003000
    dw `30003000
    dw `00000000
; 64 Y
    dw `30003000
    dw `30003000
    dw `03030000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00000000
; 65 Z
    dw `33333000
    dw `00003000
    dw `00030000
    dw `00300000
    dw `03000000
    dw `30000000
    dw `33333000
    dw `00000000
; 66 '/'
    dw `00003000
    dw `00003000
    dw `00030000
    dw `00300000
    dw `03000000
    dw `30000000
    dw `30000000
    dw `00000000

; 67 '!'
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00000000
    dw `00300000
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
; 1 TILE_DEEP — open water: little curling waves (WaterFrames phase 0)
    dw `00000000
    dw `00000000
    dw `01100110
    dw `10001000
    dw `00000000
    dw `00000000
    dw `00100010
    dw `00000000
; 2 TILE_SHALLOW — waves + a foam-glint row (WaterFrames phase 0)
    dw `00000000
    dw `01000100
    dw `01100110
    dw `10001000
    dw `00000000
    dw `00000000
    dw `00100010
    dw `00000000
; 3 TILE_SAND — flat beach, two pebble clusters
    dw `11111111
    dw `11111111
    dw `11221111
    dw `11221111
    dw `11111111
    dw `11111122
    dw `11111122
    dw `11111111
; 4 TILE_GRASS — calm meadow, two blade tufts
    dw `22222222
    dw `22222222
    dw `22322222
    dw `22322222
    dw `22222222
    dw `22222232
    dw `22222232
    dw `22222222
; 5 TILE_FOREST — two bold canopy clumps on undergrowth
    dw `22222222
    dw `22333222
    dw `23333322
    dw `23333222
    dw `22222223
    dw `22222333
    dw `22222333
    dw `22222233
; 6 TILE_MOUNTAIN — shaded crag: sunlit west face, shadowed east face
    dw `22222222
    dw `22213222
    dw `22113322
    dw `22113322
    dw `21133332
    dw `22222222
    dw `22222222
    dw `22222222
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
; 121 TILE_SHALLOW2 — calm foam-fleck band near the sand (static)
    dw `00000000
    dw `01000100
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00100010
    dw `00000000
; 122 TILE_SAND2 — pebbles in a different spot
    dw `11111111
    dw `11122111
    dw `11122111
    dw `11111111
    dw `11111111
    dw `12211111
    dw `12211111
    dw `11111111
; 123 TILE_GRASS2 — tufts elsewhere, one light fleck
    dw `22222222
    dw `23222222
    dw `23222222
    dw `22222222
    dw `22222222
    dw `22223222
    dw `22223221
    dw `22222222
; 124 TILE_FOREST2 — one sparse canopy clump
    dw `22222222
    dw `22222222
    dw `22332222
    dw `23333222
    dw `23322222
    dw `22222222
    dw `22222222
    dw `22222222

; tiles 134-136: screen-dressing glyphs
ScreenTiles:
; 134 TILE_COMPASS — eight-point rose (white & ink on parchment)
    dw `00030000
    dw `00313000
    dw `03030300
    dw `33133133
    dw `03030300
    dw `00313000
    dw `00030000
    dw `00000000
; 135 TILE_GULL — two soaring arcs, one high one low
    dw `00000000
    dw `00000000
    dw `03000300
    dw `33033033
    dw `00000000
    dw `00300300
    dw `03033030
    dw `00000000
; 136 TILE_FRAME — double rule near the top
    dw `00000000
    dw `33333333
    dw `00000000
    dw `33333333
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

HexFont:
; 5x7 pixel glyphs. 16 tiles: 0-9, A-F.
; NOTE: A-F exist twice — here (tiles 26-31, so hex nibbles print as
; value + TILE_HEX0) and as letters A-F (tiles 40-45, charmap). 96 B of
; duplicated tile data buys much simpler hex-print code everywhere; ROM is
; not tight enough to matter. Deliberate — don't merge them.
; 0
    dw `03330000
    dw `30003000
    dw `30033000
    dw `30303000
    dw `33003000
    dw `30003000
    dw `03330000
    dw `00000000
; 1
    dw `00300000
    dw `03300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `03330000
    dw `00000000
; 2
    dw `03330000
    dw `30003000
    dw `00003000
    dw `00330000
    dw `03000000
    dw `30000000
    dw `33333000
    dw `00000000
; 3
    dw `33330000
    dw `00003000
    dw `00003000
    dw `03330000
    dw `00003000
    dw `00003000
    dw `33330000
    dw `00000000
; 4
    dw `00030000
    dw `00330000
    dw `03030000
    dw `30030000
    dw `33333000
    dw `00030000
    dw `00030000
    dw `00000000
; 5
    dw `33333000
    dw `30000000
    dw `33330000
    dw `00003000
    dw `00003000
    dw `30003000
    dw `03330000
    dw `00000000
; 6
    dw `03330000
    dw `30000000
    dw `30000000
    dw `33330000
    dw `30003000
    dw `30003000
    dw `03330000
    dw `00000000
; 7
    dw `33333000
    dw `00003000
    dw `00030000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00000000
; 8
    dw `03330000
    dw `30003000
    dw `30003000
    dw `03330000
    dw `30003000
    dw `30003000
    dw `03330000
    dw `00000000
; 9
    dw `03330000
    dw `30003000
    dw `30003000
    dw `03333000
    dw `00003000
    dw `00003000
    dw `03330000
    dw `00000000
; A
    dw `03330000
    dw `30003000
    dw `30003000
    dw `33333000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `00000000
; B
    dw `33330000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `00000000
; C
    dw `03330000
    dw `30003000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `30003000
    dw `03330000
    dw `00000000
; D
    dw `33330000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `30003000
    dw `33330000
    dw `00000000
; E
    dw `33333000
    dw `30000000
    dw `30000000
    dw `33330000
    dw `30000000
    dw `30000000
    dw `33333000
    dw `00000000
; F
    dw `33333000
    dw `30000000
    dw `30000000
    dw `33330000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `00000000

; Shore mode art lives in ROM0: LoadTiles reads it with any bank mapped.
SECTION "Shore tile data", ROM0
ShoreTiles:
; 96 TILE_SH_GRASS — calm meadow, two tuft marks
    dw `22222222
    dw `22222222
    dw `22322222
    dw `22222222
    dw `22222232
    dw `22222222
    dw `22222222
    dw `22222222
; 97 TILE_SH_GRASS2 — tufts elsewhere
    dw `22222222
    dw `22322232
    dw `22222222
    dw `22222222
    dw `23222222
    dw `22222222
    dw `22222223
    dw `22222222
; 98 TILE_SH_TREE — round canopy with highlight + trunk (blocks movement)
    dw `00233200
    dw `02331320
    dw `23333332
    dw `23333332
    dw `02333320
    dw `00233200
    dw `00033000
    dw `00033000
; 99 TILE_SH_ROCK — shaded boulder with a bright face (blocks movement)
    dw `00000000
    dw `00332200
    dw `03222230
    dw `32222223
    dw `32211223
    dw `32222223
    dw `03222230
    dw `00333300
; 100 TILE_SH_FLOWER — one flower, one bud (walkable)
    dw `22222222
    dw `22212222
    dw `22121222
    dw `22212222
    dw `22222222
    dw `22222222
    dw `22221212
    dw `22222222
; 101 TILE_SH_MTN — snow-capped crag (blocks movement)
    dw `00000000
    dw `00033000
    dw `00311300
    dw `03211230
    dw `32122123
    dw `32222223
    dw `33333333
    dw `00000000

SECTION "Shore sprite data", ROM0
ShoreSprites:
; 104 player N (walking pirate, back view: bandana, coat, boots)
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
; 108 TILE_DINGHY — rowboat with bench seats, top-down
    dw `00000000
    dw `00333300
    dw `03222230
    dw `03211130
    dw `03222230
    dw `03211130
    dw `03222230
    dw `00333300
; 109 TILE_SITE_CHEST — treasure chest, banded lid and lock
    dw `00000000
    dw `00333300
    dw `03222230
    dw `32122123
    dw `33333333
    dw `32222223
    dw `32322323
    dw `03333330
; 110 TILE_SITE_DEBRIS — washed-up barrel with hoops
    dw `00000000
    dw `00333300
    dw `03222130
    dw `32222223
    dw `32122123
    dw `32222223
    dw `03222130
    dw `00333300
; 111 TILE_SITE_GIBBET — gallows with a hanging man
    dw `00333300
    dw `00300300
    dw `00301300
    dw `00303000
    dw `00330000
    dw `00300000
    dw `00300000
    dw `03333300
; 112 TILE_SITE_SKULL — skull on a pole
    dw `00000000
    dw `00033000
    dw `00311300
    dw `00333300
    dw `00033000
    dw `00030000
    dw `00030000
    dw `00333000
; 113 TILE_DIGX — bold X marks the spot
    dw `00000000
    dw `03300030
    dw `00330300
    dw `00033000
    dw `00033000
    dw `00330300
    dw `03300030
    dw `00000000
; 114 TILE_SNAKE — coiled, head raised
    dw `00000000
    dw `00133000
    dw `03130300
    dw `00300000
    dw `00333000
    dw `00003000
    dw `03333000
    dw `00000000
; 115 TILE_SKEL — shambling skeleton, ribs and arms
    dw `00033000
    dw `00311300
    dw `00033000
    dw `00030000
    dw `03232300
    dw `00333000
    dw `00303000
    dw `00300300
; 116 TILE_COIN — gold piece with a stamped face
    dw `00000000
    dw `00033000
    dw `00322300
    dw `03221230
    dw `03221230
    dw `00322300
    dw `00033000
    dw `00000000
; 117 TILE_TAVERN — a foaming mug, head spilling over
    dw `00000000
    dw `00111000
    dw `00333300
    dw `03222230
    dw `03222233
    dw `03222230
    dw `00333300
    dw `00000000
; 118 TILE_MARKET — a stack of coin with a glint
    dw `00000000
    dw `00011000
    dw `00033000
    dw `00322300
    dw `00033000
    dw `00322300
    dw `00322300
    dw `00033000
; 119 TILE_SHIPYARD — an anchor, ringed and fluked
    dw `00333000
    dw `00303000
    dw `00333000
    dw `00030000
    dw `03333300
    dw `03030300
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
    dw `00333000

SECTION "Ball tile", ROMX, BANK[3]
BallTile:
    dw `00000000
    dw `00033000
    dw `00313300
    dw `00133300
    dw `00333300
    dw `00333300
    dw `00033000
    dw `00000000

SECTION "Splash tile", ROMX, BANK[3]
SplashTile:
    dw `03000030
    dw `00300300
    dw `00033000
    dw `03333330
    dw `03333330
    dw `00033000
    dw `00300300
    dw `03000030

SECTION "Skull tile", ROMX, BANK[3]
SkullTile:
    dw `00000000
    dw `00333300
    dw `03333330
    dw `33033033
    dw `33333330
    dw `00333300
    dw `00330300
    dw `00000000

SECTION "Mixer scratch", WRAM0
wMixP:   ds 2
wMixQ:   ds 2
wMixO:   ds 2
wMixRow: db
wMixI:   db
wMixBuf: ds 16

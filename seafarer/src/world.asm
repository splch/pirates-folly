; Procedural ocean: on-demand value-noise terrain.
; WorldTile(wx, wy) is a pure function of the world seed — the world is
; never stored. Streaming generates the entering row/column into staging
; buffers during the logic phase; VBlank code blits them into the BG map.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"

SECTION "World WRAM", WRAM0
wStagePend::    db          ; bit 0: column pending, bit 1: row pending
wStageRowTiles: ds 21
wStageColTiles: ds 19
wStageRowAttrs: ds 21       ; CGB palette per staged tile
wStageColAttrs: ds 19
wStageCol:      dw          ; world tile column of staged column
wStageRow:      db          ; world tile row of staged row
wLatTop:        ds 5        ; lattice row/column cache
wLatBot:        ds 5
wIX0:           db
wIY0:           db
wIY1:           db
wJ::            db
wJCount::       db
wK:             db
wFX:            db
wFY:            db
wWX::           dw          ; current tile x (generation/detail)
wGRrow::        db          ; current tile y
wH00:           db
wH10:           db
wH01:           db
wH11:           db
wE1:            db
wE2:            db
wShipCX::       db          ; ship cell coords (0..15)
wShipCY::       db
wChX::          db
wChY::          db
wExplored::     ds 32       ; 16x16-cell fog-of-war bitmap

SECTION "World gen", ROM0

; ---------------------------------------------------------------------------
; Core noise
; ---------------------------------------------------------------------------

; Lattice hash. in: d = ix (0..40), e = iy (0..36); out: a = hash byte.
; clobbers: a, b, c, d, e, h, l
LatHash:
    push de                      ; Mul8 clobbers d AND e — save inputs!
    ld a, d
    ld b, 97
    call Mul8
    pop de
    push hl
    ld a, e
    ld b, 61
    call Mul8
    pop de
    add hl, de
    ld a, [wSeed16]
    xor h
    ld h, a
    ld a, [wSeed16+1]
    xor l
    ld l, a
    call Mix16
    ld a, l
    ret

; in: a = magnitude (0..255), c = frac (0..7); out: a = (mag * frac) >> 3
; clobbers: d, e, h, l
MulMag:
    ld d, 0
    ld e, a
    ld hl, 0
    ld a, c
    and a
    jr z, .shift
.mul
    add hl, de
    dec a
    jr nz, .mul
.shift
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ret

; Unsigned lerp: in: b = base, a = other, c = frac (0..7)
; out: a = base + (other - base) * frac / 8  (stays within [base, other])
; Sign/magnitude handling: hash deltas can exceed +-127, so a signed-byte
; multiply is NOT safe here.
; clobbers: b, c, d, e, h, l
LerpU:
    sub b                          ; a = other - base (carry if negative)
    jr c, .neg
    call MulMag
    add b
    ret
.neg
    cpl
    inc a                          ; |delta|
    call MulMag
    ld c, a
    ld a, b
    sub c
    ret

; Bilinear interpolation of wH00/wH10 (top), wH01/wH11 (bottom) by (wFX, wFY).
; out: a = elevation (0..255). clobbers: a, b, c, d, e, h, l
Bilerp4:
    ld hl, wH00
    ld b, [hl]
    ld a, [wFX]
    ld c, a
    ld a, [wH10]
    call LerpU
    ld [wE1], a
    ld hl, wH01
    ld b, [hl]
    ld a, [wFX]
    ld c, a
    ld a, [wH11]
    call LerpU
    ld [wE2], a
    ld hl, wE1
    ld b, [hl]
    ld a, [wFY]
    ld c, a
    ld a, [wE2]
    call LerpU
    ret

; Detail hash for forest/mountain sprinkle (uses wWX low byte, wGRrow).
; out: a = hash & 15
TileDetail:
    ld a, [wWX]
    ld b, 29
    call Mul8
    push hl
    ld a, [wGRrow]
    ld b, 53
    call Mul8
    pop de
    add hl, de
    ld a, [wSeed16]
    xor h
    ld h, a
    ld a, [wSeed16+1]
    xor l
    ld l, a
    call Mix16
    ld a, l
    and $0F
    ret

; Elevation -> terrain tile. in: a = e; uses wWX/wGRrow for detail.
TerrainFull:
    cp E_DEEP_MAX
    jr c, .deep
    cp E_SHALLOW_MAX
    jr c, .shallow
    cp E_SAND_MAX
    jr c, .sand
    cp E_GRASS_MAX
    jr c, .grass
    call TileDetail
    and a
    jr z, .mtn                   ; 1/16
    cp 6
    jr c, .forest                ; 5/16
.grass
    ld a, TILE_GRASS
    ret
.mtn
    ld a, TILE_MOUNTAIN
    ret
.forest
    ld a, TILE_FOREST
    ret
.sand
    ld a, TILE_SAND
    ret
.shallow
    ld a, TILE_SHALLOW
    ret
.deep
    ld a, TILE_DEEP
    ret

; ---------------------------------------------------------------------------
; Single-tile evaluation (collision, chart, spawn)
; ---------------------------------------------------------------------------

; in: bc = wx (0..319), de = wy (0..287); out: a = terrain tile
WorldTile::
    ; store coords for TileDetail
    ld a, c
    ld [wWX], a
    ld a, b
    ld [wWX+1], a
    ld a, e
    ld [wGRrow], a
    ; fx / fy
    ld a, c
    and 7
    ld [wFX], a
    ld a, e
    and 7
    ld [wFY], a
    ; ix = wx>>3 (9-bit shift)
    ld l, c
    ld h, b
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ld [wIX0], a
    ; iy = wy>>3 (16-bit shift; wy can exceed 255)
    ld l, e
    ld h, d
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ld [wIY0], a
    ; four lattice hashes
    ld a, [wIX0]
    ld d, a
    ld a, [wIY0]
    ld e, a
    call LatHash
    ld [wH00], a
    ld a, [wIX0]
    inc a
    ld d, a
    ld a, [wIY0]
    ld e, a
    call LatHash
    ld [wH10], a
    ld a, [wIX0]
    ld d, a
    ld a, [wIY0]
    inc a
    ld e, a
    call LatHash
    ld [wH01], a
    ld a, [wIX0]
    inc a
    ld d, a
    ld a, [wIY0]
    inc a
    ld e, a
    call LatHash
    ld [wH11], a
    call Bilerp4
    jp TerrainFull               ; tail: a = e -> tile

; ---------------------------------------------------------------------------
; Staged generation (logic phase) + blits (VBlank)
; ---------------------------------------------------------------------------

; in: a = terrain tile id; out: a = CGB palette attr. clobbers a only.
TileAttr:
    and a
    ret z                       ; blank -> UI palette 0
    cp TILE_SAND
    jr c, .sea
    jr z, .sand
    ld a, 3                     ; grass/forest/mountain
    ret
.sea
    ld a, 1
    ret
.sand
    ld a, 2
    ret

; in: de = world tile row (0..287). Fills wStageRowTiles with 21 tiles
; for columns wTileX..wTileX+20.
GenRowStage::
    ld a, e
    ld [wStageRow], a            ; low byte: &31 works (256 mod 32 = 0)
    ld [wGRrow], a
    and 7
    ld [wFY], a
    ld l, e
    ld h, d
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ld [wIY0], a                 ; lattice row
    ; lattice point range: ix0 = wTileX>>3, ix1 = (wTileX+20)>>3 + 1
    ld a, [wTileX]
    ld l, a
    ld a, [wTileX+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ld [wIX0], a
    ld a, [wTileX]
    add 20
    ld l, a
    ld a, [wTileX+1]
    adc 0
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    inc a
    ld [wIY1], a                 ; (repurposed: ix1)
    ; hash lattice points: top[j] = H(j, iy), bot[j] = H(j, iy+1)
    ld a, [wIY1]
    ld hl, wIX0
    sub [hl]
    inc a
    ld [wJCount], a
    ld a, [wIX0]
    ld [wJ], a
.hashLoop
    ld a, [wJ]
    ld d, a
    ld a, [wIY0]
    ld e, a
    call LatHash
    ld [wH00], a                 ; top (LatHash clobbers b!)
    ld a, [wJ]
    ld d, a
    ld a, [wIY0]
    inc a
    ld e, a
    call LatHash
    ld b, a                      ; bot
    ld a, [wJ]
    ld hl, wIX0
    sub [hl]
    ld e, a
    ld d, 0
    ld hl, wLatTop
    add hl, de
    ld a, [wH00]
    ld [hl], a
    ld hl, wLatBot
    add hl, de
    ld a, b
    ld [hl], a
    ld a, [wJ]
    inc a
    ld [wJ], a
    ld a, [wJCount]
    dec a
    ld [wJCount], a
    jr nz, .hashLoop
    ; per tile
    xor a
    ld [wK], a
.tileLoop
    ld a, [wTileX]
    ld hl, wK
    add a, [hl]
    ld [wWX], a
    ld a, [wTileX+1]
    adc 0
    ld [wWX+1], a
    ; fx
    ld a, [wWX]
    and 7
    ld [wFX], a
    ; j = (wx>>3) - ix0
    ld a, [wWX]
    ld l, a
    ld a, [wWX+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ld hl, wIX0
    sub [hl]
    ld e, a
    ld d, 0
    ld hl, wLatTop
    add hl, de
    ld a, [hli]
    ld [wH00], a
    ld a, [hl]
    ld [wH10], a
    ld hl, wLatBot
    add hl, de
    ld a, [hli]
    ld [wH01], a
    ld a, [hl]
    ld [wH11], a
    call Bilerp4
    call TerrainFull             ; a = tile
    ld b, a
    call TileAttr
    ld c, a
    ld a, [wK]
    ld e, a
    ld d, 0
    ld hl, wStageRowTiles
    add hl, de
    ld [hl], b
    ld hl, wStageRowAttrs
    add hl, de
    ld [hl], c
    ld a, [wK]
    inc a
    ld [wK], a
    cp 21
    jr nz, .tileLoop
    ret

; in: de = world tile column (0..319). Fills wStageColTiles with 19 tiles
; for rows wTileY..wTileY+18.
GenColStage::
    ld a, e
    ld [wStageCol], a
    ld [wWX], a
    ld a, d
    ld [wStageCol+1], a
    ld a, e
    and 7
    ld [wFX], a                  ; fixed horizontal frac
    ld a, e
    ld l, a
    ld a, d
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ld [wIX0], a                 ; lattice col
    ; iy0 = wTileY>>3, iy1 = (wTileY+18)>>3 + 1
    ld a, [wTileY]
    ld l, a
    ld a, [wTileY+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    ld [wIY0], a
    ld a, [wTileY]
    add 18
    ld l, a
    ld a, [wTileY+1]
    adc 0
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, l
    inc a
    ld [wIY1], a
    ; hash: left[j] = H(ix, j), right[j] = H(ix+1, j)
    ld a, [wIY1]
    ld hl, wIY0
    sub [hl]
    inc a
    ld [wJCount], a
    ld a, [wIY0]
    ld [wJ], a
.hashLoop
    ld a, [wIX0]
    ld d, a
    ld a, [wJ]
    ld e, a
    call LatHash
    ld [wH00], a                 ; left (LatHash clobbers b!)
    ld a, [wIX0]
    inc a
    ld d, a
    ld a, [wJ]
    ld e, a
    call LatHash
    ld b, a                      ; right
    ld a, [wJ]
    ld hl, wIY0
    sub [hl]
    ld e, a
    ld d, 0
    ld hl, wLatTop
    add hl, de
    ld a, [wH00]
    ld [hl], a
    ld hl, wLatBot
    add hl, de
    ld a, b
    ld [hl], a
    ld a, [wJ]
    inc a
    ld [wJ], a
    ld a, [wJCount]
    dec a
    ld [wJCount], a
    jr nz, .hashLoop
    ; per tile row
    xor a
    ld [wK], a
.tileLoop
    ld a, [wTileY]
    ld hl, wK
    add a, [hl]
    ld [wGRrow], a               ; wy (8-bit; <= 287 by camera clamp)
    and 7
    ld [wFY], a
    ld a, [wGRrow]
    srl a
    srl a
    srl a
    ld hl, wIY0
    sub [hl]
    ld e, a
    ld d, 0
    ld hl, wLatTop
    add hl, de
    ld a, [hli]
    ld [wH00], a                 ; left[j]   = top-left
    ld a, [hl]
    ld [wH01], a                 ; left[j+1] = bottom-left
    ld hl, wLatBot
    add hl, de
    ld a, [hli]
    ld [wH10], a                 ; right[j]   = top-right
    ld a, [hl]
    ld [wH11], a                 ; right[j+1] = bottom-right
    call Bilerp4
    call TerrainFull             ; a = tile
    ld b, a
    call TileAttr
    ld c, a
    ld a, [wK]
    ld e, a
    ld d, 0
    ld hl, wStageColTiles
    add hl, de
    ld [hl], b
    ld hl, wStageColAttrs
    add hl, de
    ld [hl], c
    ld a, [wK]
    inc a
    ld [wK], a
    cp 19
    jr nz, .tileLoop
    ret

; ---------------------------------------------------------------------------
; VBlank blits of staged tiles (fast: <= 21 VRAM writes)
; ---------------------------------------------------------------------------

; in: a = tilemap row (0..31); out: hl = $9800 + a*32; clobbers a, b, c
MapRowAddr::
    ld l, a
    and 7
    rrca
    rrca
    rrca                           ; (a&7) * 32
    ld c, a
    ld a, l
    srl a
    srl a
    srl a
    ld b, a
    ld hl, $9800
    add hl, bc
    ret

; Blit the staged row (wStageRow, cols wTileX..+20) into the BG map.
BlitRowStage::
    ld a, [wStageRow]
    and 31
    call MapRowAddr
    ld a, [wTileX]
    and 31
    ld c, a
    ld b, 0
    add hl, bc
    push hl
    pop de                       ; de = dst
    ld hl, wStageRowTiles
    ; run1 = min(21, 32 - startCol)
    ld a, [wTileX]
    and 31
    ld c, a
    ld a, 32
    sub c
    cp 21
    jr c, .ok
    ld a, 21
.ok
    ld [wJCount], a
    ld b, a
.r1
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .r1
    ld a, 21
    ld b, a
    ld a, [wJCount]
    ld c, a
    ld a, b
    sub c
    jr z, .attrs
    ld b, a
    ld a, e                        ; wrap to start of tilemap row
    sub 32
    ld e, a
    ld a, d
    sbc 0
    ld d, a
.r2
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .r2
.attrs                          ; CGB: same pass for palette attrs (bank 1)
    ld a, [wIsCGB]
    and a
    ret z
    ld a, 1
    ldh [rVBK], a
    ld a, [wStageRow]
    and 31
    call MapRowAddr
    ld a, [wTileX]
    and 31
    ld c, a
    ld b, 0
    add hl, bc
    push hl
    pop de
    ld hl, wStageRowAttrs
    ld a, [wTileX]
    and 31
    ld c, a
    ld a, 32
    sub c
    cp 21
    jr c, .aok
    ld a, 21
.aok
    ld [wJCount], a
    ld b, a
.ar1
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .ar1
    ld a, 21
    ld b, a
    ld a, [wJCount]
    ld c, a
    ld a, b
    sub c
    jr z, .adone
    ld b, a
    ld a, e
    sub 32
    ld e, a
    ld a, d
    sbc 0
    ld d, a
.ar2
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .ar2
.adone
    xor a
    ldh [rVBK], a
    ret

; Blit the staged column (wStageCol, rows wTileY..+18) into the BG map.
BlitColStage::
    ld a, [wStageCol]
    and 31
    ld c, a
    ld b, 0
    push bc
    ld a, [wTileY]
    and 31
    call MapRowAddr
    pop bc
    add hl, bc
    push hl
    pop de                       ; de = dst
    ld hl, wStageColTiles
    ; run1 = min(19, 32 - startRow)
    ld a, [wTileY]
    and 31
    ld c, a
    ld a, 32
    sub c
    cp 19
    jr c, .ok
    ld a, 19
.ok
    ld [wJCount], a
    ld b, a
.c1
    ld a, [hl]
    ld [de], a
    inc hl
    ld a, e
    add 32
    ld e, a
    ld a, d
    adc 0
    ld d, a
    dec b
    jr nz, .c1
    ld a, 19
    ld b, a
    ld a, [wJCount]
    ld c, a
    ld a, b
    sub c
    jr z, .attrs
    ld b, a
    ld a, e                        ; wrap to top of tilemap
    sub LOW(1024)
    ld e, a
    ld a, d
    sbc HIGH(1024)
    ld d, a
.c2
    ld a, [hl]
    ld [de], a
    inc hl
    ld a, e
    add 32
    ld e, a
    ld a, d
    adc 0
    ld d, a
    dec b
    jr nz, .c2
.attrs                          ; CGB: attribute pass in bank 1
    ld a, [wIsCGB]
    and a
    ret z
    ld a, 1
    ldh [rVBK], a
    ld a, [wStageCol]
    and 31
    ld c, a
    ld b, 0
    push bc
    ld a, [wTileY]
    and 31
    call MapRowAddr
    pop bc
    add hl, bc
    push hl
    pop de
    ld hl, wStageColAttrs
    ld a, [wTileY]
    and 31
    ld c, a
    ld a, 32
    sub c
    cp 19
    jr c, .aok
    ld a, 19
.aok
    ld [wJCount], a
    ld b, a
.ac1
    ld a, [hl]
    ld [de], a
    inc hl
    ld a, e
    add 32
    ld e, a
    ld a, d
    adc 0
    ld d, a
    dec b
    jr nz, .ac1
    ld a, 19
    ld b, a
    ld a, [wJCount]
    ld c, a
    ld a, b
    sub c
    jr z, .adone
    ld b, a
    ld a, e
    sub LOW(1024)
    ld e, a
    ld a, d
    sbc HIGH(1024)
    ld d, a
.ac2
    ld a, [hl]
    ld [de], a
    inc hl
    ld a, e
    add 32
    ld e, a
    ld a, d
    adc 0
    ld d, a
    dec b
    jr nz, .ac2
.adone
    xor a
    ldh [rVBK], a
    ret

; ---------------------------------------------------------------------------
; Spawn: find deep water near the map middle
; ---------------------------------------------------------------------------

; Sets wPosX/wPosY to the first deep-water tile along row 144 (step 4)
; that also has water 4 tiles east (so the ship isn't boxed in).
FindSpawn::
    ld bc, 8                       ; wx
.loop
    ld de, 144
    push bc
    call WorldTile
    pop bc
    cp TILE_SHALLOW
    jr nc, .next                   ; not deep water -> keep looking
    ; check 4 tiles east
    push bc
    ld a, c
    add 4
    ld c, a
    ld a, b
    adc 0
    ld b, a
    ld de, 144
    call WorldTile
    pop bc
    cp TILE_SAND
    jr c, .found                   ; water ahead: good spawn
.next
    ld a, c
    add 4
    ld c, a
    ld a, b
    adc 0
    ld b, a
    cp HIGH(WORLD_W - 8)
    jr c, .loop
    ld bc, 16                      ; fallback: west edge
.found
    ; pos = (wx*8, wy*8) px in 12.4 fixed point = (wx<<7, wy<<7)
    ld l, c
    ld h, b
    REPT 7
    add hl, hl
    ENDR
    ld a, l
    ld [wPosX], a
    ld a, h
    ld [wPosX+1], a
    ld a, LOW(144 << 7)
    ld [wPosY], a
    ld a, HIGH(144 << 7)
    ld [wPosY+1], a
    ret

; ---------------------------------------------------------------------------
; Fog of war + chart
; ---------------------------------------------------------------------------

; hl /= 20 -> a (hl destroyed)
DivHL20:
    ld bc, 0
.loop
    ld a, l
    sub 20
    ld l, a
    ld a, h
    sbc 0
    ld h, a
    jr c, .done
    inc c
    jr .loop
.done
    ld a, c
    ret

; hl /= 18 -> a (hl destroyed)
DivHL18:
    ld bc, 0
.loop
    ld a, l
    sub 18
    ld l, a
    ld a, h
    sbc 0
    ld h, a
    jr c, .done
    inc c
    jr .loop
.done
    ld a, c
    ret

; Mark the ship's current cell explored. Called once per frame.
MarkExplored::
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    call DivHL20
    ld [wShipCX], a
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    call DivHL18
    ld [wShipCY], a
    ; set bit (cy*16+cx) in wExplored
    swap a                         ; cy*16 (cy <= 15)
    ld hl, wShipCX
    add a, [hl]
    ld c, a
    and 7
    ld b, a
    ld a, c
    srl a
    srl a
    srl a
    ld e, a
    ld d, 0
    ld hl, wExplored
    add hl, de
    ld a, 1
    inc b
    jr .start
.mk
    add a, a
.start
    dec b
    jr nz, .mk
    ; a = mask, hl = byte ptr; return a=1 iff newly explored
    ld b, a
    ld a, [hl]
    and b
    jr nz, .old
    ld a, [hl]
    or b
    ld [hl], a
    ld a, 1
    ret
.old
    xor a
    ret

; in: wChX, wChY; out: a nonzero iff cell explored. clobbers a,b,c,d,e,hl
TestExplored:
    ld a, [wChY]
    swap a                         ; *16
    ld hl, wChX
    add a, [hl]
    ld c, a
    and 7
    ld b, a
    ld a, c
    srl a
    srl a
    srl a
    ld e, a
    ld d, 0
    ld hl, wExplored
    add hl, de
    ld a, 1
    inc b
    jr .start
.mk
    add a, a
.start
    dec b
    jr nz, .mk
    and [hl]
    ret

; Draw the chart into the BG map (LCD off). Explored cells show a sample
; of their center tile; unexplored cells are blank.
RenderChart:
    xor a
    ld [wChY], a
.rowLoop
    ; hl = $9800 + (cy+1)*32 + 2
    ld a, [wChY]
    inc a
    call MapRowAddr
    inc hl
    inc hl
    xor a
    ld [wChX], a
.colLoop
    push hl
    call TestExplored
    and a
    jr z, .blank
    ; sample cell center tile
    ld a, [wChX]
    ld b, 20
    call Mul8                      ; hl = cx*20
    ld a, l
    add 10
    ld c, a
    ld b, h                        ; bc = wx = cx*20+10
    ld a, [wChY]
    push bc
    ld b, 18
    call Mul8                      ; hl = cy*18
    pop bc
    ld a, l
    add 9
    ld e, a
    ld d, 0                        ; de = wy = cy*18+9
    call WorldTile
    cp TILE_SAND
    jr c, .sea
    ld a, TILE_GRASS
    jr .put
.sea
    ld a, TILE_DEEP
    jr .put
.blank
    ld a, TILE_BLANK
.put
    pop hl
    ld [hli], a
    ; CGB: matching palette attr (chart shows sea/land colors)
    ld c, a
    ld a, [wIsCGB]
    and a
    jr z, .noAttr
    push hl
    ld a, c
    call TileAttr
    ld c, a
    ld a, 1
    ldh [rVBK], a
    dec hl
    ld [hl], c
    inc hl
    xor a
    ldh [rVBK], a
    pop hl
.noAttr
    ld a, [wChX]
    inc a
    ld [wChX], a
    cp 16
    jr nz, .colLoop
    ld a, [wChY]
    inc a
    ld [wChY], a
    cp 16
    jp nz, .rowLoop
    ret

; Place the ship marker sprite on the chart (OAM entry 1, LCD off).
ChartMarker:
    ld a, [wShipCY]
    inc a
    REPT 3
    add a, a
    ENDR
    add 18                         ; (cy+1)*8 + 16 + 2
    ld [$FE04], a
    ld a, [wShipCX]
    add 2
    REPT 3
    add a, a
    ENDR
    add 10                         ; (cx+2)*8 + 8 + 2
    ld [$FE05], a
    ld a, TILE_SHIP_N
    ld [$FE06], a
    xor a
    ld [$FE07], a
    ret

; Clear all 40 OAM entries. LCD must be off.
ClearOAM::
    ld hl, $FE00
    ld b, 160
    xor a
.loop
    ld [hli], a
    dec b
    jr nz, .loop
    ret

; Open the chart (from sailing).
EnterChart::
    call WaitVBlankPoll
    xor a
    ldh [rLCDC], a
    ldh [rSCX], a                  ; chart is unscrolled
    ldh [rSCY], a
    ld a, $E4
    ldh [rBGP], a
    call ClearOAM                  ; hide everything (incl. sea sprite)
    call DrawSeedScreen
    call RenderChart
    call ChartMarker
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01 | LCDC_OBJ_ON
    ldh [rLCDC], a
    ld a, STATE_CHART
    ld [wState], a
    ret

; Chart input: A/B/START returns to sailing.
UpdateChart::
    ld a, [wJoyNew]
    and PADF_A | PADF_B | PADF_START
    ret z
    call SailRedraw
    ld a, STATE_SAIL
    ld [wState], a
    ret

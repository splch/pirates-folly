; Shore mode: exploring land on foot at 2x zoom (STATE_SHORE).
;
; Shore tile (sx, sy) samples the SAME elevation function as the ocean —
; same seed, same lattice, same LatHash, same bilinear weights — but with
; 4-bit interpolation fractions instead of 3-bit, so the shoreline here is
; provably the same landmass the sea chart shows (the ocean map is the 2x
; downsample of this one: shore tile (2*wx, 2*wy) has exactly ocean tile
; (wx, wy)'s elevation). Terrain detail (trees/rocks/flowers) is a hash
; sprinkle on top, pure function of seed + coords like everything else.
;
; BANK DISCIPLINE: this file is ROMX bank 4. It may call ROM0 and its own
; bank directly; bank-3 services go through FarCall3 (main.asm). Callers
; in bank 3 reach TryLand via FarCall4; MainLoop brackets the bank switch.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"
INCLUDE "text.inc"

SECTION "Shore WRAM", WRAM0
wShPosX::    dw             ; player position, integer px
wShPosY::    dw
wShCamX:     dw
wShCamY:     dw
wShTileX:    dw
wShTileY:    dw
wShHeading:  db
wDingX:      dw             ; dinghy world px (reboard point)
wDingY:      dw

SECTION "Shore", ROMX, BANK[4]

; ---------------------------------------------------------------------------
; Core noise: the ocean's elevation function at 2x resolution
; ---------------------------------------------------------------------------

; (mag * frac) >> 4 for mag in 0..255, frac in 0..15, built on ROM0's
; MulMag ((m*(f&7))>>3): f < 8 -> halve; f >= 8 -> (m + (m*(f-8))>>3) >> 1.
; Exact: floor(floor(r/8)/2) == floor(r/16).
; in: a = magnitude, c = frac; out: a. clobbers a, d, e, h, l
MulMag16:
    ld d, a                      ; d = mag
    ld e, c                      ; e = full frac
    res 3, c
    call MulMag                  ; a = (mag*(frac&7))>>3
    bit 3, e
    jr z, .lo
    ld l, a
    ld h, 0
    ld e, d                      ; de = mag
    ld d, 0
    add hl, de                   ; mag + partial (<= 478: needs 16 bits)
    srl h
    rr l
    ld a, l
    ret
.lo
    srl a
    ret

; Unsigned lerp, 4-bit frac: in: b = base, a = other, c = frac (0..15)
; out: a = base + (other - base) * frac / 16 (stays within [base, other])
; clobbers: b, c, d, e, h, l
LerpU16:
    sub b                          ; a = other - base (carry if negative)
    jr c, .neg
    call MulMag16
    add b
    ret
.neg
    cpl
    inc a                          ; |delta|
    call MulMag16
    ld c, a
    ld a, b
    sub c
    ret

; Bilinear interpolation of wH00/wH10 (top), wH01/wH11 (bottom) by
; (wFX, wFY), 4-bit fractions. out: a = elevation (0..255).
; clobbers: a, b, c, d, e, h, l
Bilerp16:
    ld hl, wH00
    ld b, [hl]
    ld a, [wFX]
    ld c, a
    ld a, [wH10]
    call LerpU16
    ld [wE1], a
    ld hl, wH01
    ld b, [hl]
    ld a, [wFX]
    ld c, a
    ld a, [wH11]
    call LerpU16
    ld [wE2], a
    ld hl, wE1
    ld b, [hl]
    ld a, [wFY]
    ld c, a
    ld a, [wE2]
    call LerpU16
    ret

; Detail hash for the tree/rock/flower sprinkle (uses wWX, wGRrow/wGRrowH).
; 31*sx + 63*sy, shift-computed (31 = 32-1, 63 = 64-1). out: a = hash & 15
ShoreDetail:
    ld a, [wWX]
    ld l, a
    ld a, [wWX+1]
    ld h, a
    ld d, h
    ld e, l                      ; de = sx
    REPT 5
    add hl, hl
    ENDR                         ; 32*sx
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a                      ; 31*sx
    push hl
    ld a, [wGRrow]
    ld l, a
    ld a, [wGRrowH]
    ld h, a
    ld d, h
    ld e, l                      ; de = sy
    REPT 6
    add hl, hl
    ENDR                         ; 64*sy
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a                      ; 63*sy
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

; Elevation -> shore tile. in: a = e; uses wWX/wGRrow for detail.
; Water/land thresholds match the ocean's exactly: silhouettes agree.
ShoreTerrain:
    cp E_DEEP_MAX
    jr c, .deep
    cp E_SHALLOW_MAX
    jr c, .shallow
    cp E_SAND_MAX
    jr c, .sand
    cp E_GRASS_MAX
    jr c, .grass
    call ShoreDetail               ; high land: forest with rocks and crags
    and a
    jr z, .mtn                   ; 1/16
    cp 3
    jr c, .rock                  ; 2/16
    ld a, TILE_SH_TREE
    ret
.mtn
    ld a, TILE_SH_MTN
    ret
.rock
    ld a, TILE_SH_ROCK
    ret
.grass
    call ShoreDetail
    and a
    jr z, .tree                  ; 1/16 lone tree
    cp 2
    jr c, .flower                ; 1/16 flowers
    cp 4
    jr c, .grass2                ; 2/16 tufts
    ld a, TILE_SH_GRASS
    ret
.tree
    ld a, TILE_SH_TREE
    ret
.flower
    ld a, TILE_SH_FLOWER
    ret
.grass2
    ld a, TILE_SH_GRASS2
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

; in: a = shore tile id; out: a = CGB palette attr. clobbers a only.
ShoreTileAttr:
    cp TILE_SAND
    jr c, .sea
    jr z, .sand
    ld a, 3                        ; grass/tree/rock/flower/mountain
    ret
.sea
    ld a, 1
    ret
.sand
    ld a, 2
    ret

; in: a = shore tile; out: a = 1 iff the player can walk on it
ShoreWalkable:
    cp TILE_SAND
    jr z, .yes
    cp TILE_SH_GRASS
    jr z, .yes
    cp TILE_SH_GRASS2
    jr z, .yes
    cp TILE_SH_FLOWER
    jr z, .yes
    xor a
    ret
.yes
    ld a, 1
    ret

; in: bc = sx (0..639), de = sy (0..575); out: a = shore tile
ShoreTile:
    ld a, c
    ld [wWX], a
    ld a, b
    ld [wWX+1], a
    ld a, e
    ld [wGRrow], a
    ld a, d
    ld [wGRrowH], a
    ld a, c
    and 15
    ld [wFX], a
    ld a, e
    and 15
    ld [wFY], a
    ld l, c
    ld h, b
    SR16 h, l, 4                   ; ix = sx>>4
    ld a, l
    ld [wIX0], a
    ld l, e
    ld h, d
    SR16 h, l, 4                   ; iy = sy>>4
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
    call Bilerp16
    jp ShoreTerrain                ; tail: a = e -> tile

; ---------------------------------------------------------------------------
; Staged generation (logic phase); the ROM0 blits run in VBlank
; ---------------------------------------------------------------------------

; in: de = shore tile row (0..575). Lattice prefill for a row stage.
GenShRowPrefill:
    ld a, e
    ld [wStageRow], a              ; low byte: &31 works (256 mod 32 = 0)
    ld [wGRrow], a
    ld a, d
    ld [wGRrowH], a
    ld [wStageRowH], a
    ld a, [wShTileX]
    ld [wStageBaseX], a
    ld a, [wShTileX+1]
    ld [wStageBaseX+1], a
    ld a, e
    and 15
    ld [wFY], a
    ld l, e
    ld h, d
    SR16 h, l, 4
    ld a, l
    ld [wIY0], a                   ; lattice row
    ; lattice point range: ix0 = wShTileX>>4, ix1 = (wShTileX+20)>>4 + 1
    ld a, [wShTileX]
    ld l, a
    ld a, [wShTileX+1]
    ld h, a
    SR16 h, l, 4
    ld a, l
    ld [wIX0], a
    ld [wStageLatX], a
    ld a, [wShTileX]
    add 20
    ld l, a
    ld a, [wShTileX+1]
    adc 0
    ld h, a
    SR16 h, l, 4
    ld a, l
    inc a
    ld [wIY1], a                   ; (repurposed: ix1)
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
    ld [wH00], a                   ; top (LatHash clobbers b!)
    ld a, [wJ]
    ld d, a
    ld a, [wIY0]
    inc a
    ld e, a
    call LatHash
    ld b, a                        ; bot
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
    ret

; Row tiles wGenK0..wGenK1-1 into the staging buffers (prefill must run
; first — possibly a frame earlier, so every input ShoreTile could have
; clobbered is re-derived from stage state here). Mirrors GenRowTiles.
GenShRowTiles:
    ld a, [wStageRow]
    and 15                         ; the row's vertical frac is constant
    ld [wFY], a
    ld a, [wStageRow]
    ld [wGRrow], a
    ld a, [wStageRowH]
    ld [wGRrowH], a
    ld a, [wGenK0]
    ld [wK], a
    ld c, a
    ld a, [wStageBaseX]
    add c
    ld l, a
    ld a, [wStageBaseX+1]
    adc 0
    ld h, a                        ; hl = baseX + k0
    ld a, l
    and 15
    ld [wFX], a
    SR16 h, l, 4
    ld a, l
    ld hl, wStageLatX
    sub [hl]
    ld [wJ], a                     ; j for k0
.tileLoop
    ld a, [wStageBaseX]
    ld hl, wK
    add a, [hl]
    ld [wWX], a
    ld a, [wStageBaseX+1]
    adc 0
    ld [wWX+1], a
    ld a, [wJ]                     ; j = (sx>>4) - ix0
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
    call Bilerp16
    call ShoreTerrain              ; a = tile
    ld b, a
    call ShoreTileAttr
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
    ld a, [wFX]                    ; next tile: fx/j step
    inc a
    and 15
    ld [wFX], a
    jr nz, .noJIncrX
    ld a, [wJ]
    inc a
    ld [wJ], a
.noJIncrX
    ld a, [wK]
    inc a
    ld [wK], a
    ld hl, wGenK1
    cp [hl]
    jr nz, .tileLoop
    ret

; in: de = shore tile row (0..575). Full row stage (LCD off only).
GenShRowStage:
    call GenShRowPrefill
    xor a
    ld [wGenK0], a
    ld a, 21
    ld [wGenK1], a
    jp GenShRowTiles

; in: de = shore tile column (0..639). Lattice prefill for a column stage.
GenShColPrefill:
    ld a, e
    ld [wStageCol], a
    ld [wWX], a
    ld a, d
    ld [wStageCol+1], a
    ld a, [wShTileY]
    ld [wStageColY], a             ; blit base row (see wStageColY)
    ld [wStageBaseY], a
    ld a, [wShTileY+1]
    ld [wStageBaseY+1], a
    ld a, e
    and 15
    ld [wFX], a                    ; fixed horizontal frac
    ld a, e
    ld l, a
    ld a, d
    ld h, a
    SR16 h, l, 4
    ld a, l
    ld [wIX0], a                   ; lattice col
    ; iy0 = wShTileY>>4, iy1 = (wShTileY+18)>>4 + 1
    ld a, [wShTileY]
    ld l, a
    ld a, [wShTileY+1]
    ld h, a
    SR16 h, l, 4
    ld a, l
    ld [wIY0], a
    ld [wStageLatY], a
    ld a, [wShTileY]
    add 18
    ld l, a
    ld a, [wShTileY+1]
    adc 0
    ld h, a
    SR16 h, l, 4
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
    ld [wH00], a                   ; left (LatHash clobbers b!)
    ld a, [wIX0]
    inc a
    ld d, a
    ld a, [wJ]
    ld e, a
    call LatHash
    ld b, a                        ; right
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
    ret

; Column tiles wGenK0..wGenK1-1 into the staging buffers. Mirrors GenColTiles.
GenShColTiles:
    ld a, [wStageCol]                ; the column's horizontal frac is constant
    and 15
    ld [wFX], a
    ld a, [wStageCol]                ; wWX too: the detail hash reads it
    ld [wWX], a
    ld a, [wStageCol+1]
    ld [wWX+1], a
    ld a, [wGenK0]
    ld [wK], a
    ld c, a
    ld a, [wStageBaseY]
    add c
    ld l, a
    ld a, [wStageBaseY+1]
    adc 0
    ld h, a                          ; hl = baseY + k0
    ld a, l
    and 15
    ld [wFY], a
    SR16 h, l, 4
    ld a, l
    ld hl, wStageLatY
    sub [hl]
    ld [wJ], a                       ; j for k0
.tileLoop
    ld a, [wStageBaseY]
    ld hl, wK
    add a, [hl]
    ld [wGRrow], a                   ; sy low byte (detail hash)
    ld a, [wStageBaseY+1]
    adc 0
    ld [wGRrowH], a
    ld a, [wJ]                       ; j = (sy>>4) - iy0
    ld e, a
    ld d, 0
    ld hl, wLatTop
    add hl, de
    ld a, [hli]
    ld [wH00], a                     ; left[j]   = top-left
    ld a, [hl]
    ld [wH01], a                     ; left[j+1] = bottom-left
    ld hl, wLatBot
    add hl, de
    ld a, [hli]
    ld [wH10], a                     ; right[j]   = top-right
    ld a, [hl]
    ld [wH11], a                     ; right[j+1] = bottom-right
    call Bilerp16
    call ShoreTerrain                ; a = tile
    ld b, a
    call ShoreTileAttr
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
    ld a, [wFY]                      ; next tile: fy/j step
    inc a
    and 15
    ld [wFY], a
    jr nz, .noJIncrY
    ld a, [wJ]
    inc a
    ld [wJ], a
.noJIncrY
    ld a, [wK]
    inc a
    ld [wK], a
    ld hl, wGenK1
    cp [hl]
    jr nz, .tileLoop
    ret

; in: de = shore tile column (0..639). Full column stage (LCD off only).
GenShColStage:
    call GenShColPrefill
    xor a
    ld [wGenK0], a
    ld a, 19
    ld [wGenK1], a
    jp GenShColTiles

; ---------------------------------------------------------------------------
; Landing (from sailing; entered through FarCall4)
; ---------------------------------------------------------------------------

; From sailing: A pressed, and no dock/dig triggered. With a dinghy aboard
; and a walkable landing tile beside the ship, go ashore.
TryLand::
    ld a, [wHasDinghy]
    and a
    ret z
    ; ship tile -> bc/de
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    SR16 h, l, 3
    ld c, l
    ld b, h
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
    ld h, a
    SR16 h, l, 3
    ld e, l
    ld d, h
    ; stash the ship tile (the dinghy anchors there)
    ld a, c
    ld [wBeachX], a
    ld a, b
    ld [wBeachX+1], a
    ld a, e
    ld [wBeachY], a
    ld a, d
    ld [wBeachY+1], a
    ; north
    ld a, d
    or e
    jr z, .chkS                    ; ty=0: no north
    dec de
    call .tryTile
    ret c
    inc de
.chkS
    ; south
    inc de
    call .tryTile
    ret c
    dec de
    ; west
    ld a, b
    or c
    jr z, .chkE
    dec bc
    call .tryTile
    ret c
    inc bc
.chkE
    inc bc
    call .tryTile
    ret

; in: bc = ocean tile x, de = ocean tile y. If it's land with a walkable
; shore sub-tile, land there: carry set. Else carry clear.
.tryTile
    push bc
    push de
    ld hl, WorldTile
    call FarCall3
    pop de
    pop bc
    cp TILE_SAND
    jr nc, .land
    and a                          ; water: no landing here, carry clear
    ret
.land
    ; shore sub-tile base: wSpX = 2*tx, wSpX2 = 2*ty
    ld l, c
    ld h, b
    add hl, hl
    ld a, l
    ld [wSpX], a
    ld a, h
    ld [wSpX+1], a
    ld l, e
    ld h, d
    add hl, hl
    ld a, l
    ld [wSpX2], a
    ld a, h
    ld [wSpX2+1], a
    xor a
    ld [wSpN], a                   ; sub-tile candidate 0..3
.subLoop
    ld a, [wSpN]
    and 1
    ld hl, wSpX
    add a, [hl]                    ; wSpX is even: +1 never carries
    ld c, a
    inc hl
    ld a, [hl]
    adc 0
    ld b, a                        ; bc = sub sx
    ld a, [wSpN]
    and 2
    srl a
    ld hl, wSpX2
    add a, [hl]
    ld e, a
    inc hl
    ld a, [hl]
    adc 0
    ld d, a                        ; de = sub sy
    push bc
    push de
    call ShoreTile
    call ShoreWalkable
    pop de
    pop bc
    and a
    jr nz, .landHere
    ld a, [wSpN]
    inc a
    ld [wSpN], a
    cp 4
    jr nz, .subLoop
    and a                          ; no walkable sub-tile: carry clear
    ret
.landHere
    ; player px = sub-tile * 8 + 4 (tile center)
    SL16 b, c, 3
    ld a, c
    add 4
    ld [wShPosX], a
    ld a, b
    adc 0
    ld [wShPosX+1], a
    SL16 d, e, 3
    ld a, e
    add 4
    ld [wShPosY], a
    ld a, d
    adc 0
    ld [wShPosY+1], a
    call GoAshore
    scf
    ret

; Enter shore mode: player/dinghy positions already set. LCD on entry.
GoAshore:
    ; the dinghy anchors at the ship's tile center (wBeachX/Y = ship tile)
    ld a, [wBeachX]
    ld l, a
    ld a, [wBeachX+1]
    ld h, a
    REPT 4
    add hl, hl
    ENDR                           ; stx * 16
    ld a, l
    add 8
    ld [wDingX], a
    ld a, h
    adc 0
    ld [wDingX+1], a
    ld a, [wBeachY]
    ld l, a
    ld a, [wBeachY+1]
    ld h, a
    REPT 4
    add hl, hl
    ENDR                           ; sty * 16
    ld a, l
    add 8
    ld [wDingY], a
    ld a, h
    adc 0
    ld [wDingY+1], a
    ; park the sea: hazards do not follow the player ashore
    xor a
    ld [wStormT], a
    ld [wStormT+1], a
    ld [wEnemyActive], a
    ld [wBallPActive], a
    ld [wBallEActive], a
    ld [wMerchActive], a
    ld [wSinkT], a
    ld [wSplashT], a
    ld [wSmokeT], a
    ld [wEnemyFlash], a
    ld [wDmgCool], a
    ld [wQuitCfm], a
    ld [wShakeT], a
    ld [wHitFlashT], a
    ; a despawned final-battle guardian must not consume its wave (the
    ; same hand-back UpdateEnemy does for a despawned guardian)
    ld a, [wIsGuardian]
    and a
    jr z, .noHand
    xor a
    ld [wIsGuardian], a
    ld a, [wFinal]
    and a
    jr z, .noHand
    cp FINAL_DONE
    jr z, .noHand
    dec a
    ld [wFinal], a
.noHand
    ld hl, UpdateSailMusic
    call FarCall3                  ; hazards cleared: calm seas again
    call LcdOff
    ld a, 2
    ld [wShHeading], a             ; face south
    call ShoreCamera
    call ShoreRedrawBody
    ld a, SFX_SPLASH
    ld hl, PlaySfx
    call FarCall3                  ; the dinghy grounds on the sand
    ld a, STATE_SHORE
    ld [wState], a
    ret

; ---------------------------------------------------------------------------
; Reboarding
; ---------------------------------------------------------------------------

; A ashore: beside the dinghy -> back to the ship.
TryReboard:
    ld a, [wShPosX]
    ld l, a
    ld a, [wShPosX+1]
    ld h, a
    ld a, [wDingX]
    ld c, a
    ld a, [wDingX+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call AbsHL
    ld a, h
    and a
    ret nz
    ld a, l
    cp 11
    ret nc
    ld a, [wShPosY]
    ld l, a
    ld a, [wShPosY+1]
    ld h, a
    ld a, [wDingY]
    ld c, a
    ld a, [wDingY+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call AbsHL
    ld a, h
    and a
    ret nz
    ld a, l
    cp 11
    ret nc
ReboardShip:
    ld hl, SailRedraw
    call FarCall3
    ld hl, UpdateSailMusic
    call FarCall3
    ld a, STATE_SAIL
    ld [wState], a
    ret

; ---------------------------------------------------------------------------
; Camera / screen rebuild
; ---------------------------------------------------------------------------

; Camera = player - (80,72), clamped so streaming never leaves the world.
ShoreCamera:
    ld a, [wShPosX]
    ld l, a
    ld a, [wShPosX+1]
    ld h, a
    ld a, l
    sub 80
    ld l, a
    ld a, h
    sbc 0
    ld h, a
    bit 7, h
    jr z, .notNegX
    ld hl, 0
    jr .storeX
.notNegX
    ld a, h
    cp HIGH(SH_CAM_MAX_X)
    jr c, .storeX
    jr nz, .clampX
    ld a, l
    cp LOW(SH_CAM_MAX_X)
    jr c, .storeX
.clampX
    ld hl, SH_CAM_MAX_X
.storeX
    ld a, l
    ld [wShCamX], a
    ld a, h
    ld [wShCamX+1], a
    ld a, [wShPosY]
    ld l, a
    ld a, [wShPosY+1]
    ld h, a
    ld a, l
    sub 72
    ld l, a
    ld a, h
    sbc 0
    ld h, a
    bit 7, h
    jr z, .notNegY
    ld hl, 0
    jr .storeY
.notNegY
    ld a, h
    cp HIGH(SH_CAM_MAX_Y)
    jr c, .storeY
    jr nz, .clampY
    ld a, l
    cp LOW(SH_CAM_MAX_Y)
    jr c, .storeY
.clampY
    ld hl, SH_CAM_MAX_Y
.storeY
    ld a, l
    ld [wShCamY], a
    ld a, h
    ld [wShCamY+1], a
    ret

; wShTileX/wShTileY = camera in whole tiles
ComputeShTiles:
    ld a, [wShCamX]
    ld l, a
    ld a, [wShCamX+1]
    ld h, a
    SR16 h, l, 3
    ld a, l
    ld [wShTileX], a
    ld a, h
    ld [wShTileX+1], a
    ld a, [wShCamY]
    ld l, a
    ld a, [wShCamY+1]
    ld h, a
    SR16 h, l, 3
    ld a, l
    ld [wShTileY], a
    ld a, h
    ld [wShTileY+1], a
    ret

; Initial 21x19 fill of the BG map (LCD off; generation is slow, that's OK).
ShoreFillScreen:
    ld a, [wShTileY]
    ld e, a
    ld a, [wShTileY+1]
    ld d, a
    ld c, 19
.row
    push de
    push bc
    call GenShRowStage
    call BlitRowStage
    pop bc
    pop de
    inc de
    dec c
    jr nz, .row
    ret

; LCD off -> fully rebuilt -> LCD on.
ShoreRedrawBody:
    call ComputeShTiles
    call ShoreFillScreen
    ; the full refill makes any queued/in-flight stream work stale
    ld a, $FF
    ld [wCrossCol+1], a
    ld [wCrossRow+1], a
    xor a
    ld [wJobAxis], a
    ldh [hStagePend], a
    ; hide any sailing sprites left in the shadow OAM
    ld hl, wShadowOAM
    ld b, 160
.clr
    ld [hli], a
    dec b
    jr nz, .clr
    call SetupHud
    call ShoreSprites
    ld a, [wShCamX]
    ldh [rSCX], a
    ld a, [wShCamY]
    ldh [rSCY], a
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01 | LCDC_OBJ_ON | LCDC_WIN_ON | LCDC_WIN_9C00
    ldh [rLCDC], a
    ret

; ---------------------------------------------------------------------------
; Streaming (mirrors CheckStream: one half-stage per frame)
; ---------------------------------------------------------------------------
ShoreStream:
    ; --- X axis ---
    ld a, [wShCamX]
    ld l, a
    ld a, [wShCamX+1]
    ld h, a
    SR16 h, l, 3                ; hl = new tileX
    ld a, [wShTileX]
    ld c, a
    ld a, [wShTileX+1]
    ld b, a
    ld a, l
    cp c
    jr nz, .xDiff
    ld a, h
    cp b
    jr z, .xDone
.xDiff
    ld a, l
    ld [wShTileX], a
    ld a, h
    ld [wShTileX+1], a
    ld a, h
    cp b
    jr c, .left
    jr nz, .right
    ld a, l
    cp c
    jr c, .left
.right
    ld a, [wShTileX]
    add 20
    ld e, a
    ld a, [wShTileX+1]
    adc 0
    ld d, a
    jr .colGot
.left
    ld a, [wShTileX]
    ld e, a
    ld a, [wShTileX+1]
    ld d, a
.colGot
    ld a, [wCrossCol+1]
    cp $FF
    jr nz, .xDone                 ; slot busy: drop the newest crossing
    ld a, e
    ld [wCrossCol], a
    ld a, d
    ld [wCrossCol+1], a
.xDone
    ; --- Y axis ---
    ld a, [wShCamY]
    ld l, a
    ld a, [wShCamY+1]
    ld h, a
    SR16 h, l, 3
    ld a, [wShTileY]
    ld c, a
    ld a, [wShTileY+1]
    ld b, a
    ld a, l
    cp c
    jr nz, .yDiff
    ld a, h
    cp b
    jr z, .yDone
.yDiff
    ld a, l
    ld [wShTileY], a
    ld a, h
    ld [wShTileY+1], a
    ld a, h
    cp b
    jr c, .up
    jr nz, .down
    ld a, l
    cp c
    jr c, .up
.down
    ld a, [wShTileY]
    add 18
    ld e, a
    ld a, [wShTileY+1]
    adc 0
    ld d, a
    jr .rowGot
.up
    ld a, [wShTileY]
    ld e, a
    ld a, [wShTileY+1]
    ld d, a
.rowGot
    ld a, [wCrossRow+1]
    cp $FF
    jr nz, .yDone                 ; slot busy: drop the newest
    ld a, e
    ld [wCrossRow], a
    ld a, d
    ld [wCrossRow+1], a
.yDone
    ; --- generation: one half-stage per frame, from the job queue ---
    ld a, [wJobAxis]
    and a
    jr nz, .runJob
    ; idle: start a job from the queue (column first)
    ld a, [wCrossCol+1]
    cp $FF
    jr z, .tryRowJob
    ld a, 1
    ld [wJobAxis], a
    ld a, [wCrossCol]
    ld [wJobCoord], a
    ld a, [wCrossCol+1]
    ld [wJobCoord+1], a
    ld a, $FF
    ld [wCrossCol+1], a
    xor a
    ld [wJobHalf], a
    jr .runJob
.tryRowJob
    ld a, [wCrossRow+1]
    cp $FF
    ret z
    ld a, 2
    ld [wJobAxis], a
    ld a, [wCrossRow]
    ld [wJobCoord], a
    ld a, [wCrossRow+1]
    ld [wJobCoord+1], a
    ld a, $FF
    ld [wCrossRow+1], a
    xor a
    ld [wJobHalf], a
.runJob
    ld a, [wJobAxis]
    cp 1
    jr z, .jobCol
    ; --- row job ---
    ld a, [wJobHalf]
    and a
    jr nz, .rowSecond
    ld a, [wJobCoord]
    ld e, a
    ld a, [wJobCoord+1]
    ld d, a
    call GenShRowPrefill
    xor a
    ld [wGenK0], a
    ld a, 11
    ld [wGenK1], a
    call GenShRowTiles
    ld a, 1
    ld [wJobHalf], a
    ret
.rowSecond
    ld a, 11
    ld [wGenK0], a
    ld a, 21
    ld [wGenK1], a
    call GenShRowTiles
    ldh a, [hStagePend]
    or 2
    ldh [hStagePend], a
    xor a
    ld [wJobAxis], a
    ret
.jobCol
    ld a, [wJobHalf]
    and a
    jr nz, .colSecond
    ld a, [wJobCoord]
    ld e, a
    ld a, [wJobCoord+1]
    ld d, a
    call GenShColPrefill
    xor a
    ld [wGenK0], a
    ld a, 10
    ld [wGenK1], a
    call GenShColTiles
    ld a, 1
    ld [wJobHalf], a
    ret
.colSecond
    ld a, 10
    ld [wGenK0], a
    ld a, 19
    ld [wGenK1], a
    call GenShColTiles
    ldh a, [hStagePend]
    or 1
    ldh [hStagePend], a
    xor a
    ld [wJobAxis], a
    ret

; ---------------------------------------------------------------------------
; Movement (walking: no momentum, 1 px/frame, per-axis wall sliding)
; ---------------------------------------------------------------------------
ShoreMove:
    ; --- X axis ---
    ldh a, [hJoyHeld]
    and PADF_RIGHT
    jr z, .notR
    ld a, 1
    ld [wShHeading], a
    ld a, [wShPosX]
    ld l, a
    ld a, [wShPosX+1]
    ld h, a
    inc hl
    ld a, h
    cp HIGH(SHORE_W * 8)
    jr nc, .notR                   ; east world edge
    call .walkX
    jr z, .notR
    ld a, l
    ld [wShPosX], a
    ld a, h
    ld [wShPosX+1], a
.notR
    ldh a, [hJoyHeld]
    and PADF_LEFT
    jr z, .notL
    ld a, 3
    ld [wShHeading], a
    ld a, [wShPosX]
    ld l, a
    ld a, [wShPosX+1]
    ld h, a
    dec hl
    bit 7, h
    jr nz, .notL                   ; west world edge
    call .walkX
    jr z, .notL
    ld a, l
    ld [wShPosX], a
    ld a, h
    ld [wShPosX+1], a
.notL
    ; --- Y axis ---
    ldh a, [hJoyHeld]
    and PADF_DOWN
    jr z, .notD
    ld a, 2
    ld [wShHeading], a
    ld a, [wShPosY]
    ld l, a
    ld a, [wShPosY+1]
    ld h, a
    inc hl
    ld a, h
    cp HIGH(SHORE_H * 8)
    jr nc, .notD                   ; south world edge
    call .walkY
    jr z, .notD
    ld a, l
    ld [wShPosY], a
    ld a, h
    ld [wShPosY+1], a
.notD
    ldh a, [hJoyHeld]
    and PADF_UP
    jr z, .notU
    xor a
    ld [wShHeading], a
    ld a, [wShPosY]
    ld l, a
    ld a, [wShPosY+1]
    ld h, a
    dec hl
    bit 7, h
    jr nz, .notU                   ; north world edge
    call .walkY
    jr z, .notU
    ld a, l
    ld [wShPosY], a
    ld a, h
    ld [wShPosY+1], a
.notU
    ret

; in: hl = candidate px X; out: a nonzero iff tile (hl, wShPosY) walkable.
; hl preserved. clobbers b, c, d, e
.walkX
    push hl
    SR16 h, l, 3
    ld c, l
    ld b, h                        ; bc = sx
    ld a, [wShPosY]
    ld e, a
    ld a, [wShPosY+1]
    ld d, a
    SR16 d, e, 3                   ; de = sy
    call ShoreTile
    call ShoreWalkable
    pop hl
    and a
    ret

; in: hl = candidate px Y; out: a nonzero iff tile (wShPosX, hl) walkable.
; hl preserved. clobbers b, c, d, e
.walkY
    push hl
    SR16 h, l, 3
    ld e, l
    ld d, h                        ; de = sy
    ld a, [wShPosX]
    ld c, a
    ld a, [wShPosX+1]
    ld b, a
    SR16 b, c, 3                   ; bc = sx
    call ShoreTile
    call ShoreWalkable
    pop hl
    and a
    ret

; ---------------------------------------------------------------------------
; Sprites / HUD
; ---------------------------------------------------------------------------

; Player into shadow OAM entry 0, dinghy into entry 1.
ShoreSprites:
    ld a, [wShPosX]
    ld hl, wShCamX
    sub [hl]                       ; low-byte diff is exact (<256 apart)
    add 4                          ; +8 OAM offset, -4 to center 8px sprite
    ld b, a
    ld a, [wShPosY]
    ld hl, wShCamY
    sub [hl]
    add 12
    ld c, a
    ld a, [wShHeading]
    add TILE_SH_PLAYER
    ld d, a
    ld hl, wShadowOAM
    ld a, c
    ld [hli], a                    ; Y
    ld a, b
    ld [hli], a                    ; X
    ld a, d
    ld [hli], a                    ; tile
    xor a
    ld [hl], a                     ; attr
    ; dinghy (hidden when off-screen)
    ld a, [wDingX]
    ld hl, wShCamX
    sub [hl]
    add 4
    ld b, a
    ld a, [wDingY]
    ld hl, wShCamY
    sub [hl]
    add 12
    ld c, a
    ld a, b
    cp 169
    jr nc, .hideD
    ld a, c
    cp 160
    jr nc, .hideD
    ld hl, wShadowOAM + 4
    ld a, c
    ld [hli], a
    ld a, b
    ld [hli], a
    ld a, TILE_DINGHY
    ld [hli], a
    xor a
    ld [hl], a
    ret
.hideD
    xor a
    ld [wShadowOAM + 4], a
    ret

; HUD: TX (3 hex), TY (3 hex), moving (2), then H/G/F like the helm.
ShoreHud:
    ld a, [wShPosX]
    ld l, a
    ld a, [wShPosX+1]
    ld h, a
    SR16 h, l, 3
    ld de, wHudDigits
    call WriteHexTriple
    ld a, [wShPosY]
    ld l, a
    ld a, [wShPosY+1]
    ld h, a
    SR16 h, l, 3
    call WriteHexTriple
    ldh a, [hJoyHeld]
    and DIR_MASK
    jr z, .still
    ld a, 1
    jr .spd
.still
    xor a
.spd
    call WriteHexPair
    ld de, wHudRow1
    ld a, TILE_A + 7                 ; 'H'
    ld [de], a
    inc de
    ld a, [wHull]
    call PrintDec2
    ld a, TILE_SPACE
    ld [de], a
    inc de
    ld a, TILE_A + 6                 ; 'G'
    ld [de], a
    inc de
    ld a, [wGold+1]
    ld h, a
    ld a, [wGold]
    ld l, a
    call PrintDec4                   ; clamps to 9999
    ld a, TILE_SPACE
    ld [de], a
    inc de
    ld a, TILE_A + 5                 ; 'F'
    ld [de], a
    inc de
    ld a, [wFragCount]
    add TILE_HEX0
    ld [de], a
    inc de
    ld a, TILE_SLASH
    ld [de], a
    inc de
    ld a, TILE_HEX0 + 9
    ld [de], a
    inc de
    ld a, TILE_SPACE
    ld [de], a
    ret

; ---------------------------------------------------------------------------
; Per-frame entry points
; ---------------------------------------------------------------------------

; Time-critical VBlank work (MainLoop calls this first, inside VBlank).
; The ROM0 blit loops poll STAT before each write, so overrunning VBlank
; stretches into the visible frame instead of dropping writes.
ShoreVBlank::
    ld a, $E4                      ; no storms ashore: canonical BGP
    ldh [rBGP], a
    ld a, [wShCamX]
    ldh [rSCX], a
    ld a, [wShCamY]
    ldh [rSCY], a
    call hOamDma                   ; DMA mid-frame garbles sprites: VBlank only
    ldh a, [hStagePend]
    and a
    jr z, .noPend
    bit 0, a
    jr z, .noCol
    call BlitColStage
.noCol
    ldh a, [hStagePend]
    bit 1, a
    jr z, .noRow
    call BlitRowStage
.noRow
    xor a
    ldh [hStagePend], a
.noPend
    call AnimWater
    call HudVBlank
    ret

; Game logic (after the VBlank work; no VRAM access here).
UpdateShore::
    ldh a, [hJoyNew]
    and PADF_A
    jr z, .noA
    call TryReboard
    ld a, [wState]
    cp STATE_SHORE
    ret nz                         ; reboarded
.noA
    call ShoreMove
    call ShoreCamera
    call ShoreStream
    call ShoreSprites
    call ShoreHud
    ret

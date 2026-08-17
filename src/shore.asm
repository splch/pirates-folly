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

; Shore sites (S1): hash-placed chests, salvage, and lore landmarks.
; Active list entry, 8 bytes: sprite tile, x px (dw), y px (dw),
; dug-bit index (dw; $FFFF for landmarks), loot byte.
wSiteList:   ds 48          ; 6 entries x 8
wSiteCount:  db
wSiteCX0:    db             ; camera cell of the last refresh ($FF = stale)
wSiteCY0:    db
wSiteSlot:   db             ; eval slot / refresh loop index
wSiteX:      dw             ; SiteEval output: px center
wSiteY:      dw
wSiteBit:    dw             ; SiteEval output: dug-bit index
wSiteLoot:   db             ; SiteEval output: loot byte
wSiteType:   db
wSiteQty:    db             ; loot scratch (amount / qty) / refresh cell dy
wSiteGood:   db             ; loot scratch (good index) / refresh cell dx
wSiteCur:    dw             ; list cursor of the site being looted
wSiteTry:    db             ; SitePlace: try index (must NOT alias the
wSiteDX:     db             ;   refresh loop counters — SitePlace runs
wSiteDY:     db             ;   inside them; wSiteDX/DY are its dx/dy temps)

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
ShoreRedrawBody::
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
    dec a                          ; $FF: force a site-list refresh
    ld [wSiteCX0], a
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
; Shore sites (S1): chests, salvage, landmarks
; ---------------------------------------------------------------------------

; hl += sign-extend(a). clobbers a, d, e
ShAddSigned:
    ld e, a
    ld d, 0
    bit 7, a
    jr z, .p
    dec d
.p
    ld a, l
    add e
    ld l, a
    ld a, h
    adc d
    ld h, a
    ret

; Try offsets for site placement: near ring, corners, then a wider ring.
; Dig sites are the win condition, so the search is wider than S1's was.
SITE_TRY: db 0, 0, 2, 0, -2, 0, 0, 2, 0, -2, 2, 2, -2, -2, 2, -2, -2, 2
          db 4, 0, -4, 0, 0, 4, 0, -4
DEF SITE_TRIES EQU 13

; in: hl = a site's first hash (h1); out: a = 1 and wSiteX/wSiteY = px
; center iff a walkable position was found near the hashed spot.
; clobbers all
SitePlace:
    ; h2 = Mix16(h1 ^ SITE_SALT2)
    ld a, h
    xor HIGH(SITE_SALT2)
    ld h, a
    ld a, l
    xor LOW(SITE_SALT2)
    ld l, a
    call Mix16                       ; h2
    ; ox = h2 & 31, oy = (h2>>4) & 31
    ld a, l
    and 31
    ld [wSpX], a
    xor a
    ld [wSpX+1], a
    SR16 h, l, 4
    ld a, l
    and 31
    ld [wSpX2], a
    xor a
    ld [wSpX2+1], a
    ; base = (cx*40 + ox, cy*36 + oy)
    ld a, [wChX]
    ld b, 40
    call Mul8                        ; hl = cx*40
    ld a, [wSpX]
    add l
    ld [wSpX], a
    ld a, h
    adc 0
    ld [wSpX+1], a
    ld a, [wChY]
    ld b, 36
    call Mul8                        ; hl = cy*36
    ld a, [wSpX2]
    add l
    ld [wSpX2], a
    ld a, h
    adc 0
    ld [wSpX2+1], a
    ; walkable-position scan over SITE_TRY offsets
    xor a
    ld [wSiteTry], a                 ; try index
.try
    ld a, [wSiteTry]
    add a
    ld hl, SITE_TRY
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hli]
    ld [wSiteDX], a                  ; dx (signed)
    ld a, [hl]
    ld [wSiteDY], a                  ; dy (signed)
    ; sx = base + dx, into bc FIRST: ShAddSigned clobbers de (its sign-
    ; extension scratch), so the sy half must run second.
    ld a, [wSpX]
    ld l, a
    ld a, [wSpX+1]
    ld h, a
    ld a, [wSiteDX]
    call ShAddSigned
    bit 7, h
    jr nz, .next                     ; wrapped off the west edge
    ld c, l
    ld b, h                          ; bc = sx
    ; sy = base + dy
    ld a, [wSpX2]
    ld l, a
    ld a, [wSpX2+1]
    ld h, a
    ld a, [wSiteDY]
    call ShAddSigned
    bit 7, h
    jr nz, .next                     ; wrapped off the north edge
    ld e, l
    ld d, h                          ; de = sy
    push bc
    push de
    call ShoreTile
    call ShoreWalkable
    pop de
    pop bc
    and a
    jr nz, .found
.next
    ld a, [wSiteTry]
    inc a
    ld [wSiteTry], a
    cp SITE_TRIES
    jp nz, .try
    xor a
    ret
.found
    ; px center = tile * 8 + 4
    SL16 b, c, 3
    ld a, c
    add 4
    ld [wSiteX], a
    ld a, b
    adc 0
    ld [wSiteX+1], a
    SL16 d, e, 3
    ld a, e
    add 4
    ld [wSiteY], a
    ld a, d
    adc 0
    ld [wSiteY+1], a
    ld a, 1
    ret

; in: b = cx (0..15), c = cy (0..15), d = slot (0..1)
; out: a = 0 (no site) or SITE_CHEST/SITE_DEBRIS; wSiteX/wSiteY = px
; center, wSiteBit = dug-bit index, wSiteLoot = loot byte
SiteEval:
    ld a, b
    ld [wChX], a
    ld a, c
    ld [wChY], a
    ld a, d
    ld [wSiteSlot], a                ; the slot
    ; dug-bit index = cell*2 + slot
    ld a, c
    swap a                           ; cy*16
    add b                            ; cell id
    ld l, a
    ld h, 0
    add hl, hl
    ld e, d
    ld d, 0
    add hl, de
    ld a, l
    ld [wSiteBit], a
    ld a, h
    ld [wSiteBit+1], a
    ; h1 = Mix16(cell*251 ^ seed16 ^ slot salt)
    ld a, [wChY]
    swap a
    ld hl, wChX
    add a, [hl]
    ld b, 251
    call Mul8                        ; hl = cell*251
    ld a, [wSeed16]
    xor h
    ld h, a
    ld a, [wSeed16+1]
    xor l
    ld l, a
    ld a, [wSiteSlot]
    and a
    jr nz, .slot1
    ld a, h
    xor HIGH(SITE_SALT0)
    ld h, a
    ld a, l
    xor LOW(SITE_SALT0)
    ld l, a
    jr .mix
.slot1
    ld a, h
    xor HIGH(SITE_SALT1)
    ld h, a
    ld a, l
    xor LOW(SITE_SALT1)
    ld l, a
.mix
    call Mix16                       ; h1
    ld a, l
    and 7
    cp 3
    jr nc, .none                     ; ~5/8 of slots are empty
    ld a, h
    ld [wSiteLoot], a
    and 1
    inc a                            ; SITE_CHEST / SITE_DEBRIS
    ld [wSiteType], a
    call SitePlace
    and a
    jr z, .none
    ld a, [wSiteType]
    ret
.none
    xor a
    ret

; in: b = cx, c = cy; out: a = 0 or SITE_GIBBET/SITE_SKULL; wSiteX/wSiteY.
; Landmarks are rare and never consumed.
LandmarkEval:
    ld a, b
    ld [wChX], a
    ld a, c
    ld [wChY], a
    ld a, c
    swap a
    add b
    ld b, 251
    call Mul8
    ld a, [wSeed16]
    xor h
    ld h, a
    ld a, [wSeed16+1]
    xor l
    ld l, a
    ld a, h
    xor HIGH(LAND_SALT)
    ld h, a
    ld a, l
    xor LOW(LAND_SALT)
    ld l, a
    call Mix16                       ; h1
    ld a, l
    and 31
    jr z, .rare                      ; ~3% of cells
    xor a
    ret                              ; no landmark: return ZERO (a ret nz
                                     ; here appended phantoms with stale
                                     ; site vars for 97% of cells)
.rare
    ld a, h
    and 1
    add SITE_GIBBET
    ld [wSiteType], a
    call SitePlace
    and a
    jr z, .none
    ld a, $FF
    ld [wSiteBit], a                 ; landmarks have no dug bit
    ld [wSiteBit+1], a
    ld a, [wSiteType]
    ret
.none
    xor a
    ret

; out: a = 1 iff wSiteBit is set in wSiteDug. clobbers a, b, h, l
SiteDugTest:
    ld a, [wSiteBit]
    ld l, a
    ld a, [wSiteBit+1]
    ld h, a
    SR16 h, l, 3
    ld bc, wSiteDug
    add hl, bc
    ld a, [wSiteBit]
    and 7
    ld b, 1
    inc a
    jr .s
.m
    sla b
.s
    dec a
    jr nz, .m
    ld a, [hl]
    and b
    ret z
    ld a, 1
    ret

; set wSiteBit in wSiteDug. clobbers a, b, h, l
SiteDugSet:
    ld a, [wSiteBit]
    ld l, a
    ld a, [wSiteBit+1]
    ld h, a
    SR16 h, l, 3
    ld bc, wSiteDug
    add hl, bc
    ld a, [wSiteBit]
    and 7
    ld b, 1
    inc a
    jr .s
.m
    sla b
.s
    dec a
    jr nz, .m
    ld a, [hl]
    or b
    ld [hl], a
    ret

; in: b = cx, c = cy (the isle's cell), d = isle index
; out: a = 1 and wSiteX/wSiteY = px center. h1 = Mix16(cell*251 ^ seed16
; ^ DIG_SALT ^ isle). The win condition needs a diggable spot in every
; isle cell: if the hashed neighborhood is all unwalkable, fall back to a
; full-cell scan, then to the cell center (the lint sweep flags that).
DigSitePlace:
    ld a, b
    ld [wChX], a
    ld a, c
    ld [wChY], a
    ld a, d
    ld [wSiteSlot], a              ; stash the isle index: Mul8 clobbers d
    ld a, c
    swap a
    add b
    ld b, 251
    call Mul8
    ld a, [wSeed16]
    xor h
    ld h, a
    ld a, [wSeed16+1]
    xor l
    ld l, a
    ld a, h
    xor HIGH(DIG_SALT)
    ld h, a
    ld a, l
    xor LOW(DIG_SALT)
    ld l, a
    ld a, [wSiteSlot]
    xor l                          ; mix in the isle index (low byte)
    ld l, a
    call Mix16
    call SitePlace
    and a
    ret nz
    ; fallback: first walkable tile in the cell (row-major scan)
    ld a, [wChX]
    ld b, 40
    call Mul8
    ld a, l
    ld [wSpX], a                   ; x0
    ld a, h
    ld [wSpX+1], a
    ld a, [wChY]
    ld b, 36
    call Mul8
    ld a, l
    ld [wSpX2], a                  ; y0
    ld a, h
    ld [wSpX2+1], a
    xor a
    ld [wSiteTry], a               ; row within the cell
.scanY
    xor a
    ld [wSiteSlot], a              ; column within the cell (dead here)
.scanX
    ld a, [wSpX2]
    ld hl, wSiteTry
    add a, [hl]
    ld e, a
    ld a, [wSpX2+1]
    adc 0
    ld d, a                        ; de = sy
    ld a, [wSpX]
    ld hl, wSiteSlot
    add a, [hl]
    ld c, a
    ld a, [wSpX+1]
    adc 0
    ld b, a                        ; bc = sx
    push bc
    push de
    call ShoreTile
    call ShoreWalkable
    pop de
    pop bc
    and a
    jr nz, .scanFound
    ld a, [wSiteSlot]
    inc a
    ld [wSiteSlot], a
    cp 40
    jr nz, .scanX
    ld a, [wSiteTry]
    inc a
    ld [wSiteTry], a
    cp 36
    jr nz, .scanY
    ; pathological: no walkable tile at all. Cell center; the dig works
    ; from adjacency, and the world lint flags unwalkable placements.
    ld a, [wSpX]
    add 20
    ld c, a
    ld a, [wSpX+1]
    adc 0
    ld b, a
    ld a, [wSpX2]
    add 18
    ld e, a
    ld a, [wSpX2+1]
    adc 0
    ld d, a
    jr .placeAt
.scanFound
.placeAt
    SL16 b, c, 3
    ld a, c
    add 4
    ld [wSiteX], a
    ld a, b
    adc 0
    ld [wSiteX+1], a
    SL16 d, e, 3
    ld a, e
    add 4
    ld [wSiteY], a
    ld a, d
    adc 0
    ld [wSiteY+1], a
    ld a, 1
    ret

; append wSiteType/wSiteX/wSiteY/wSiteBit/wSiteLoot as a list entry (cap 6)
SiteAppend:
    ld a, [wSiteCount]
    cp 6
    ret nc
    add a
    add a
    add a                            ; *8
    ld e, a
    ld d, 0
    ld hl, wSiteList
    add hl, de
    ld a, [wSiteType]
    add TILE_SITE_CHEST - 1          ; sprite tile
    ld [hli], a
    ld a, [wSiteX]
    ld [hli], a
    ld a, [wSiteX+1]
    ld [hli], a
    ld a, [wSiteY]
    ld [hli], a
    ld a, [wSiteY+1]
    ld [hli], a
    ld a, [wSiteBit]
    ld [hli], a
    ld a, [wSiteBit+1]
    ld [hli], a
    ld a, [wSiteLoot]
    ld [hl], a
    ld hl, wSiteCount
    inc [hl]
    ret

; Rebuild the active-site list when the camera's cell changes.
ShoreSites:
    ld a, [wShTileX]
    ld l, a
    ld a, [wShTileX+1]
    ld h, a
    ld b, 40
    call DivHLb
    ld hl, wSiteCX0
    cp [hl]
    jr nz, .refresh
    ld a, [wShTileY]
    ld l, a
    ld a, [wShTileY+1]
    ld h, a
    ld b, 36
    call DivHLb
    ld hl, wSiteCY0
    cp [hl]
    ret z
.refresh
    ld a, [wShTileX]
    ld l, a
    ld a, [wShTileX+1]
    ld h, a
    ld b, 40
    call DivHLb
    ld [wSiteCX0], a
    ld a, [wShTileY]
    ld l, a
    ld a, [wShTileY+1]
    ld h, a
    ld b, 36
    call DivHLb
    ld [wSiteCY0], a
    ld hl, wSiteList
    ld b, 48
    xor a
.clr
    ld [hli], a
    dec b
    jr nz, .clr
    ld [wSiteCount], a
    ld [wSiteQty], a                 ; cell dy
.cellY
    xor a
    ld [wSiteGood], a                ; cell dx
.cellX
    xor a
    ld [wSiteSlot], a                ; slot
.slot
    ld a, [wSiteCX0]
    ld hl, wSiteGood
    add a, [hl]
    ld b, a                          ; cx
    ld a, [wSiteCY0]
    ld hl, wSiteQty
    add a, [hl]
    ld c, a                          ; cy
    ld a, [wSiteSlot]
    ld d, a
    call SiteEval
    and a
    jr z, .nextSlot
    call SiteDugTest
    and a
    jr nz, .nextSlot                 ; dug already
    call SiteAppend
.nextSlot
    ld a, [wSiteSlot]
    inc a
    ld [wSiteSlot], a
    cp 2
    jr nz, .slot
    ; landmark, once per cell
    ld a, [wSiteCX0]
    ld hl, wSiteGood
    add a, [hl]
    ld b, a
    ld a, [wSiteCY0]
    ld hl, wSiteQty
    add a, [hl]
    ld c, a
    call LandmarkEval
    and a
    jr z, .noLandmark
    call SiteAppend
.noLandmark
    ; isle dig site: this cell is an isle cell, its guardian is sunk, and
    ; its fragment is still in the ground
    ld a, [wSiteCX0]
    ld hl, wSiteGood
    add a, [hl]
    ld b, a
    ld a, [wSiteCY0]
    ld hl, wSiteQty
    add a, [hl]
    ld c, a
    push bc
    ld hl, IsIsleCell
    call FarCall3
    pop bc
    cp $FF
    jr z, .cellDone
    ld d, a                        ; isle index
    ld a, b
    ld [wSiteDX], a                ; the FarCalls clobber bc
    ld a, c
    ld [wSiteDY], a
    ld a, d
    ld [wSiteLoot], a              ; stash the isle index
    ld hl, TestGuard
    call FarCall3                  ; a = 1 iff guardian defeated
    and a
    jr z, .cellDone                ; the guardian still watches: no X
    ld a, [wSiteLoot]
    ld hl, TestFrag
    call FarCall3                  ; a = 1 iff fragment collected
    and a
    jr nz, .cellDone               ; already dug up
    ld a, [wSiteDX]
    ld b, a
    ld a, [wSiteDY]
    ld c, a
    ld a, [wSiteLoot]
    ld d, a
    call DigSitePlace
    and a
    jr z, .cellDone
    ld a, SITE_DIG
    ld [wSiteType], a
    ld a, $FF
    ld [wSiteBit], a               ; the fragment mask, not the dug
    ld [wSiteBit+1], a             ;   bitmap, governs the X
    call SiteAppend
.cellDone
    ld a, [wSiteGood]
    inc a
    ld [wSiteGood], a
    cp 2
    jp nz, .cellX                    ; the isle dig check grew past jr range
    ld a, [wSiteQty]
    inc a
    ld [wSiteQty], a
    cp 2
    jp nz, .cellY
    ret

; Write site sprites into shadow OAM entries 2-7 (hidden when off-screen).
ShoreSiteSprites:
    ld hl, wSiteList
    ld de, wShadowOAM + 8
    ld b, 6
.loop
    push bc
    ld a, [hli]
    ld [wSiteType], a
    ld a, [hli]
    ld [wSiteX], a
    ld a, [hli]
    ld [wSiteX+1], a
    ld a, [hli]
    ld [wSiteY], a
    ld a, [hli]
    ld [wSiteY+1], a
    inc hl
    inc hl
    inc hl                           ; skip dug-bit index and loot
    ld a, [wSiteType]
    and a
    jr z, .hide
    ; sx = x - camX (16-bit: sites sit up to a cell off the viewport)
    ld a, [wSiteX]
    ld l, a
    ld a, [wSiteX+1]
    ld h, a
    ld a, [wShCamX]
    ld c, a
    ld a, [wShCamX+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    ld a, h
    and a
    jr nz, .hide
    ld a, l
    add 4
    cp 169
    jr nc, .hide
    ld [wSiteQty], a                 ; screen X
    ; sy = y - camY
    ld a, [wSiteY]
    ld l, a
    ld a, [wSiteY+1]
    ld h, a
    ld a, [wShCamY]
    ld c, a
    ld a, [wShCamY+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    ld a, h
    and a
    jr nz, .hide
    ld a, l
    add 12
    cp 160
    jr nc, .hide
    ld [de], a                       ; Y
    inc de
    ld a, [wSiteQty]
    ld [de], a                       ; X
    inc de
    ld a, [wSiteType]
    ld [de], a                       ; tile
    inc de
    xor a
    ld [de], a                       ; attr
    inc de
    jr .next
.hide
    xor a
    ld [de], a
    inc de
    inc de
    inc de
    inc de
.next
    pop bc
    dec b
    jp nz, .loop
    ret

; ---------------------------------------------------------------------------
; Site interaction (A pressed ashore) and message screens
; ---------------------------------------------------------------------------

; out: a = 1 iff the press was consumed (loot or lore)
TrySite:
    ld hl, wSiteList
    ld b, 6
.loop
    push bc
    ld a, [hl]
    and a
    jp z, .nextEntry                 ; loot code grew past jr range
    ; read the whole entry into scratch
    ld [wSiteType], a
    inc hl
    ld a, [hli]
    ld [wSiteX], a
    ld a, [hli]
    ld [wSiteX+1], a
    ld a, [hli]
    ld [wSiteY], a
    ld a, [hli]
    ld [wSiteY+1], a
    ld a, [hli]
    ld [wSiteBit], a
    ld a, [hli]
    ld [wSiteBit+1], a
    ld a, [hl]                       ; loot (hl stays at entry+7)
    ld [wSiteLoot], a
    push hl
    ; chebyshev range to the player, x then y
    ld a, [wShPosX]
    ld l, a
    ld a, [wShPosX+1]
    ld h, a
    ld a, [wSiteX]
    ld c, a
    ld a, [wSiteX+1]
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
    jp nz, .farPop                   ; loot code grew past jr range
    ld a, l
    cp 11
    jp nc, .farPop
    ld a, [wShPosY]
    ld l, a
    ld a, [wShPosY+1]
    ld h, a
    ld a, [wSiteY]
    ld c, a
    ld a, [wSiteY+1]
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
    jp nz, .farPop
    ld a, l
    cp 11
    jp nc, .farPop
    pop hl                           ; entry cursor (at the loot byte)
    pop bc                           ; the loop counter is dead: the loot
                                     ; paths jp out, so balance the stack
    ld a, [wSiteType]                ; holds the sprite TILE (108 + type)
    cp TILE_DIGX
    jp z, .dig
    cp TILE_SITE_GIBBET
    jp nc, .lore
    ; consumable: remember the entry start for .consume
    ld de, -7
    add hl, de
    ld a, l
    ld [wSiteCur], a
    ld a, h
    ld [wSiteCur+1], a
    ld a, [wSiteType]
    cp TILE_SITE_CHEST
    jp z, .chest
    ; --- debris: good = (loot>>1)&3, qty = 3 + ((loot>>3)&3) ---
    ld a, [wSiteLoot]
    srl a
    and 3
    ld [wSiteGood], a
    ld a, [wSiteLoot]
    REPT 3
    srl a
    ENDR
    and 3
    add 3
    ld [wSiteQty], a
    ; clamp the lot to hold space
    ld a, [wCargo]
    ld hl, wCargo+1
    add a, [hl]
    ld hl, wCargo+2
    add a, [hl]
    ld hl, wCargo+3
    add a, [hl]
    ld b, a
    ld a, CARGO_MAX
    sub b
    jr z, .holdFull
    ld b, a                          ; space
    ld a, [wSiteQty]
    cp b
    jr c, .qtyOk
    ld a, b
.qtyOk
    ld [wSiteQty], a
    ld a, [wSiteGood]
    ld e, a
    ld d, 0
    ld hl, wCargo
    add hl, de
    ld a, [wSiteQty]
    add [hl]
    ld [hl], a
    call .consume
    call ShoreMsgBegin
    ld hl, StrSalvage
    ld de, $9800 + 8*32 + 2
    call PrintStr
    ld a, [wSiteQty]
    add TILE_HEX0
    ld [$9800 + 8*32 + 11], a
    ld a, [wSiteGood]
    ld hl, GoodNamePtr
    call FarCall3                    ; hl = ROM0 name string
    ld de, $9800 + 8*32 + 13
    call PrintStr
    jp ShoreMsgEndActed
.holdFull
    call ShoreMsgBegin
    ld hl, StrHoldFull
    ld de, $9800 + 8*32 + 2
    call PrintStr
    jp ShoreMsgEndActed               ; NOT dug: come back with space
.chest
    ; amount = 15 + (loot & 31)
    ld a, [wSiteLoot]
    and 31
    add 15
    ld [wSiteQty], a
    ld b, a
    ld hl, AddGold
    call FarCall3
    call .consume
    call ShoreMsgBegin
    ld hl, StrDigUpGold
    ld de, $9800 + 8*32 + 1
    call PrintStr
    ld a, [wSiteQty]
    ld de, $9800 + 8*32 + 11
    call PrintDec2
    jp ShoreMsgEndActed
.consume
    call SiteDugSet
    ld a, [wSiteCur]
    ld l, a
    ld a, [wSiteCur+1]
    ld h, a
    xor a
    ld [hl], a                       ; sprite gone
    ld a, SFX_COIN
    ld hl, PlaySfx
    call FarCall3
    ret
; The X on an isle with a sunk guardian: dig up the chart fragment.
.dig
    ; the isle index from the player's cell (the X is in it)
    ld a, [wShPosX]
    ld l, a
    ld a, [wShPosX+1]
    ld h, a
    SR16 h, l, 3
    ld b, 40
    call DivHLb
    ld b, a
    ld a, [wShPosY]
    ld l, a
    ld a, [wShPosY+1]
    ld h, a
    SR16 h, l, 3
    push bc
    ld b, 36
    call DivHLb
    pop bc                           ; restore b (cx) BEFORE writing c:
    ld c, a                          ;   the pop used to clobber cy
    push bc
    ld hl, IsIsleCell
    call FarCall3
    pop bc
    cp $FF
    jp z, .farPop2                   ; not an isle cell: can't happen
    ld [wCurIsle], a
    ; the X vanishes while the ceremony runs
    ld a, [wSiteCur]
    ld l, a
    ld a, [wSiteCur+1]
    ld h, a
    xor a
    ld [hl], a
    ld hl, DigScene
    call FarCall3                    ; sets STATE_DIG; returns ashore after
    ld a, 1
    ret
.lore
    cp TILE_SITE_SKULL
    jr z, .skull
    ld hl, StrGibbet
    jr .show
.skull
    ld hl, StrSkullPole
.show
    push hl
    call ShoreMsgBegin
    pop hl
    ld de, $9800 + 8*32 + 1
    call PrintStr
    jp ShoreMsgEndActed
.farPop
    pop hl                           ; entry cursor (at the loot byte)
    inc hl                           ; -> next entry
    jr .next
.farPop2
    xor a                          ; balanced: the dispatch already popped
    ret
.nextEntry
    ld de, 8
    add hl, de
.next
    pop bc
    dec b
    jp nz, .loop
    xor a
    ret

; Message-screen framing: LCD off, blank map (bank-3 helpers via FarCall3).
ShoreMsgBegin:
    ld hl, ClearTextScreen
    call FarCall3
    ret

; Show the message, wait for any key, rebuild the shore. out: a = 1
ShoreMsgEndActed:
    ld hl, ShowTextScreen
    call FarCall3
ShoreWaitKey:
.wait
    halt
    ldh a, [hVBlankFlag]             ; count VBlanks, not halts (see Wreck)
    and a
    jr z, .wait
    xor a
    ldh [hVBlankFlag], a
    ld hl, UpdateSound
    call FarCall3                    ; MainLoop is parked: tick music here
    call ReadJoypad
    ldh a, [hJoyNew]
    and a
    jr z, .wait
    call LcdOff
    call ShoreRedrawBody
    ld a, 1
    ret

; PUSHS/POPS: a plain SECTION here would dump the rest of the file into
; ROM0 and split shore mode across banks (silent wrong-bank calls!).
PUSHS "Shore strings", ROM0
StrDigUpGold: db "YE DIG UP    GOLD!", 0   ; digits printed at offset 10
StrSalvage:   db "SALVAGE:", 0
StrHoldFull:  db "YER HOLD IS FULL", 0
StrGibbet:    db "A GIBBET SWAYS HERE", 0
StrSkullPole: db "THE DEAD KEEP WATCH", 0
POPS

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
    call TrySite                   ; a site under your boots wins the press
    and a
    ret nz                         ; looted or learned: press consumed
    call TryReboard                ; else: beside the dinghy -> back aboard
    ret
.noA
    call ShoreMove
    call ShoreCamera
    call ShoreStream
    call ShoreSites
    call ShoreSprites
    call ShoreSiteSprites
    call ShoreHud
    ret

; Procedural ocean: on-demand value-noise terrain.
; WorldTile(wx, wy) is a pure function of the world seed — the world is
; never stored. Streaming generates the entering row/column into staging
; buffers during the logic phase; VBlank code blits them into the BG map.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"
INCLUDE "text.inc"

SECTION "Stage HRAM", HRAM
hStagePend::    db          ; bit 0: column pending, bit 1: row pending

SECTION "World WRAM", WRAM0
; Shared with shore mode (shore.asm stages into the same buffers and
; blits through the same ROM0 routines): many of these are exported.
wStageRowTiles:: ds 21
wStageColTiles:: ds 19
wStageRowAttrs:: ds 21      ; CGB palette per staged tile
wStageColAttrs:: ds 19
wStageCol::     dw          ; world tile column of staged column
wStageRow::     db          ; world tile row of staged row
wStageColY::    db          ; wTileY (low byte) when the column was staged:
                            ; the blit runs at least a frame later (two when
                            ; generation is sliced) — the live wTileY may
                            ; have advanced again by then
wCrossCol::     dw          ; CheckStream: queued column crossing (high byte
wCrossRow::     dw          ;   $FF = empty); same for the row crossing
wGenK0::        db          ; GenXTiles: first tile index of this slice
wGenK1::        db          ; GenXTiles: end tile index (exclusive)
wStageBaseX::   dw          ; wTileX at row-stage prefill time: sliced halves
wStageBaseY::   dw          ; wTileY at col-stage prefill time — the camera
                            ; may advance between halves, so tiles must NOT
                            ; read the live camera position
wStageLatX::    db          ; lattice ix0/iy0 at prefill time (wIX0/wIY0 are
wStageLatY::    db          ;   clobbered by WorldTile between halves)
wStageRowH::    db          ; staged row's high byte (wGRrowH is clobbered
                            ;   by WorldTile between halves too)
wSpX::          dw          ; FindSpawn candidate tile x
wSpY:           db          ; FindSpawn candidate row
wSpYC:          db          ; FindSpawn vertical-run cursor
wSpN::          db          ; FindSpawn run counter
wSpX2::         dw          ; FindSpawn eastward-run cursor
wSpRowPtr:      dw          ; FindSpawn row-table cursor
wLatTop::       ds 5        ; lattice row/column cache
wLatBot::       ds 5
wIX0::          db
wIY0::          db
wIY1::          db
wJ::            db
wJCount::       db
wK::            db
wFX::           db
wFY::           db
wWX::           dw          ; current tile x (generation/detail)
wGRrow::        db          ; current tile y (low byte; detail hash)
wGRrowH::       db          ; current tile y, high byte (world rows 256-287)
wH00::          db
wH10::          db
wH01::          db
wH11::          db
wE1::           db
wE2::           db
wShipCX::       db          ; ship cell coords (0..15)
wShipCY::       db
wChX::          db
wChY::          db
wExplored::     ds 32       ; 16x16-cell fog-of-war bitmap
wPortCells::    ds 32       ; cells with a docked-at port (chart markers)
wSiteDug::      ds 64       ; shore-site dug bitmap (bit = cell*2+slot)
                            ; contiguous with wExplored: cleared together
wMarkTX::       dw          ; MarkExplored: ship tile last processed
wMarkTY::       dw          ; ($FFFF = invalid: after boot/spawn jumps)
                            ; NOTE: must stay right after wExplored (cleared together)
wNewCX:         db          ; MarkExplored cell-under-ship candidates
wNewCY:         db

SECTION "World gen", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; Core noise
; ---------------------------------------------------------------------------

PUSHS "Worldgen multiply tables", ROM0
; ix*97 (0..40) and iy*61 (0..36) for LatHash; wx*29 (0..319) and
; wyLow*53 (0..255) for TileDetail. 1.6 KB of ROM to skip Mul8's inner loop.
MUL97_TAB:
FOR i, 40 + 1
    dw i * 97
ENDR
MUL61_TAB:
FOR i, 36 + 1
    dw i * 61
ENDR
MUL29_TAB:
FOR i, WORLD_W
    dw i * 29
ENDR
MUL53_TAB:
FOR i, 256
    dw i * 53
ENDR
POPS

; Lattice hash. in: d = ix (0..40), e = iy (0..36); out: a = hash byte.
; clobbers: a, b, c, d, e, h, l
; ROM0: shore mode (bank 4) hashes the same lattice.
PUSHS "Lattice hash", ROM0
LatHash::
    ld a, d
    ld hl, MUL97_TAB
    call IdxWord                   ; hl = ix*97
    push hl
    ld a, e
    ld hl, MUL61_TAB
    call IdxWord                   ; hl = iy*61
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
POPS

PUSHS "MulMag table", ROM0, ALIGN[8]
; (mag * frac) >> 3 for all 256x8 inputs: page-aligned so the lookup is
; addr = tab + frac*256 + mag. 2 KB of ROM to make Bilerp4 ~3x cheaper —
; diagonal-scroll generation was overrunning the frame (R49).
MULMAG_TAB:
FOR f, 8
    FOR m, 256
        db (m * f) >> 3
    ENDR
ENDR
POPS

; in: a = magnitude (0..255), c = frac (0..7); out: a = (mag * frac) >> 3
; clobbers: a, h, l
; ROM0: shore mode's MulMag16 builds on it (shore.asm).
PUSHS "MulMag", ROM0
MulMag::
    ld l, a
    ld h, HIGH(MULMAG_TAB)
    ld a, c
    add h
    ld h, a
    ld a, [hl]
    ret
POPS

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
    ld hl, MUL29_TAB
    call IdxWord                   ; hl = wx*29 (low byte: wWX low is exact)
    push hl
    ld a, [wGRrow]
    ld hl, MUL53_TAB
    call IdxWord                   ; hl = wyLow*53
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
    SR16 h, l, 3
    ld a, l
    ld [wIX0], a
    ; iy = wy>>3 (16-bit shift; wy can exceed 255)
    ld l, e
    ld h, d
    SR16 h, l, 3
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
    cp TILE_PORT
    jr z, .ui                   ; port marker -> ink
    cp TILE_LET_X
    jr z, .ui                   ; chart X marker -> ink
    cp TILE_SKULL
    jr z, .ui                   ; chart skull marker -> ink
    cp TILE_DOCK
    jr z, .sand                 ; dock -> wood (sand palette)
    cp TILE_SAND
    jr c, .sea
    jr z, .sand
    ld a, 3                     ; grass/forest/mountain
    ret
.ui
    xor a
    ret
.sea
    ld a, 1
    ret
.sand
    ld a, 2
    ret

; in: a = TILE_SAND (a beach tile at wWX/wGRrow); out: a = TILE_DOCK if the
; tile's 4x4 district is a port district, else TILE_SAND. Pure function of
; seed+coords, so streamed and redrawn tiles always agree. clobbers all.
DockTileIfPort::
    ld a, [wWX]
    ld l, a
    ld a, [wWX+1]
    ld h, a
    srl h
    rr l
    srl h
    rr l
    ld b, l                       ; dx = wx / 4
    ld a, [wGRrowH]
    ld h, a
    ld a, [wGRrow]
    ld l, a
    SR16 h, l, 2
    ld c, l                       ; dy = wy / 4 (full 9-bit wy)
    call HasPortHash
    and a
    ld a, TILE_SAND
    ret z
    ld a, TILE_DOCK
    ret

; in: de = world tile row (0..287). Lattice prefill for a row stage:
; sets wStageRow/wGRrow/wFY/wIY0 and hashes wLatTop/wLatBot.
GenRowPrefill::
    ld a, e
    ld [wStageRow], a            ; low byte: &31 works (256 mod 32 = 0)
    ld [wGRrow], a
    ld a, d
    ld [wGRrowH], a
    ld [wStageRowH], a
    ld a, [wTileX]
    ld [wStageBaseX], a
    ld a, [wTileX+1]
    ld [wStageBaseX+1], a
    ld a, e
    and 7
    ld [wFY], a
    ld l, e
    ld h, d
    SR16 h, l, 3
    ld a, l
    ld [wIY0], a                 ; lattice row
    ; lattice point range: ix0 = wTileX>>3, ix1 = (wTileX+20)>>3 + 1
    ld a, [wTileX]
    ld l, a
    ld a, [wTileX+1]
    ld h, a
    SR16 h, l, 3
    ld a, l
    ld [wIX0], a
    ld [wStageLatX], a
    ld a, [wTileX]
    add 20
    ld l, a
    ld a, [wTileX+1]
    adc 0
    ld h, a
    SR16 h, l, 3
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
    ret

; Row tiles wGenK0..wGenK1-1 into the staging buffers (prefill must run
; first — possibly a frame earlier, so every input WorldTile could have
; clobbered is re-derived from stage state here). fx/j are derived
; directly for wGenK0, then step incrementally (fx wraps -> j++).
GenRowTiles::
    ld a, [wStageRow]              ; the row's vertical frac is constant —
    and 7                          ; prefill's wFY is clobbered by WorldTile
    ld [wFY], a                    ; between halves, so re-derive it here
    ld a, [wStageRow]              ; same for wGRrow/wGRrowH (detail + dock
    ld [wGRrow], a                 ; hashes read them per tile)
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
    and 7
    ld [wFX], a
    SR16 h, l, 3
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
    ld a, [wJ]                     ; j = (wx>>3) - ix0
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
    cp TILE_SAND
    call z, DockTileIfPort       ; beach in a port district -> dock
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
    ld a, [wFX]                    ; next tile: fx/j step
    inc a
    and 7
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

; in: de = world tile row (0..287). Full row stage: fills wStageRowTiles
; with 21 tiles for columns wTileX..wTileX+20 (SailFillScreen: LCD off, so
; the frame budget doesn't matter).
GenRowStage::
    call GenRowPrefill
    xor a
    ld [wGenK0], a
    ld a, 21
    ld [wGenK1], a
    jp GenRowTiles

; in: de = world tile column (0..319). Lattice prefill for a column stage:
; sets wStageCol/wWX/wFX/wIX0 and hashes wLatTop/wLatBot.
GenColPrefill::
    ld a, e
    ld [wStageCol], a
    ld [wWX], a
    ld a, d
    ld [wStageCol+1], a
    ld a, [wTileY]
    ld [wStageColY], a         ; blit base row (see wStageColY)
    ld [wStageBaseY], a
    ld a, [wTileY+1]
    ld [wStageBaseY+1], a
    ld a, e
    and 7
    ld [wFX], a                  ; fixed horizontal frac
    ld a, e
    ld l, a
    ld a, d
    ld h, a
    SR16 h, l, 3
    ld a, l
    ld [wIX0], a                 ; lattice col
    ; iy0 = wTileY>>3, iy1 = (wTileY+18)>>3 + 1
    ld a, [wTileY]
    ld l, a
    ld a, [wTileY+1]
    ld h, a
    SR16 h, l, 3
    ld a, l
    ld [wIY0], a
    ld [wStageLatY], a
    ld a, [wTileY]
    add 18
    ld l, a
    ld a, [wTileY+1]
    adc 0
    ld h, a
    SR16 h, l, 3
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
    ret

; Column tiles wGenK0..wGenK1-1 into the staging buffers (prefill first;
; every input WorldTile could have clobbered is re-derived from stage
; state). fy/j are derived directly for wGenK0, then step incrementally.
GenColTiles::
    ld a, [wStageCol]              ; the column's horizontal frac is constant
    and 7                          ; — re-derive it (see GenRowTiles)
    ld [wFX], a
    ld a, [wStageCol]              ; wWX too: the detail/dock hashes read it
    ld [wWX], a                    ; per tile, and WorldTile clobbered it
    ld a, [wStageCol+1]            ; between halves
    ld [wWX+1], a
    ld a, [wGenK0]
    ld [wK], a
    ld c, a
    ld a, [wStageBaseY]
    add c
    ld l, a
    ld a, [wStageBaseY+1]
    adc 0
    ld h, a                        ; hl = baseY + k0
    ld a, l
    and 7
    ld [wFY], a
    SR16 h, l, 3
    ld a, l
    ld hl, wStageLatY
    sub [hl]
    ld [wJ], a                     ; j for k0
.tileLoop
    ld a, [wStageBaseY]
    ld hl, wK
    add a, [hl]
    ld [wGRrow], a               ; wy low byte (detail hash)
    ld a, [wStageBaseY+1]
    adc 0
    ld [wGRrowH], a              ; wy high byte (rows 256-287)
    ld a, [wJ]                   ; j = (wy>>3) - iy0
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
    cp TILE_SAND
    call z, DockTileIfPort       ; beach in a port district -> dock
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
    ld a, [wFY]                  ; next tile: fy/j step
    inc a
    and 7
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

; in: de = world tile column (0..319). Full column stage (LCD off only).
GenColStage::
    call GenColPrefill
    xor a
    ld [wGenK0], a
    ld a, 19
    ld [wGenK1], a
    jp GenColTiles

; ---------------------------------------------------------------------------
; VBlank blits of staged tiles (fast: <= 21 VRAM writes)
; ROM0: shore mode (bank 4) blits through the same routines.
; ---------------------------------------------------------------------------

PUSHS "Staged blits", ROM0

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

; A full staged blit can exceed VBlank on CGB (tile + attr passes, col +
; row, plus DMA/water/HUD), and VRAM writes landing in Mode 3 are silently
; dropped — the clipped blit tail left stale tiles/attrs until the area
; happened to be re-streamed. Poll STAT mode before every write instead:
; bit 1 clear (mode 0/1) means VRAM is accessible, and mode 0 is always
; followed by mode 2 (>= 20 M-cycles of access), so the write right after
; the poll always lands. Falls through instantly in VBlank and with LCD
; off (mode reads 0). Overruns then merely stretch into the visible frame.
; NOTE: STAT is only ever READ here and in BlitColPass — a mid-frame STAT
; WRITE on DMG can raise a spurious STAT IRQ (pandocs: STAT quirks), so
; keep this a read-only poll.
BlitRowPass:
    push hl                      ; src
    ld a, [wStageRow]
    and 31
    call MapRowAddr
    ld a, [wStageBaseX]          ; prefill-time camera column: sliced
    and 31                       ; generation blits frames later, and the
                                 ; live wTileX may have advanced since
    ld c, a
    ld b, 0
    add hl, bc
    push hl
    pop de                       ; de = dst
    pop hl                       ; src
    ; run1 = min(21, 32 - startCol)
    ld a, 32
    sub c
    cp 21
    jr c, .ok
    ld a, 21
.ok
    ld b, a
    ld c, a                      ; keep run1 for the wrap calc
.r1
    ldh a, [rSTAT]
    and STAT_BUSY
    jr nz, .r1
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .r1
    ld a, 21
    sub c
    ret z                        ; no wrap
    ld b, a
    ld a, e                      ; wrap to start of tilemap row
    sub 32
    ld e, a
    ld a, d
    sbc 0
    ld d, a
.r2
    ldh a, [rSTAT]
    and STAT_BUSY
    jr nz, .r2
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .r2
    ret

; Blit the staged row (wStageRow, cols wTileX..+20) into the BG map.
BlitRowStage::
    ld hl, wStageRowTiles
    call BlitRowPass
    ; CGB: same pass for palette attrs (bank 1)
    ld a, [wIsCGB]
    cp $11                      ; DMG-class HW has one VRAM bank: writing
    ret nz                      ; attrs there would overwrite the tilemap
    VBK1
    ld hl, wStageRowAttrs
    call BlitRowPass
    VBK0
    ret

; Copy a staged column from hl into the BG map: col (wStageCol & 31),
; rows (wStageColY & 31)..+18 wrapping to the top. clobbers all.
BlitColPass:
    push hl                      ; src
    ld a, [wStageCol]
    and 31
    ld c, a
    ld b, 0
    push bc                      ; start col
    ld a, [wStageColY]
    and 31
    call MapRowAddr
    pop bc
    add hl, bc
    push hl
    pop de                       ; de = dst
    pop hl                       ; src
    ; run1 = min(19, 32 - startRow)
    ld a, [wStageColY]
    and 31
    ld c, a
    ld a, 32
    sub c
    cp 19
    jr c, .ok
    ld a, 19
.ok
    ld b, a
    ld c, a                      ; keep run1 for the wrap calc
.c1
    ldh a, [rSTAT]
    and STAT_BUSY
    jr nz, .c1
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
    sub c
    ret z                        ; no wrap
    ld b, a
    ld a, e                      ; wrap to top of tilemap
    sub LOW(1024)
    ld e, a
    ld a, d
    sbc HIGH(1024)
    ld d, a
.c2
    ldh a, [rSTAT]
    and STAT_BUSY
    jr nz, .c2
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
    ret

; Blit the staged column (wStageCol, rows wTileY..+18) into the BG map.
BlitColStage::
    ld hl, wStageColTiles
    call BlitColPass
    ; CGB: attribute pass in bank 1
    ld a, [wIsCGB]
    cp $11
    ret nz
    VBK1
    ld hl, wStageColAttrs
    call BlitColPass
    VBK0
    ret
POPS

; ---------------------------------------------------------------------------
; Spawn: find deep water near the map middle
; ---------------------------------------------------------------------------

; Sets wPosX/wPosY to a spawn in OPEN OCEAN. Candidates step east along a
; list of rows; a candidate must be deep water with water 4 tiles east, a
; 24-tile eastward water run, and a 12-tile vertical water run. The plain
; "first deep tile on row 144" scan could pick a tiny enclosed lake (seed
; FFFFFFFF spawned in a 218-tile puddle with no path to the ocean).
PUSHS "Spawn row table", ROMX, BANK[3]
SPAWN_ROWS: db 144, 160, 128, 176, 112, 192, 96, 208, 80, 224, 0
POPS

FindSpawn::
    ld a, LOW(SPAWN_ROWS)
    ld [wSpRowPtr], a
    ld a, HIGH(SPAWN_ROWS)
    ld [wSpRowPtr+1], a
.rowLoop
    ld a, [wSpRowPtr]
    ld l, a
    ld a, [wSpRowPtr+1]
    ld h, a
    ld a, [hli]
    and a
    jp z, .fallback
    ld [wSpY], a
    ld a, l
    ld [wSpRowPtr], a
    ld a, h
    ld [wSpRowPtr+1], a
    xor a
    ld [wSpX+1], a
    ld a, 8
    ld [wSpX], a
.cand
    call .loadX
    call .tileAtRow                ; current tile must be water
    cp TILE_SAND
    jp nc, .next
    ; eastward water run of >= 24 tiles from wx
    ld a, [wSpX]
    ld [wSpX2], a
    ld a, [wSpX+1]
    ld [wSpX2+1], a
    ld a, 24
    ld [wSpN], a
.runE
    ld a, [wSpX2+1]                ; out of world (>= WORLD_W) = land
    cp HIGH(WORLD_W)
    jr c, .runEok
    jp nz, .next
    ld a, [wSpX2]
    cp LOW(WORLD_W)
    jp nc, .next
.runEok
    ld a, [wSpX2]
    ld c, a
    ld a, [wSpX2+1]
    ld b, a
    call .tileAtRow
    cp TILE_SAND
    jp nc, .next                   ; run too short
    ld a, [wSpX2]
    inc a
    ld [wSpX2], a
    jr nz, .runE2
    ld a, [wSpX2+1]
    inc a
    ld [wSpX2+1], a
.runE2
    ld a, [wSpN]
    dec a
    ld [wSpN], a
    jr nz, .runE
    ; vertical water run (north + south through wx) of >= 24 tiles
    ld a, 1
    ld [wSpN], a                   ; total includes the center tile
    ld a, [wSpY]
    ld [wSpYC], a
.runN
    ld a, [wSpYC]
    and a
    jr z, .runNDone                ; top edge stops the run
    dec a
    ld [wSpYC], a
    call .loadX
    call .tileAtYC
    cp TILE_SAND
    jr nc, .runNDone
    ld a, [wSpN]
    inc a
    ld [wSpN], a
    cp 12
    jp z, .found
    jr .runN
.runNDone
    ld a, [wSpY]
    ld [wSpYC], a
.runS
    ld a, [wSpYC]
    cp 250                         ; run cap keeps the 8-bit cursor safe
    jp nc, .next                   ; bottom edge/short run: next candidate
    inc a
    ld [wSpYC], a
    call .loadX
    call .tileAtYC
    cp TILE_SAND
    jr nc, .runSDone
    ld a, [wSpN]
    inc a
    ld [wSpN], a
    cp 12
    jp z, .found
    jr .runS
.runSDone
.next
    ld a, [wSpX]
    add 8
    ld [wSpX], a
    ld a, [wSpX+1]
    adc 0
    ld [wSpX+1], a                 ; loop while wx < WORLD_W - 8 (16-bit)
    cp HIGH(WORLD_W - 8)
    jp c, .cand
    jp nz, .rowLoop
    ld a, [wSpX]
    cp LOW(WORLD_W - 8)
    jp c, .cand
    jp .rowLoop
.fallback
    xor a
    ld [wSpX+1], a
    ld a, 16                       ; west edge, like the original scan
    ld [wSpX], a
    ld a, 144
    ld [wSpY], a
.found
    ; pos = (wx*8, wy*8) px in 12.4 fixed point = (wx<<7, wy<<7)
    ld a, [wSpX]
    ld l, a
    ld a, [wSpX+1]
    ld h, a
    REPT 7
    add hl, hl
    ENDR
    ld a, l
    ld [wPosX], a
    ld a, h
    ld [wPosX+1], a
    ld a, [wSpY]
    ld l, a
    ld h, 0
    REPT 7
    add hl, hl
    ENDR
    ld a, l
    ld [wPosY], a
    ld a, h
    ld [wPosY+1], a
    ; the position jumped discontinuously: force the next MarkExplored
    ; to re-derive the cell even if this tile matches the old one
    ld a, $FF
    ld [wMarkTX], a
    ld [wMarkTX+1], a
    ld [wMarkTY], a
    ld [wMarkTY+1], a
    ret

; bc = wSpX (WorldTile clobbers bc). clobbers a, b, c
.loadX
    ld a, [wSpX]
    ld c, a
    ld a, [wSpX+1]
    ld b, a
    ret

; in: bc = wx, wSpY = row; out: a = tile. clobbers all
.tileAtRow
    ld a, [wSpY]
    ld e, a
    ld d, 0
    jp WorldTile                 ; tail: a = WorldTile(bc, de)

; in: bc = wx, wSpYC = row; out: a = tile. clobbers all
.tileAtYC
    ld a, [wSpYC]
    ld e, a
    ld d, 0
    jp WorldTile

; ---------------------------------------------------------------------------
; Fog of war + chart
; ---------------------------------------------------------------------------

PUSHS "Cell division tables", ROM0
; tx/20 and ty/18 for MarkExplored/MarkPortCell (byte LUTs beat the
; subtract-loop DivHLb for these two constant divisors)
DIV20_TAB:
FOR i, WORLD_W
    db i / 20
ENDR
DIV18_TAB:
FOR i, WORLD_H
    db i / 18
ENDR

; hl /= b -> a (hl destroyed). clobbers a, b, c, hl
; ROM0: shore mode (bank 4) divides camera cells with it.
DivHLb::
    ld c, 0
.loop
    ld a, l
    sub b
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
POPS

PUSHS "Bitmask table", ROMX, BANK[3]
BITMASKS: db 1, 2, 4, 8, 16, 32, 64, 128
POPS

; in: a = cell index (cy*16+cx), hl = bitmap base
; out: hl = &byte, a = bit mask. clobbers b, c, d, e
CellBitPtr:
    ld c, a
    and 7
    ld e, a
    ld d, 0
    push hl
    ld hl, BITMASKS
    add hl, de
    ld a, [hl]
    ld b, a
    ld a, c
    srl a
    srl a
    srl a
    ld e, a
    pop hl
    add hl, de
    ld a, b
    ret

; Mark the ship's current cell explored. Called once per frame.
; Early-out while the ship stays on its tile: the cell bit was set when
; the tile was entered, so only recompute on a tile crossing (the two
; divisions below are the expensive part).
; out: a = 1 newly charted cell, 2 = re-entered charted cell, 0 = no move
MarkExplored::
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    SR16 h, l, 3                ; hl = tx
    ld a, [wShipY]
    ld e, a
    ld a, [wShipY+1]
    ld d, a
    SR16 d, e, 3                ; de = ty
    ld a, [wMarkTX]
    cp l
    jr nz, .moved
    ld a, [wMarkTX+1]
    cp h
    jr nz, .moved
    ld a, [wMarkTY]
    cp e
    jr nz, .moved
    ld a, [wMarkTY+1]
    cp d
    jr nz, .moved
    xor a                          ; same tile: not newly explored
    ret
.moved
    ld a, l
    ld [wMarkTX], a
    ld a, h
    ld [wMarkTX+1], a
    ld a, e
    ld [wMarkTY], a
    ld a, d
    ld [wMarkTY+1], a
    push de                        ; ty
    ld de, DIV20_TAB
    add hl, de
    ld a, [hl]                     ; a = cell x (tx / 20)
    ld [wNewCX], a
    pop hl                         ; hl = ty
    ld de, DIV18_TAB
    add hl, de
    ld a, [hl]                     ; a = cell y (ty / 18)
    ld [wNewCY], a
    ; a tile crossing inside the ship's own cell changes nothing
    ld hl, wShipCY
    cp [hl]
    jr nz, .cellEntry
    ld a, [wNewCX]
    ld hl, wShipCX
    cp [hl]
    jr nz, .cellEntry
    xor a
    ret
.cellEntry
    ld a, [wNewCX]
    ld [wShipCX], a
    ld a, [wNewCY]
    ld [wShipCY], a
    ; set bit (cy*16+cx) in wExplored
    swap a                         ; cy*16 (cy <= 15)
    ld hl, wShipCX
    add a, [hl]
    ld hl, wExplored
    call CellBitPtr
    ; a = mask, hl = byte ptr
    ld b, a
    ld a, [hl]
    and b
    jr nz, .revisit
    ld a, [hl]
    or b
    ld [hl], a
    ld a, 1                        ; newly charted
    ret
.revisit
    ld a, 2                        ; re-entered an already-charted cell
    ret

; Mark the port at beach tile (wBeachX, wBeachY) on the chart bitmap.
MarkPortCell::
    ld a, [wBeachX]
    ld l, a
    ld a, [wBeachX+1]
    ld h, a
    ld de, DIV20_TAB
    add hl, de
    ld a, [hl]
    ld [wChX], a                   ; beach cell X
    ld a, [wBeachY]
    ld l, a
    ld a, [wBeachY+1]
    ld h, a
    ld de, DIV18_TAB
    add hl, de
    ld a, [hl]                     ; a = beach cell Y
    swap a                         ; cy*16 (cy <= 15)
    ld hl, wChX
    add a, [hl]
    ld hl, wPortCells
    call CellBitPtr
    or [hl]
    ld [hl], a
    ret

; in: wChX, wChY; out: a nonzero iff cell has a docked-at port
TestPortCell:
    ld a, [wChY]
    swap a                         ; *16
    ld hl, wChX
    add a, [hl]
    ld hl, wPortCells
    call CellBitPtr
    and [hl]
    ret

; in: wChX, wChY; out: a nonzero iff cell explored. clobbers a,b,c,d,e,hl
TestExplored:
    ld a, [wChY]
    swap a                         ; *16
    ld hl, wChX
    add a, [hl]
    ld hl, wExplored
    call CellBitPtr
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
    call TestPortCell              ; docked-at port? mark it
    and a
    jr z, .isle
    ld a, TILE_PORT
    jr .put
.isle
    ld a, [wChX]
    ld b, a
    ld a, [wChY]
    ld c, a
    call IsIsleCell                ; a = isle index or $FF
    cp $FF
    jr z, .sample
    ld b, a                        ; keep the index (TestFrag clobbers b)
    push bc
    call TestFrag
    pop bc
    and a
    jr z, .notDug
    ld a, TILE_LET_X               ; fragment dug: X marks the spot
    jr .put
.notDug
    ld a, b
    call TestGuard
    and a
    jr nz, .sample                 ; cleared but undug: plain terrain
    ld a, TILE_SKULL               ; guardian still watches these waters
    jr .put
.sample
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
    cp $11
    jr nz, .noAttr
    push hl
    ld a, c
    call TileAttr
    ld c, a
    VBK1
    dec hl
    ld [hl], c
    inc hl
    VBK0
    pop hl
.noAttr
    ld a, [wChX]
    inc a
    ld [wChX], a
    cp 16
    jp nz, .colLoop                ; skull markers grew the loop past jr range
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

; A fully-inked chart earns the cartographer's bounty, once per voyage.
; LCD off. clobbers a, b, h, l (and PlaySfx's)
ChartBounty:
    ld hl, wExplored
    ld b, 32
.full
    ld a, [hli]
    cpl
    and a
    ret nz                         ; still blank parchment somewhere
    dec b
    jr nz, .full
    ld a, [wCartDone]
    and a
    ret nz                         ; already awarded this voyage
    inc a
    ld [wCartDone], a
    ld a, [wGold]
    add LOW(500)
    ld [wGold], a
    ld a, [wGold+1]
    adc HIGH(500)
    ld [wGold+1], a
    ld hl, StrCartDone
    ld de, $9800                   ; row 0: free above the 16x16 chart
    call PrintStr
    ld a, SFX_COIN
    call PlaySfx
    ret

; Print the voyage seed on the chart's free bottom row ("SEED xxxxxxxx").
; Share a seed, share a world — it should be readable without quitting.
; LCD off. clobbers a, b, d, e, h, l
ChartSeed:
    ld hl, $9800 + 17 * 32 + 4
    ld a, TILE_A + 18              ; 'S'
    ld [hli], a
    ld a, TILE_A + 4               ; 'E'
    ld [hli], a
    ld [hli], a                    ; second 'E'
    ld a, TILE_A + 3               ; 'D'
    ld [hli], a
    ld a, TILE_SPACE
    ld [hli], a
    ld de, wSeedNib
    ld b, 8
.dig
    ld a, [de]
    inc de
    add TILE_HEX0
    ld [hli], a
    dec b
    jr nz, .dig
    ret

PUSHS "Chart strings", ROMX, BANK[3]
StrCartDone: db "CHART COMPLETE! 500G", 0
POPS

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
    call LcdOffHome                ; chart is unscrolled
    call ClearOAM                  ; hide everything (incl. sea sprite)
    call DrawSeedScreen
    call RenderChart
    call ChartMarker
    call ChartSeed
    call ChartBounty
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01 | LCDC_OBJ_ON
    ldh [rLCDC], a
    ld a, STATE_CHART
    ld [wState], a
    ret

; Chart input: A/B/START returns to sailing.
UpdateChart::
    ldh a, [hJoyNew]
    and PADF_A | PADF_B | PADF_START
    ret z
    call SailRedraw
    ld a, STATE_SAIL
    ld [wState], a
    ret

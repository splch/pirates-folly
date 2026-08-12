; Island cell generator: hash-seeded random fill with radial falloff,
; cellular automata smoothing, then terrain tile assignment.
; Fully deterministic: wSeed16 -> wMap (20x18 tile IDs).

INCLUDE "hardware.inc"
INCLUDE "defs.inc"

SECTION "Generator WRAM", WRAM0
wLand:    ds 360    ; 20x18, 1 = land
wLandB:   ds 360    ; CA double buffer
wMap:     ds 360    ; 20x18 tile IDs, ready to blit
wGenX:    db
wGenY:    db
wGenSeed: dw        ; wSeed16 ^ salt
wRowBase: dw
wD2:      db
wCAIter:  db
wCNx:     db
wCNy:     db
wCNrow:   db
wCNcol:   db
wCellIdx: dw

SECTION "Generator", ROM0

; Waits for VBlank, kills the LCD, regenerates wMap, blits, LCD on.
GenerateMap::
    call WaitVBlankPoll
    xor a
    ldh [rLCDC], a
    call GenCell
    call CopyMapToVRAM
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    ret

GenCell:
    ld a, [wSeed16]
    xor HIGH(GEN_SALT_LAND)
    ld [wGenSeed], a
    ld a, [wSeed16+1]
    xor LOW(GEN_SALT_LAND)
    ld [wGenSeed+1], a

    ; ---- Phase 1: random fill, probability falls off from center ----
    xor a
    ld [wGenY], a
.p1Row
    ; rowBase = Mix16(genSeed ^ y*97)
    ld a, [wGenY]
    ld b, 97
    call Mul8
    ld a, [wGenSeed]
    xor h
    ld h, a
    ld a, [wGenSeed+1]
    xor l
    ld l, a
    call Mix16
    ld a, h
    ld [wRowBase], a
    ld a, l
    ld [wRowBase+1], a

    xor a
    ld [wGenX], a
.p1Col
    ; hash = Mix16(rowBase ^ x*61)
    ld a, [wGenX]
    ld b, 61
    call Mul8
    ld a, [wRowBase]
    xor h
    ld h, a
    ld a, [wRowBase+1]
    xor l
    ld l, a
    call Mix16
    push hl                      ; save hash (l = random byte)

    ; d2 = |x-10|^2 + |y-9|^2  (max 181, fits a byte)
    ld a, [wGenX]
    sub 10
    jr nc, .xPos
    cpl
    inc a
.xPos
    ld b, a
    call Mul8                    ; hl = dx^2
    ld a, l
    ld [wD2], a
    ld a, [wGenY]
    sub 9
    jr nc, .yPos
    cpl
    inc a
.yPos
    ld b, a
    call Mul8                    ; hl = dy^2
    ld a, [wD2]
    add l                        ; a = d2

    ; chance = GEN_BASE_CHANCE - (d2 - d2/4)
    ld b, a
    srl a
    srl a
    ld c, a
    ld a, b
    sub c
    ld b, a
    ld a, GEN_BASE_CHANCE
    sub b
    ld b, a                      ; b = chance
    pop hl
    ld a, l
    cp b                         ; land iff rand < chance
    ld a, 0
    jr nc, .p1Water
    inc a
.p1Water
    push af                      ; CellPtr clobbers a
    ld de, wLand
    call CellPtr
    pop af
    ld [hl], a

    ld a, [wGenX]
    inc a
    ld [wGenX], a
    cp 20
    jp nz, .p1Col
    ld a, [wGenY]
    inc a
    ld [wGenY], a
    cp 18
    jp nz, .p1Row

    ; ---- Phase 2: cellular automata smoothing (land iff >=5 of 9) ----
    ld a, GEN_CA_ITERS
    ld [wCAIter], a
.caLoop
    xor a
    ld [wGenY], a
.caRow
    xor a
    ld [wGenX], a
.caCol
    call CountNeighbors          ; a = 0..9
    cp 5
    ld a, 0
    jr c, .dead
    inc a
.dead
    push af                      ; CellPtr clobbers a
    ld de, wLandB
    call CellPtr
    pop af
    ld [hl], a
    ld a, [wGenX]
    inc a
    ld [wGenX], a
    cp 20
    jr nz, .caCol
    ld a, [wGenY]
    inc a
    ld [wGenY], a
    cp 18
    jr nz, .caRow
    ; copy wLandB -> wLand
    ld hl, wLandB
    ld de, wLand
    ld bc, 360
.caCopy
    ld a, [hli]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .caCopy
    ld a, [wCAIter]
    dec a
    ld [wCAIter], a
    jr nz, .caLoop

    ; ---- Phase 3: terrain tiles ----
    xor a
    ld [wGenY], a
.tRow
    xor a
    ld [wGenX], a
.tCol
    ld de, wLand
    call CellPtr
    ld a, [hl]
    and a
    jr z, .water
    ; land: coast iff any 4-neighbor is water (edge of map counts)
    call AnyWaterNeighbor
    and a
    jr nz, .sand
    call DetailHash              ; a = hash & 15
    and a
    jr z, .mountain              ; 1/16
    cp 5
    jr c, .forest                ; 4/16
    ld a, TILE_GRASS
    jr .store
.mountain
    ld a, TILE_MOUNTAIN
    jr .store
.forest
    ld a, TILE_FOREST
    jr .store
.sand
    ld a, TILE_SAND
    jr .store
.water
    call AnyLandNeighbor
    and a
    jr nz, .shallow
    ld a, TILE_DEEP
    jr .store
.shallow
    ld a, TILE_SHALLOW
.store
    push af                      ; CellPtr clobbers a
    ld de, wMap
    call CellPtr
    pop af
    ld [hl], a
    ld a, [wGenX]
    inc a
    ld [wGenX], a
    cp 20
    jp nz, .tCol
    ld a, [wGenY]
    inc a
    ld [wGenY], a
    cp 18
    jp nz, .tRow
    ret

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

; hl = de + wGenY*20 + wGenX. Clobbers a, d, e (de is the input base!).
CellPtr:
    push de
    ld a, [wGenY]
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl                   ; y*4
    push hl
    pop de                       ; de = y*4
    add hl, hl
    add hl, hl                   ; y*16
    add hl, de                   ; y*20
    ld a, [wGenX]
    ld e, a
    ld d, 0
    add hl, de
    pop de
    add hl, de
    ret

; a = number of land cells in the 3x3 around (wGenX, wGenY), itself included.
; Out of bounds = water. Clobbers a, b, c, d, e, h, l.
CountNeighbors:
    ld a, [wGenX]
    ld [wCNx], a
    ld a, [wGenY]
    ld [wCNy], a
    ld c, 0                      ; count
    dec a
    ld [wCNrow], a               ; row = y-1
.rowLoop
    ld a, [wCNrow]
    bit 7, a                     ; negative -> skip
    jr nz, .nextRow
    cp 18
    jr nc, .nextRow
    ; col loop: x-1 .. x+1
    ld a, [wCNx]
    dec a
    ld [wCNcol], a
.colLoop
    ld a, [wCNcol]
    bit 7, a
    jr nz, .nextCol
    cp 20
    jr nc, .nextCol
    ; hl = wLand + row*20 + col
    ld a, [wCNrow]
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl                   ; row*4
    push hl
    pop de
    add hl, hl
    add hl, hl                   ; row*16
    add hl, de                   ; row*20
    ld a, [wCNcol]
    ld e, a
    ld d, 0
    add hl, de
    ld de, wLand
    add hl, de
    ld a, [hl]
    add c
    ld c, a
.nextCol
    ld a, [wCNcol]
    inc a
    ld [wCNcol], a
    ld a, [wCNx]
    add 2                        ; stop when col == x+2
    ld b, a
    ld a, [wCNcol]
    cp b
    jr nz, .colLoop
.nextRow
    ld a, [wCNrow]
    inc a
    ld [wCNrow], a
    ld a, [wCNy]
    add 2                        ; stop when row == y+2
    ld b, a
    ld a, [wCNrow]
    cp b
    jr nz, .rowLoop
    ld a, c
    ret

; wCellIdx = wGenY*20 + wGenX
ComputeCellIdx:
    ld a, [wGenY]
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl
    push hl
    pop de
    add hl, hl
    add hl, hl
    add hl, de                   ; y*20
    ld a, [wGenX]
    ld e, a
    ld d, 0
    add hl, de
    ld a, h
    ld [wCellIdx], a
    ld a, l
    ld [wCellIdx+1], a
    ret

; a = wLand[wCellIdx + de]. Caller must keep the access in bounds.
LoadLandAt:
    ld a, [wCellIdx]
    ld h, a
    ld a, [wCellIdx+1]
    ld l, a
    add hl, de
    ld de, wLand
    add hl, de
    ld a, [hl]
    ret

; a = 1 iff any 4-neighbor of the current cell is water; map edge = water.
AnyWaterNeighbor:
    call ComputeCellIdx
    ld a, [wGenY]                ; up
    and a
    jr z, .yes
    ld de, -20
    call LoadLandAt
    and a
    jr z, .yes
    ld a, [wGenY]                ; down
    cp 17
    jr z, .yes
    ld de, 20
    call LoadLandAt
    and a
    jr z, .yes
    ld a, [wGenX]                ; left
    and a
    jr z, .yes
    ld de, -1
    call LoadLandAt
    and a
    jr z, .yes
    ld a, [wGenX]                ; right
    cp 19
    jr z, .yes
    ld de, 1
    call LoadLandAt
    and a
    jr z, .yes
    xor a
    ret
.yes
    ld a, 1
    ret

; a = 1 iff any 4-neighbor of the current cell is land; map edge = sea.
AnyLandNeighbor:
    call ComputeCellIdx
    ld a, [wGenY]                ; up
    and a
    jr z, .chkDown
    ld de, -20
    call LoadLandAt
    and a
    jr nz, .yes
.chkDown
    ld a, [wGenY]
    cp 17
    jr z, .chkLeft
    ld de, 20
    call LoadLandAt
    and a
    jr nz, .yes
.chkLeft
    ld a, [wGenX]
    and a
    jr z, .chkRight
    ld de, -1
    call LoadLandAt
    and a
    jr nz, .yes
.chkRight
    ld a, [wGenX]
    cp 19
    jr z, .no
    ld de, 1
    call LoadLandAt
    and a
    jr nz, .yes
.no
    xor a
    ret
.yes
    ld a, 1
    ret

; a = Mix16(genSeed ^ x*29 ^ y*53) & 15 — interior detail sprinkle.
DetailHash:
    ld a, [wGenX]
    ld b, 29
    call Mul8
    push hl
    ld a, [wGenY]
    ld b, 53
    call Mul8
    pop de
    add hl, de
    ld a, [wGenSeed]
    xor h
    ld h, a
    ld a, [wGenSeed+1]
    xor l
    ld l, a
    call Mix16
    ld a, l
    and $0F
    ret

; Blit wMap (20x18) to the BG map at $9800. LCD must be off.
CopyMapToVRAM:
    ld hl, wMap
    ld de, $9800
    ld c, 18                     ; rows
.row
    ld b, 20
.col
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .col
    ld a, e                      ; next map row: de += 32-20
    add 12
    ld e, a
    ld a, d
    adc 0
    ld d, a
    dec c
    jr nz, .row
    ret

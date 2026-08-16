; Ports & economy: docking, port menus, market, repair, recruit,
; tavern rumors, and battery-backed save/load (MBC5).

INCLUDE "hardware.inc"
INCLUDE "defs.inc"
INCLUDE "text.inc"

SECTION "Port WRAM", WRAM0
wPortState: db          ; PMAIN/PTRADE/PTAVERN/PREPAIR/PRECRUIT/PSAVED
wPortMenu:  db          ; cursor index
wPortDirty: db          ; 1 = full re-render, 2 = cursor moved
wPortDX:    db          ; current port district
wPortDY:    db
wBeachX::   dw          ; land-neighbor tile coords during TryDock
wBeachY::   dw
wPortHash:  dw          ; district hash (drives name/prices/rumor)
wTradeSel:  db
wPortK:     db
wPriceTmp:  db
wDmgCool::  db
wGold::     dw
wHull::     db
wCrew::     db
wCargo::    ds 4
wLastPortDX:: db
wLastPortDY:: db
wHasSave::  db
wNeedSpawn:: db
wNpR:       db          ; nearest-port scan state
wNpX:       db
wNpY:       db
wCandX::    db          ; candidate district under test
wCandY::    db
wNpFound:   db
; wNpDays/wNpDir are the isles.asm exports (shared): FindNearestPort and
; FindNearestIsle each write them right before their print, and the tavern
; prints the port line before the isle line, so one pair serves both.

SECTION "Ports", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; Docking (called from sailing on A press)
; ---------------------------------------------------------------------------

; If the ship is next to a beach in a port district, enter the port.
TryDock::
    ; beach check: any 4-neighbor of the ship tile is land
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld c, l
    ld b, h                        ; bc = tx
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld e, l
    ld d, h                        ; de = ty
    ; store tile coords for neighbor checks
    ld a, c
    ld [wWX], a
    ld a, b
    ld [wWX+1], a
    ld a, e
    ld [wGRrow], a
    ; north
    ld a, d
    or e
    jr z, .chkS                    ; ty=0: no north
    dec de
    call .isLand
    jr c, .beach
    inc de
.chkS
    ; south
    inc de
    call .isLand
    jr c, .beach
    dec de
    ; west
    ld a, b
    or c
    jr z, .chkE
    dec bc
    call .isLand
    jr c, .beach
    inc bc
.chkE
    inc bc
    call .isLand
    jr c, .beach
    ret                            ; no beach: no docking
.beach
    ; stash the beach tile coords (the isle checks clobber bc/de)
    ld a, c
    ld [wBeachX], a
    ld a, b
    ld [wBeachX+1], a
    ld a, e
    ld [wBeachY], a
    ld a, d
    ld [wBeachY+1], a
    ; isle dig? (ship's current cell, set by MarkExplored)
    ld a, [wShipCX]
    ld b, a
    ld a, [wShipCY]
    ld c, a
    call IsIsleCell
    cp $FF
    jr z, .notIsle
    ld [wCurIsle], a
    call TestFrag
    and a
    jr nz, .notIsle                ; already dug up
    ld a, [wCurIsle]
    call TestGuard
    and a
    jr z, .notIsle                 ; guardian alive: no digging yet
    call DigScene
    ret
.notIsle
    ; district of the BEACH tile (from WRAM: calls above clobbered bc/de)
    ld a, [wBeachX]
    ld l, a
    ld a, [wBeachX+1]
    ld h, a
    REPT 2
    srl h
    rr l
    ENDR
    ld a, l
    ld [wPortDX], a                  ; dx
    ld a, [wBeachY]
    ld l, a
    ld a, [wBeachY+1]
    ld h, a
    REPT 2
    srl h
    rr l
    ENDR
    ld a, l
    ld [wPortDY], a                  ; dy
    ; port check (reload b/c from WRAM: call-clobber-proof)
    ld a, [wPortDX]
    ld b, a
    ld a, [wPortDY]
    ld c, a
    call HasPortHash
    and a
    ret z                            ; no port in this district
    ld a, [wPortDX]
    ld [wLastPortDX], a
    ld a, [wPortDY]
    ld [wLastPortDY], a
    call MarkPortCell              ; chart the port (beach's cell)
    ; hash for name/prices/rumor
    ld a, [wPortDX]
    ld b, a
    ld a, [wPortDY]
    ld c, a
    call DistrictHash
    ld a, h
    ld [wPortHash], a
    ld a, l
    ld [wPortHash+1], a
    call SaveGame                  ; autosave on dock
    ld a, SFX_BELL
    call PlaySfx                   ; harbor bell
    ld a, SONG_PORT
    call SetSong                   ; Spanish Ladies was composed but never played
    ; enter port screen
    xor a
    ld [wPortState], a             ; PMAIN
    ld [wPortMenu], a
    ld a, 1
    ld [wPortDirty], a
    call LcdOffHome                ; UI screens are unscrolled
    call ClearOAM
    call RenderPort
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    ld a, STATE_PORT
    ld [wState], a
    ret

; helper: is tile (bc, de) land? carry set if so. clobbers all.
.isLand
    push bc
    push de
    call WorldTile
    pop de
    pop bc
    cp TILE_SAND
    ccf                            ; carry set iff land (tile >= SAND)
    ret

; ---------------------------------------------------------------------------
; District hashing
; ---------------------------------------------------------------------------

; in: b = dx (0..79), c = dy (0..71); out: hl = hash16
DistrictHash:
    push bc                      ; Mul8 clobbers b AND c — save dy!
    ld a, b
    ld b, 37
    call Mul8
    pop bc
    push hl
    ld a, c
    ld b, 91
    call Mul8
    pop de
    add hl, de
    ld a, [wSeed16]
    xor h
    ld h, a
    ld a, [wSeed16+1]
    xor l
    ld l, a
    ld a, h
    xor HIGH(PORT_SALT)
    ld h, a
    ld a, l
    xor LOW(PORT_SALT)
    ld l, a
    call Mix16
    ret

; in: b = dx, c = dy; out: a = 1 iff port district (hash only, ~19%)
HasPortHash::
    call DistrictHash
    ld a, l
    and $3F
    cp 12
    ld a, 0
    ret nc
    inc a
    ret

; in: b = dx, c = dy; out: a = 1 iff any land tile in the district
; Scratch is wBeachX/wBeachY: safe here (TryDock is long done when the
; tavern runs) and, unlike wNpX/wNpY, not FindNearestPort's loop state.
; 16-bit bases: dx*4 reaches 316, dy*4 reaches 284 — bytes would wrap.
PUSHS "DistrictHasLand offsets", ROMX, BANK[3]
DHL_OFF: db 1, 1, 2, 1, 1, 2, 2, 2, 0
POPS

DistrictHasLand:
    ld l, b
    ld h, 0
    add hl, hl
    add hl, hl
    ld a, l
    ld [wBeachX], a
    ld a, h
    ld [wBeachX+1], a              ; dx*4
    ld l, c
    ld h, 0
    add hl, hl
    add hl, hl
    ld a, l
    ld [wBeachY], a
    ld a, h
    ld [wBeachY+1], a              ; dy*4
    ld hl, DHL_OFF
.loop
    ld a, [wBeachX]
    ld c, a
    ld a, [wBeachX+1]
    ld b, a
    ld a, [hli]
    add c
    ld c, a
    jr nc, .xok
    inc b
.xok
    ld a, [wBeachY]
    ld e, a
    ld a, [wBeachY+1]
    ld d, a
    ld a, [hli]
    add e
    ld e, a
    jr nc, .yok
    inc d
.yok
    push hl
    call WorldTile
    pop hl
    cp TILE_SAND
    jr nc, .land
    ld a, [hl]
    and a
    jr nz, .loop
    xor a                          ; all four samples water
    ret
.land
    ld a, 1
    ret

; Nearest port district to (wPortDX, wPortDY) within radius 12, land-validated.
; out: wNpFound (0/1), wNpX/wNpY = district, wNpDays, wNpDir (0..7 = N,NE,E,SE,S,SW,W,NW)
FindNearestPort:
    ld a, 1
    ld [wNpR], a
.radiusLoop
    ; iterate dx in -r..r, dy in -r..r, ring max(|dx|,|dy|)==r
    ld a, [wNpR]
    cpl
    inc a
    ld [wNpX], a                   ; dx = -r
.xLoop
    ld a, [wNpR]
    cpl
    inc a
    ld [wNpY], a                   ; dy = -r
.yLoop
    ; skip if max(|dx|,|dy|) != r
    ld a, [wNpX]
    call AbsA
    ld b, a
    ld a, [wNpY]
    call AbsA
    cp b
    jr nc, .m1
    ld a, b
.m1                              ; a = max(|dx|,|dy|)
    ld hl, wNpR
    cp [hl]
    jr nz, .nextY
    ; candidate district -> WRAM (bc does not survive hash calls)
    ld a, [wPortDX]
    ld hl, wNpX
    add a, [hl]
    ld [wCandX], a
    ld a, [wPortDY]
    ld hl, wNpY
    add a, [hl]
    ld [wCandY], a
    ; bounds: 0..79, 0..71
    ld a, [wCandX]
    cp 80
    jr nc, .nextY
    ld a, [wCandY]
    cp 72
    jr nc, .nextY
    ld a, [wCandX]
    ld b, a
    ld a, [wCandY]
    ld c, a
    call HasPortHash
    and a
    jr z, .nextY
    ld a, [wCandX]
    ld b, a
    ld a, [wCandY]
    ld c, a
    call DistrictHasLand
    and a
    jr z, .nextY
    ; found!
    ld a, 1
    ld [wNpFound], a
    ld a, [wCandX]
    ld [wNpX], a
    ld a, [wCandY]
    ld [wNpY], a
    ld a, [wNpR]
    ld [wNpDays], a
    call ComputeDirection
    ret
.nextY
    ; dy/dx march from -r upward one step at a time, so an equality test
    ; on r+1 is the exact loop bound. (A magnitude test against r is NOT:
    ; negative offsets are two's complement bytes like $FF that compare
    ; unsigned-large, which used to end rings r >= 2 after their first cell.)
    ld a, [wNpY]
    inc a
    ld [wNpY], a
    ld b, a
    ld a, [wNpR]
    inc a                          ; r + 1
    cp b
    jr nz, .yLoop                  ; dy <= r: keep scanning this ring
    ; dy == r+1 -> next dx
    ld a, [wNpX]
    inc a
    ld [wNpX], a
    ld b, a
    ld a, [wNpR]
    inc a
    cp b
    jp nz, .xLoop
    ; dx == r+1 -> next radius
    ld a, [wNpR]
    inc a
    ld [wNpR], a
    cp 13
    jp c, .radiusLoop
    xor a
    ld [wNpFound], a
    ret

; wNpX/wNpY (found port) vs wPortDX/wPortDY -> wNpDir (0=N..7=NW)
ComputeDirection:
    ld a, [wNpX]
    ld hl, wPortDX
    sub [hl]                       ; ddx
    ld b, a
    ld a, [wNpY]
    ld hl, wPortDY
    sub [hl]                       ; ddy
    ld c, a
    ; |ddx| vs 2*|ddy| etc
    ld a, b
    call AbsA
    ld e, a                        ; |ddx|
    ld a, c
    call AbsA
    ld d, a                        ; |ddy|
    ; compare |ddx| > 2*|ddy| -> E/W; 2*|ddx| < |ddy| -> N/S; else diagonal
    ld a, d
    add a                          ; 2|ddy|
    cp e
    jr c, .eastWest
    ld a, e
    add a                          ; 2|ddx|
    cp d
    jr c, .northSouth
    ; diagonal: NE/NW/SE/SW
    bit 7, c
    jr nz, .diagN
    ; south diagonals: SE=3, SW=4
    bit 7, b
    jr nz, .sw
    ld a, 3
    jr .setDir
.sw
    ld a, 5                        ; DIRS: 0=N 1=NE 2=E 3=SE 4=S 5=SW 6=W 7=NW
    jr .setDir
.diagN
    ; north diagonals: NE=1, NW=7
    bit 7, b
    jr nz, .nw
    ld a, 1
    jr .setDir
.nw
    ld a, 7
    jr .setDir
.eastWest
    bit 7, b
    jr nz, .west
    ld a, 2                        ; E
    jr .setDir
.west
    ld a, 6                        ; W
    jr .setDir
.northSouth
    bit 7, c
    jr nz, .north
    ld a, 4                        ; S (y down)
    jr .setDir
.north
    xor a                          ; N
.setDir
    ld [wNpDir], a
    ret

; ---------------------------------------------------------------------------
; Port rendering
; ---------------------------------------------------------------------------

; Full re-render of the port screen (LCD off).
RenderPort:
    call DrawSeedScreen            ; clear tilemap
    ; port name, row 1
    ld de, $9800 + 1 * 32 + 3
    call PrintPortName
    ; gold, row 3
    ld hl, StrGold
    ld de, $9800 + 3 * 32 + 2
    call PrintStr
    ld a, [wGold+1]
    ld h, a
    ld a, [wGold]
    ld l, a
    ld de, $9800 + 3 * 32 + 8
    call PrintDec4
    ; hull/crew, row 4
    ld hl, StrHull
    ld de, $9800 + 4 * 32 + 2
    call PrintStr
    ld a, [wHull]
    ld de, $9800 + 4 * 32 + 8
    call PrintDec2
    ld a, TILE_SLASH
    ld [$9800 + 4 * 32 + 10], a
    ld a, HULL_MAX
    ld de, $9800 + 4 * 32 + 11
    call PrintDec2
    ld hl, StrCrew
    ld de, $9800 + 4 * 32 + 13
    call PrintStr
    ld a, [wCrew]
    ld de, $9800 + 4 * 32 + 18
    call PrintDec2
    ; sub-screen body
    ld a, [wPortState]
    and a
    jr z, .main
    cp PTRADE
    jp z, RenderTrade
    cp PTAVERN
    jp z, RenderTavern
    cp PREPAIR
    jp z, RenderRepair
    cp PRECRUIT
    jp z, RenderRecruit
    ; PSAVED
    ld hl, StrSaved
    ld de, $9800 + 7 * 32 + 5
    call PrintStr
    ld hl, StrAnyKey
    ld de, $9800 + 9 * 32 + 3
    call PrintStr
    ret
.main
    ; menu items, rows 6-11
    ld hl, StrTrade
    ld de, $9800 + 6 * 32 + 5
    call PrintStr
    ld hl, StrRepair
    ld de, $9800 + 7 * 32 + 5
    call PrintStr
    ld hl, StrTavern
    ld de, $9800 + 8 * 32 + 5
    call PrintStr
    ld hl, StrRecruit
    ld de, $9800 + 9 * 32 + 5
    call PrintStr
    ld hl, StrSave
    ld de, $9800 + 10 * 32 + 5
    call PrintStr
    ld hl, StrSetSail
    ld de, $9800 + 11 * 32 + 5
    call PrintStr
    call DrawCursor
    ret

; Draw the '>' cursor for the current menu (main: rows 6+, trade: rows 6+).
DrawCursor:
    ld a, [wPortMenu]
    add 6
    call MapRowAddr
    ld bc, 4
    add hl, bc
    ld a, TILE_GT
    ld [hl], a
    ret

; Erase all cursor spots (rows 6-14, col 4).
EraseCursors:
    ld c, 6                        ; row counter (survives via stack)
.loop
    ld a, c
    push bc
    call MapRowAddr
    ld bc, 4
    add hl, bc
    ld a, TILE_SPACE
    ld [hl], a
    pop bc
    inc c
    ld a, c
    cp 15
    jr nz, .loop
    ret

; ---------------------------------------------------------------------------
; Trade
; ---------------------------------------------------------------------------

PUSHS "Trade tables", ROMX, BANK[3]
GOOD_NAMES:  dw StrRum, StrSilk, StrSpice, StrCannon
GOOD_BASE:   db 5, 10, 15, 25
POPS

; price of good a (0..3) -> a. Uses port hash drift: base * (6 + h&7) / 10.
GoodPrice:
    ld [wPriceTmp], a
    ld a, [wPortHash]
    ld h, a
    ld a, [wPortHash+1]
    ld l, a
    ld a, [wPriceTmp]
    REPT 4                           ; i * 16 — cheap per-good hash spread
    add a, a
    ENDR
    xor l
    ld l, a
    call Mix16
    ld a, l
    and 7
    add 6                            ; factor 6..13
    ld b, a
    ld a, [wPriceTmp]
    ld hl, GOOD_BASE
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hl]                       ; base
    call Mul8                        ; base * factor
    ld b, 10
    call DivHLb
    ret

RenderTrade:
    ld hl, StrTradeHd
    ld de, $9800 + 5 * 32 + 3
    call PrintStr
    xor a
    ld [wPortK], a                 ; good index
.row
    ; name
    ld a, [wPortK]
    add 6
    push af
    call MapRowAddr
    ld bc, 2
    add hl, bc
    push hl
    pop de
    ld a, [wPortK]
    ld hl, GOOD_NAMES
    add a
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hli]
    ld h, [hl]
    ld l, a
    call PrintStr
    ; price
    pop af                           ; row
    push af
    call MapRowAddr
    ld bc, 9
    add hl, bc
    push hl
    pop de
    ld a, [wPortK]
    call GoodPrice
    call PrintDec3
    ; owned
    pop af
    push af
    call MapRowAddr
    ld bc, 14
    add hl, bc
    push hl
    pop de
    ld a, [wPortK]
    ld hl, wCargo
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hl]
    call PrintDec3
    pop af
    ld a, [wPortK]
    inc a
    ld [wPortK], a
    cp 4
    jr nz, .row
    ld hl, StrTradeHelp
    ld de, $9800 + 11 * 32 + 2
    call PrintStr
    call DrawCursor
    ret

; total cargo in a
TotalCargo:
    ld a, [wCargo]
    ld hl, wCargo+1
    add a, [hl]
    ld hl, wCargo+2
    add a, [hl]
    ld hl, wCargo+3
    add a, [hl]
    ret

TradeInput:
    ld a, [wJoyNew]
    and PADF_B
    jr z, .notB
    xor a
    ld [wPortState], a             ; back to PMAIN
    ld [wPortMenu], a
    jp .redraw
.notB
    ld a, [wJoyNew]
    and PADF_UP
    jr z, .notUp
    ld a, [wPortMenu]
    dec a
    and 3
    ld [wPortMenu], a
    jr .redraw
.notUp
    ld a, [wJoyNew]
    and PADF_DOWN
    jr z, .notDown
    ld a, [wPortMenu]
    inc a
    and 3
    ld [wPortMenu], a
    jr .redraw
.notDown
    ld a, [wJoyNew]
    and PADF_RIGHT
    jr z, .notRight
    ; buy 1
    ld a, [wPortMenu]
    call GoodPrice
    ld b, a                          ; price
    ld a, [wGold]
    ld l, a
    ld a, [wGold+1]
    ld h, a
    ; gold >= price?
    ld a, l
    cp b
    ld a, h
    sbc 0
    ret c
    call TotalCargo
    cp CARGO_MAX
    ret nc
    ; gold -= price
    ld a, [wGold]
    sub b
    ld [wGold], a
    ld a, [wGold+1]
    sbc 0
    ld [wGold+1], a
    ; cargo[sel]++
    ld a, [wPortMenu]
    ld hl, wCargo
    ld e, a
    ld d, 0
    add hl, de
    inc [hl]
    jr .redraw
.notRight
    ld a, [wJoyNew]
    and PADF_LEFT
    ret z
    ; sell 1
    ld a, [wPortMenu]
    ld hl, wCargo
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hl]
    and a
    ret z
    dec [hl]
    ld a, [wPortMenu]
    call GoodPrice
    ld b, a
    ld a, [wGold]
    add b
    ld [wGold], a
    ld a, [wGold+1]
    adc 0
    ld [wGold+1], a
.redraw
    ld a, 1
    ld [wPortDirty], a
    ret

; ---------------------------------------------------------------------------
; Tavern / repair / recruit / saved renders
; ---------------------------------------------------------------------------

RenderTavern:
    ld hl, StrTavern
    ld de, $9800 + 5 * 32 + 3
    call PrintStr
    ; flavor rumor (1 of 16)
    ld a, [wPortHash+1]
    and $0F
    ld hl, RUMORS
    add a
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld de, $9800 + 6 * 32
    call PrintStr
    ; nearest port
    call FindNearestPort
    ld a, [wNpFound]
    and a
    jr z, .noPort
    ; line 1: name of that port district
    ld a, [wNpX]
    ld b, a
    ld a, [wNpY]
    ld c, a
    call DistrictHash
    ld a, h
    ld [wPortHash], a              ; temporarily reuse for name gen
    ld a, l
    ld [wPortHash+1], a
    ld de, $9800 + 8 * 32 + 1
    call PrintPortName
    ; line 2: "nn DAYS d"
    ld a, [wNpDays]
    ld de, $9800 + 9 * 32 + 1
    call PrintDec2
    ld hl, StrDays
    ld de, $9800 + 9 * 32 + 3
    call PrintStr
    ld a, [wNpDir]
    ld hl, DIRS
    add a
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld de, $9800 + 9 * 32 + 9
    call PrintStr
    jr .restore
.noPort
    ld hl, StrNoRumor
    ld de, $9800 + 8 * 32 + 1
    call PrintStr
    ; fall through: the isle rumor is always worth printing
.restore
    ; restore current port hash
    ld a, [wPortDX]
    ld b, a
    ld a, [wPortDY]
    ld c, a
    call DistrictHash
    ld a, h
    ld [wPortHash], a
    ld a, l
    ld [wPortHash+1], a
    ; nearest unclaimed isle line
    call FindNearestIsle
    ld a, [wNpDays]
    cp 255
    ret z                          ; none left
    ld a, [wBestIsle]              ; legendary name of that isle
    ld hl, ISLE_NAMES
    add a
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld de, $9800 + 11 * 32 + 1
    call PrintStr
    ld a, [wNpDays]
    ld de, $9800 + 12 * 32 + 1
    call PrintDec2
    ld hl, StrDays
    ld de, $9800 + 12 * 32 + 3
    call PrintStr
    ld a, [wNpDir]
    ld hl, DIRS
    add a
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ld de, $9800 + 12 * 32 + 9
    call PrintStr
    ret

RenderRepair:
    ld hl, StrRepair
    ld de, $9800 + 5 * 32 + 3
    call PrintStr
    ld hl, StrRepairCost
    ld de, $9800 + 7 * 32 + 2
    call PrintStr
    ld hl, StrAConfirm
    ld de, $9800 + 9 * 32 + 2
    call PrintStr
    ret

RenderRecruit:
    ld hl, StrRecruit
    ld de, $9800 + 5 * 32 + 3
    call PrintStr
    ld hl, StrRecruitCost
    ld de, $9800 + 7 * 32 + 2
    call PrintStr
    ld hl, StrAConfirm
    ld de, $9800 + 9 * 32 + 2
    call PrintStr
    ret

; ---------------------------------------------------------------------------
; Port input
; ---------------------------------------------------------------------------
UpdatePort::
    ; re-render if dirty
    ld a, [wPortDirty]
    and a
    jr z, .input
    xor a
    ld [wPortDirty], a
    call LcdOff
    call RenderPort
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
.input
    ld a, [wPortState]
    and a
    jr z, MainInput
    cp PTRADE
    jp z, TradeInput
    ; all other sub-states: B returns to main, A acts (repair/recruit)
    ld a, [wJoyNew]
    and PADF_B
    jr z, .chkA
    xor a
    ld [wPortState], a
    ld [wPortMenu], a
    ld a, 1
    ld [wPortDirty], a
    ret
.chkA
    ld a, [wJoyNew]
    and PADF_A
    ret z
    ld a, [wPortState]
    cp PREPAIR
    jr z, .doRepair
    cp PRECRUIT
    ret nz
    call RecruitAction
    jr .acted
.doRepair
    call RepairAction
.acted
    ld a, 1
    ld [wPortDirty], a
    ret

MainInput:
    ld a, [wJoyNew]
    and PADF_B
    jr z, .notB
    ; set sail
    call SaveGame
    ld a, SONG_SAIL
    call SetSong
    call SailRedraw
    ld a, STATE_SAIL
    ld [wState], a
    ret
.notB
    ld a, [wJoyNew]
    and PADF_UP
    jr z, .notUp
    ld a, [wPortMenu]
    dec a
    and 7
    cp 6
    jr c, .ok1
    ld a, 5                        ; wrap: item 0 -> bottom item
.ok1
    ld [wPortMenu], a
    jr .moved
.notUp
    ld a, [wJoyNew]
    and PADF_DOWN
    jr z, .notDown
    ld a, [wPortMenu]
    inc a
    cp 6
    jr c, .ok2
    xor a
.ok2
    ld [wPortMenu], a
.moved
    call EraseCursors
    call DrawCursor
    ret
.notDown
    ld a, [wJoyNew]
    and PADF_A
    ret z
    ld a, [wPortMenu]
    and a
    jr z, .trade
    dec a
    jr z, .repair
    dec a
    jr z, .tavern
    dec a
    jr z, .recruit
    dec a
    jr z, .save
    ; SET SAIL
    call SaveGame
    call SailRedraw
    ld a, STATE_SAIL
    ld [wState], a
    ret
.trade
    ld a, PTRADE
    jr .enter
.repair
    ld a, PREPAIR
    jr .enter
.tavern
    ld a, PTAVERN
    jr .enter
.recruit
    ld a, PRECRUIT
    jr .enter
.save
    call SaveGame
    ld a, PSAVED
.enter
    ld [wPortState], a
    xor a
    ld [wPortMenu], a
    ld a, 1
    ld [wPortDirty], a
    ret

; Repair/recruit A-action handling happens in their input (shared sub-state
; input above only handles B). Add A actions here via state check:
RepairAction:
    ; repair all affordable: while hull < max && gold >= cost
.loop
    ld a, [wHull]
    cp HULL_MAX
    ret nc
    ld a, [wGold]
    ld l, a
    ld a, [wGold+1]
    ld h, a
    ld a, l
    cp REPAIR_COST
    ld a, h
    sbc 0
    ret c
    ld a, [wGold]
    sub REPAIR_COST
    ld [wGold], a
    ld a, [wGold+1]
    sbc 0
    ld [wGold+1], a
    ld a, [wHull]
    inc a
    ld [wHull], a
    jr .loop

RecruitAction:
    ld a, [wCrew]
    cp CREW_MAX
    ret nc
    ld a, [wGold]
    ld l, a
    ld a, [wGold+1]
    ld h, a
    ld a, l
    cp RECRUIT_COST
    ld a, h
    sbc 0
    ret c
    ld a, [wGold]
    sub RECRUIT_COST
    ld [wGold], a
    ld a, [wGold+1]
    sbc 0
    ld [wGold+1], a
    ld a, [wCrew]
    inc a
    ld [wCrew], a
    ret

; ---------------------------------------------------------------------------
; Text helpers
; ---------------------------------------------------------------------------

; hl = 0-terminated string, de = tilemap address. clobbers a, hl, de
PrintStr::
    ld a, [hli]
    and a
    ret z
    ld [de], a
    inc de
    jr PrintStr

; a = value -> 2 decimal digits at de (leading zero). clobbers a, b, c, de
PrintDec2::
    ld b, 10
    call DivA
    add TILE_HEX0
    ld [de], a
    inc de
    ld a, b
    add TILE_HEX0
    ld [de], a
    inc de
    ret

; a = value -> 3 decimal digits at de. clobbers a, b, c, de
PrintDec3::
    ld b, 100
    call DivA
    add TILE_HEX0
    ld [de], a
    inc de
    ld a, b
    ; fall through to PrintDec2


; hl = value -> 4 decimal digits at de. clobbers a, b, c, de, hl
; Values above 9999 are clamped (the field is only 4 tiles wide).
PrintDec4::
    ld a, h
    cp HIGH(9999)
    jr c, .inRange
    jr nz, .cap
    ld a, l
    cp LOW(9999)
    jr c, .inRange
    jr z, .inRange
.cap
    ld hl, 9999
.inRange
    ld bc, 1000
    call DivHL
    add TILE_HEX0
    ld [de], a
    inc de
    ld bc, 100
    call DivHL
    add TILE_HEX0
    ld [de], a
    inc de
    ld bc, 10
    call DivHL
    add TILE_HEX0
    ld [de], a
    inc de
    ld a, l
    add TILE_HEX0
    ld [de], a
    inc de
    ret

; a / b -> a, remainder in b. clobbers a, b
; a / b -> a (quotient), b = remainder. clobbers a, b, c
DivA:
    ld c, 0
.loop
    cp b
    jr c, .done
    sub b
    inc c
    jr .loop
.done
    ld b, a
    ld a, c
    ret

; hl / bc -> a (quotient < 256), hl = remainder. clobbers a, bc, hl
DivHL:
    xor a
.loop
    push af
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    jr c, .done
    pop af
    inc a
    jr .loop
.done
    ; undo last subtraction
    ld a, l
    add c
    ld l, a
    ld a, h
    adc b
    ld h, a
    pop af
    ret

; ---------------------------------------------------------------------------
; Port name generation
; ---------------------------------------------------------------------------

PUSHS "Port name tables", ROMX, BANK[3]
PORT_PREFIX: dw StrP0, StrP1, StrP2, StrP3, StrP4, StrP5, StrP6, StrP7
             dw StrP8, StrP9, StrP10, StrP11, StrP12, StrP13, StrP14, StrP15
PORT_SUFFIX: dw StrS0, StrS1, StrS2, StrS3, StrS4, StrS5, StrS6, StrS7
             dw StrS8, StrS9, StrS10, StrS11, StrS12, StrS13, StrS14, StrS15
POPS

; Print "PFX SFX" from wPortHash at de. clobbers a, b, c, hl, de
PrintPortName:
    ld a, [wPortHash+1]
    and $0F
    ld hl, PORT_PREFIX
    call .entry
    ld a, TILE_SPACE
    ld [de], a
    inc de
    ld a, [wPortHash+1]
    swap a
    and $0F
    ld hl, PORT_SUFFIX
.entry
    add a
    ld c, a
    ld b, 0
    add hl, bc
    ld a, [hli]
    ld h, [hl]
    ld l, a
    jp PrintStr

; ---------------------------------------------------------------------------
; Save / load (MBC5 battery RAM at $A000)
; ---------------------------------------------------------------------------

DEF SAVE_MAGIC_0 EQU $53
DEF SAVE_MAGIC_1 EQU $46
DEF SAVE_VERSION EQU 3          ; v3: + wPortCells (32 B). v2 saves rejected.

; Copy b bytes from de to hl, advancing both. clobbers a, b, de, hl
CopyToSRAM:
    ld a, [de]
    inc de
    ld [hli], a
    dec b
    jr nz, CopyToSRAM
    ret

; Save game state to cart RAM.
SaveGame::
    ld a, $0A
    ld [$0000], a                  ; RAM enable
    ld hl, $A000
    ld a, SAVE_MAGIC_0
    ld [hli], a
    ld a, SAVE_MAGIC_1
    ld [hli], a
    ld a, SAVE_VERSION
    ld [hli], a
    xor a
    ld [hli], a                    ; checksum placeholder
    ; data layout ($A004..$A05B): seed(4) pos(4) gold+hull+crew+cargo(8)
    ; explored(32) lastport(2) fragmask+guardmask(4) final+won(2) portcells(32)
    ld de, wSeed
    ld b, 4
    call CopyToSRAM
    ld de, wPosX                   ; wPosX/wPosY are contiguous
    ld b, 4
    call CopyToSRAM
    ld de, wGold                   ; wGold/wHull/wCrew/wCargo are contiguous
    ld b, 8
    call CopyToSRAM
    ld de, wExplored
    ld b, 32
    call CopyToSRAM
    ld de, wLastPortDX             ; DX/DY contiguous
    ld b, 2
    call CopyToSRAM
    ld de, wFragMask               ; wFragMask/wGuardMask contiguous
    ld b, 4
    call CopyToSRAM
    ld de, wFinal                  ; wFinal/wWon contiguous
    ld b, 2
    call CopyToSRAM
    ld de, wPortCells              ; $A03C..$A05B
    ld b, 32
    call CopyToSRAM
    ; checksum = sum of $A004..$A05B
    ld hl, $A004
    ld c, 88
    xor a
.sum
    add a, [hl]
    inc hl
    dec c
    jr nz, .sum
    ld [$A003], a
    xor a
    ld [$0000], a                  ; RAM disable
    ld a, 1
    ld [wHasSave], a               ; a save exists now: editor offers LOAD
    ret

; Copy b bytes from hl to de, advancing both. clobbers a, b, de, hl
CopyFromSRAM:
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, CopyFromSRAM
    ret

; Validate + load save. Sets wHasSave (1 = loaded). Called at boot.
LoadGame::
    ld a, $0A
    ld [$0000], a
    ; magic + version
    ld a, [$A000]
    cp SAVE_MAGIC_0
    jp nz, .fail
    ld a, [$A001]
    cp SAVE_MAGIC_1
    jp nz, .fail
    ld a, [$A002]
    cp SAVE_VERSION
    jp nz, .fail
    ; checksum
    ld hl, $A004
    ld c, 88
    xor a
.sum
    add a, [hl]
    inc hl
    dec c
    jr nz, .sum
    ld hl, $A003
    cp [hl]
    jp nz, .fail
    ; load fields (hl walks $A004..$A05B; runs mirror SaveGame)
    ld hl, $A004
    ld de, wSeed
    ld b, 4
    call CopyFromSRAM
    ld de, wPosX
    ld b, 4
    call CopyFromSRAM
    ld de, wGold
    ld b, 8
    call CopyFromSRAM
    ld de, wExplored
    ld b, 32
    call CopyFromSRAM
    ld de, wLastPortDX
    ld b, 2
    call CopyFromSRAM
    ld de, wFragMask
    ld b, 4
    call CopyFromSRAM
    ld de, wFinal
    ld b, 2
    call CopyFromSRAM
    ld de, wPortCells
    ld b, 32
    call CopyFromSRAM
    call FoldSeed16                ; wSeed16 first: ComputeIsles hashes with it
    call ComputeIsles              ; isles are derived, never saved
    xor a
    ld [wNeedSpawn], a             ; loaded: keep position
    ld a, 1
    ld [wHasSave], a
    xor a
    ld [$0000], a
    ret
.fail
    xor a
    ld [wHasSave], a
    ld [$0000], a
    ret

; ---------------------------------------------------------------------------
; Strings
; ---------------------------------------------------------------------------

SECTION "Port strings", ROMX, BANK[3]

StrGold::   db "GOLD", 0
StrHull:    db "HULL", 0
StrCrew:    db "CREW", 0
StrTrade:   db "TRADE", 0
StrRepair:  db "REPAIR", 0
StrTavern:  db "TAVERN", 0
StrRecruit: db "RECRUIT", 0
StrSave:    db "SAVE", 0
StrSetSail: db "SET SAIL", 0
StrSaved:   db "GAME SAVED", 0
StrAnyKey:  db "PRESS B TO RETURN", 0
StrTradeHd: db "GOODS   PRICE OWN", 0
StrTradeHelp: db "L SELL  R BUY  B BACK", 0
StrRepairCost: db "COST 2 PER POINT", 0
StrRecruitCost: db "COST 5 PER CREW", 0
StrAConfirm: db "PRESS A", 0
StrDays:    db " DAYS ", 0
StrNoRumor: db "NO NEWS TODAY", 0

StrRum:     db "RUM", 0
StrSilk:    db "SILK", 0
StrSpice:   db "SPICE", 0
StrCannon:  db "CANNON", 0

; M6: 16 rumors, all <= 20 chars (printed at col 0). Lore: PIRATE_LORE.md.
RUMORS: dw Rumor0, Rumor1, Rumor2, Rumor3, Rumor4, Rumor5, Rumor6, Rumor7
        dw Rumor8, Rumor9, RumorA, RumorB, RumorC, RumorD, RumorE, RumorF
Rumor0: db "THE RUM NEVER LIES", 0
Rumor1: db "DEAD MEN NEVER LIE", 0
Rumor2: db "THE NINE ISLES AWAIT", 0
Rumor3: db "BEASTS IN DEEP WATER", 0
Rumor4: db "ASK THE OLD SALT", 0
Rumor5: db "GOLD FAVORS THE BOLD", 0
Rumor6: db "STORMS BREW OFFSHORE", 0
Rumor7: db "X MARKS THE SPOT", 0
Rumor8: db "DAVY JONES WAITS", 0
Rumor9: db "THE RED FLAG FLIES", 0
RumorA: db "THE KRAKEN SURFACED", 0
RumorB: db "A GHOST SHIP SAILS", 0
RumorC: db "NO PREY NO PAY", 0
RumorD: db "WHYDAH LIES DEEP", 0
RumorE: db "KIDD WAS HERE", 0
RumorF: db "LIBERTALIA IS REAL", 0

DIRS: dw DirN, DirNE, DirE, DirSE, DirS, DirSW, DirW, DirNW
DirN:  db "N", 0
DirNE: db "NE", 0
DirE:  db "E", 0
DirSE: db "SE", 0
DirS:  db "S", 0
DirSW: db "SW", 0
DirW:  db "W", 0
DirNW: db "NW", 0

; M6: lore pass (PIRATE_LORE.md). STORM must stay at index 8 (test_m3).
StrP0:  db "PORT", 0
StrP1:  db "JOLLY", 0
StrP2:  db "RUM", 0
StrP3:  db "SALT", 0
StrP4:  db "GULL", 0
StrP5:  db "DAVY", 0
StrP6:  db "RED", 0
StrP7:  db "BLACK", 0
StrP8:  db "STORM", 0
StrP9:  db "SHARK", 0
StrP10: db "GROG", 0
StrP11: db "OLD", 0
StrP12: db "BONNY", 0
StrP13: db "DEAD", 0
StrP14: db "MAROON", 0
StrP15: db "KRAKEN", 0

; M6: lore pass. WATCH must stay at index 12 (test_m3).
StrS0:  db "BAY", 0
StrS1:  db "LOCKER", 0
StrS2:  db "HAVEN", 0
StrS3:  db "ROADS", 0
StrS4:  db "COVE", 0
StrS5:  db "REST", 0
StrS6:  db "DOCK", 0
StrS7:  db "SHORE", 0
StrS8:  db "POINT", 0
StrS9:  db "LANDING", 0
StrS10: db "HOLLOW", 0
StrS11: db "ANCHOR", 0
StrS12: db "WATCH", 0
StrS13: db "REEF", 0
StrS14: db "INLET", 0
StrS15: db "REACH", 0

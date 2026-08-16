; The Nine Isles: placement, guardians, treasure digs, finale, victory.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"
INCLUDE "text.inc"

SECTION "Isles WRAM", WRAM0
wIsles:      ds 18        ; 9 x (cellX, cellY)
wFragMask::  dw           ; fragment collected per isle
wGuardMask:: dw           ; guardian defeated per isle
wCurIsle::   db
wIsGuardian:: db
wFinal::     db           ; 0=none, 1-4=wave to spawn, 5=all spawned, 6=done
wWon::       db
wLastCellX:  db
wLastCellY:  db
wBaseTX:     dw
wBaseTY:     dw
wNpDir::     db
wNpDays::    db
wBestK:      db
wBestIsle::  db           ; isle index of nearest unclaimed (tavern rumor)
wDigT::      db           ; dig-ceremony frames left (0 = reveal shown)
wDigCount:   db           ; fragment count saved for the reveal

SECTION "Isles", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; Placement: 9 isles at 40-degree intervals around center (8,8), jittered,
; validated to contain land. Deterministic from the seed.
; ---------------------------------------------------------------------------

PUSHS "Isle placement tables", ROMX, BANK[3]
ISLE_DX: db  6,  5,  1, -3, -6, -6, -3,  1,  5
ISLE_DY: db  0,  4,  6,  5,  2, -2, -5, -6, -4
; attempt offsets for the land scan
ISLE_TRY_DX: db 0, 1, -1, 0, 0, 1
ISLE_TRY_DY: db 0, 0, 0, 1, -1, 1
POPS

ComputeIsles::
    xor a
    ld [wChX], a                   ; k
.kLoop
    ; base = center + dir[k]
    ld a, [wChX]
    ld hl, ISLE_DX
    ld e, a
    ld d, 0
    add hl, de
    ld b, [hl]
    ld hl, ISLE_DY
    add hl, de
    ld c, [hl]
    ; jitter: h = Mix16(seed16 ^ k*251)
    ld a, [wChX]
    push bc
    ld b, 251
    call Mul8
    ld a, [wSeed16]
    xor h
    ld h, a
    ld a, [wSeed16+1]
    xor l
    ld l, a
    call Mix16
    pop bc
    ; jx = (h & 3) - 1, jy = ((h>>4) & 3) - 1; clamp to [1,14]
    ld a, l
    and 3
    dec a
    add b
    add 8                          ; + center
    cp 14
    jr c, .xOk
    ld a, 14
.xOk
    and a
    jr nz, .xOk2
    ld a, 1
.xOk2
    ld [wChY], a                   ; candidate cx
    ld a, h
    swap a
    and 3
    dec a
    add c
    add 8
    cp 14
    jr c, .yOk
    ld a, 14
.yOk
    and a
    jr nz, .yOk2
    ld a, 1
.yOk2
    ld [wJ], a                     ; candidate cy
    ; land scan over attempt offsets
    xor a
    ld [wBestK], a                   ; attempt counter (wJCount is CellHasLand's)
.try
    ld a, [wChY]
    ld hl, wBestK
    push af
    ld a, [hl]
    ld hl, ISLE_TRY_DX
    ld e, a
    ld d, 0
    add hl, de
    ld b, [hl]
    ld hl, ISLE_TRY_DY
    add hl, de
    ld c, [hl]
    pop af
    add b
    and 15                         ; keep cell coords in [0,15]
    ld [wCandX], a                 ; cx
    ld a, [wJ]
    add c
    and 15
    ld [wCandY], a                 ; cy
    call CellHasLand
    and a
    jr nz, .accept
    ld a, [wBestK]
    inc a
    ld [wBestK], a
    cp 6
    jr nz, .try
.accept
    ; store isle k
    ld a, [wChX]
    add a
    ld e, a
    ld d, 0
    ld hl, wIsles
    add hl, de
    ld a, [wCandX]
    ld [hli], a
    ld a, [wCandY]
    ld [hl], a
    ; next k
    ld a, [wChX]
    inc a
    ld [wChX], a
    cp 9
    jp nz, .kLoop
    ret

PUSHS "Isle land-sample offsets", ROMX, BANK[3]
CHL_OFFSETS: db 10, 9, 5, 5, 15, 13
POPS

; in: wCandX, wCandY (cell coords); out: a = 1 iff any sampled land tile
CellHasLand:
    ld a, [wCandX]
    ld b, 20
    call Mul8
    ld a, l
    ld [wBaseTX], a
    ld a, h
    ld [wBaseTX+1], a
    ld a, [wCandY]
    ld b, 18
    call Mul8
    ld a, l
    ld [wBaseTY], a
    ld a, h
    ld [wBaseTY+1], a
    xor a
    ld [wJCount], a
.loop
    ld a, [wJCount]
    add a
    ld hl, CHL_OFFSETS
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hli]
    ld b, a                        ; dx offset
    ld c, [hl]                     ; dy offset
    ld a, [wBaseTY]
    add c
    ld e, a
    ld a, [wBaseTY+1]
    adc 0
    ld d, a                        ; de = wy
    ld a, [wBaseTX]
    add b
    ld c, a
    ld a, [wBaseTX+1]
    adc 0
    ld b, a                        ; bc = wx
    call WorldTile
    cp TILE_SAND
    jr nc, .yes
    ld a, [wJCount]
    inc a
    ld [wJCount], a
    cp 3
    jr nz, .loop
    xor a
    ret
.yes
    ld a, 1
    ret

; ---------------------------------------------------------------------------
; Bit helpers (9 isles -> 16-bit masks)
; ---------------------------------------------------------------------------

; in: a = index (0..8); out: hl = 1 << index
BitMask16:
    ld hl, 1
    inc a
    jr .s
.m
    add hl, hl
.s
    dec a
    jr nz, .m
    ret

; in: a = isle index; out: a = 1 iff fragment collected
TestFrag::
    call BitMask16
    ld a, [wFragMask]
    and l
    ld b, a
    ld a, [wFragMask+1]
    and h
    or b
    ld a, 0
    ret z
    inc a
    ret

; in: a = isle index; out: a = 1 iff guardian defeated
TestGuard::
    call BitMask16
    ld a, [wGuardMask]
    and l
    ld b, a
    ld a, [wGuardMask+1]
    and h
    or b
    ld a, 0
    ret z
    inc a
    ret

; in: a = isle index; set its fragment bit
SetFrag:
    call BitMask16
    ld a, [wFragMask]
    or l
    ld [wFragMask], a
    ld a, [wFragMask+1]
    or h
    ld [wFragMask+1], a
    ret

; in: a = isle index; set its guardian-defeated bit
SetGuardBit::
    call BitMask16
    ld a, [wGuardMask]
    or l
    ld [wGuardMask], a
    ld a, [wGuardMask+1]
    or h
    ld [wGuardMask+1], a
    ret

; in: b = cellX, c = cellY; out: a = isle index or $FF
IsIsleCell::
    ld hl, wIsles
    ld d, 0
.loop
    ld a, [hli]
    cp b
    jr nz, .no
    ld a, [hl]
    cp c
    jr nz, .no
    ld a, d
    ret
.no
    inc hl
    inc d
    ld a, d
    cp 9
    jr nz, .loop
    ld a, $FF
    ret

; ---------------------------------------------------------------------------
; Guardians & the final battle
; ---------------------------------------------------------------------------

SpawnGuardian:
    call SpawnEnemy
    ld a, [wEnemyActive]
    and a
    ret z                          ; spawn aborted (land)
    ld a, [wFinal]
    and a
    jr nz, .finalWave
    ld a, GUARD_HP
    ld [wEnemyHP], a
    ld a, GUARD_FIRECOOL
    ld [wEnemyFireCool], a
    jr .mark
.finalWave
    ; the final fleet escalates per wave k (= wFinal): HP 5+k, cooldown 50-8k
    ld b, a
    add GUARD_HP
    ld [wEnemyHP], a
    ld a, b
    REPT 3
    add a
    ENDR                           ; 8k
    ld b, a
    ld a, GUARD_FIRECOOL
    sub b
    ld [wEnemyFireCool], a
.mark
    ld a, 1
    ld [wIsGuardian], a
    ret

; Per-frame isle/final-battle watch (from UpdateSail).
CellWatch::
    ld a, [wFinal]
    and a
    jr z, .notFinal
    cp 5
    ret nc                         ; all waves spawned (or done)
    ld a, [wEnemyActive]
    and a
    ret nz
    ld a, [wMerchActive]
    and a
    ret nz                         ; don't crash a merchant parley
    call SpawnGuardian
    ld a, [wEnemyActive]
    and a
    ret z                          ; spawn aborted (land): retry next frame
    ld hl, wFinal
    inc [hl]                       ; consume the wave only if it spawned
    ret
.notFinal
    ; track cell changes (dig/wCurIsle bookkeeping)
    ld a, [wShipCX]
    ld hl, wLastCellX
    cp [hl]
    jr nz, .changed
    ld a, [wShipCY]
    ld hl, wLastCellY
    cp [hl]
    jr z, .sameCell
.changed
    ld a, [wShipCX]
    ld [wLastCellX], a
    ld a, [wShipCY]
    ld [wLastCellY], a
.sameCell
    ; isle cell with a living guardian and no active enemy?
    ld a, [wShipCX]
    ld b, a
    ld a, [wShipCY]
    ld c, a
    call IsIsleCell
    cp $FF
    ret z
    ld [wCurIsle], a
    call TestGuard
    and a
    ret nz                         ; already defeated
    ld a, [wEnemyActive]
    and a
    ret nz
    ld a, [wMerchActive]
    and a
    ret nz                         ; don't crash a merchant parley
    call SpawnGuardian             ; aborts on land: retried next frame
    ret

; ---------------------------------------------------------------------------
; The dig
; ---------------------------------------------------------------------------

; Player digs on isle wCurIsle: a short ceremony (knocks in the sand),
; then DigReveal pays off. Any key skips the ceremony.
DigScene::
    ld a, [wCurIsle]
    call SetFrag
    call CountFrags
    ld [wDigCount], a              ; the reveal reads it after the ceremony
    call LcdOff
    call DrawSeedScreen
    ld hl, StrDigSpot
    ld de, $9800 + 4 * 32 + 2
    call PrintStr
    ld hl, StrDigging
    ld de, $9800 + 6 * 32 + 6
    call PrintStr
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    ld a, 90
    ld [wDigT], a
    ld a, SFX_KNOCK
    call PlaySfx
    ld a, STATE_DIG
    ld [wState], a
    ret

; The dig pays off: the fragment count screen, or the final battle at 9.
DigReveal:
    ld a, JINGLE_DIG
    call SetSong
    ld a, [wDigCount]
    cp 9
    jr z, .final
    ; render: "YOU FOUND A CHART FRAGMENT!" + "k OF 9"
    push af
    call LcdOff
    call DrawSeedScreen
    ld hl, StrFound1
    ld de, $9800 + 4 * 32 + 5
    call PrintStr
    ld hl, StrFound2
    ld de, $9800 + 5 * 32 + 3
    call PrintStr
    pop af
    ld de, $9800 + 7 * 32 + 7
    call PrintDec2
    ld hl, StrOf9
    ld de, $9800 + 7 * 32 + 9
    call PrintStr
    jr .show
.final
    ; 9th fragment: begin the final battle
    ld a, 1
    ld [wFinal], a
    call LcdOff
    call DrawSeedScreen
    ld hl, StrFinal1
    ld de, $9800 + 4 * 32 + 2
    call PrintStr
    ld hl, StrFinal2
    ld de, $9800 + 5 * 32 + 4
    call PrintStr
.show
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    ret

UpdateDig::
    ld a, [wDigT]
    and a
    jr z, .revealed
    ld b, a
    ld a, [wJoyNew]
    and a
    jr nz, .revealNow              ; any key skips the ceremony
    ld a, b
    dec a
    ld [wDigT], a
    jr z, .revealNow
    cp 60
    jr z, .knock
    cp 30
    ret nz
.knock
    ld a, SFX_KNOCK
    call PlaySfx
    ret
.revealNow
    xor a
    ld [wDigT], a
    call DigReveal
    ret
.revealed
    ld a, [wJoyNew]
    and a
    ret z
    call SailRedraw
    ld a, STATE_SAIL
    ld [wState], a
    ret

; a = number of set bits in wFragMask. clobbers a, c, d, h, l
CountFrags::
    ld a, [wFragMask]
    ld l, a
    ld a, [wFragMask+1]
    ld h, a
    ld c, 0
    ld d, 9
.loop
    srl h
    rr l
    jr nc, .no
    inc c
.no
    dec d
    jr nz, .loop
    ld a, c
    ret

; ---------------------------------------------------------------------------
; Victory
; ---------------------------------------------------------------------------
Victory::
    ld a, 6
    ld [wFinal], a
    ld a, 1
    ld [wWon], a
    ld a, JINGLE_WIN
    call SetSong
    call SaveGame
    call LcdOff
    xor a
    ldh [rSCX], a
    ldh [rSCY], a
    call DrawSeedScreen
    ld hl, StrWin1
    ld de, $9800 + 3 * 32 + 1
    call PrintStr
    ld hl, StrWin2
    ld de, $9800 + 4 * 32
    call PrintStr
    ld hl, StrGold
    ld de, $9800 + 6 * 32 + 6
    call PrintStr
    ld a, [wGold+1]
    ld h, a
    ld a, [wGold]
    ld l, a
    ld de, $9800 + 6 * 32 + 11
    call PrintDec4
    ld hl, StrTheEnd
    ld de, $9800 + 9 * 32 + 7
    call PrintStr
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    ld a, STATE_WIN
    ld [wState], a
    ret

UpdateWin::
    ld a, [wJoyNew]
    and a
    ret z
    call SailRedraw
    ld a, STATE_SAIL
    ld [wState], a
    ret

; ---------------------------------------------------------------------------
; Tavern: nearest unclaimed isle
; ---------------------------------------------------------------------------
FindNearestIsle::
    xor a
    ld [wChX], a                   ; k
    ld a, 255
    ld [wNpDays], a                ; best distance
.next
    ld a, [wChX]
    call TestFrag
    and a
    jr nz, .skip
    ; isle coords
    ld a, [wChX]
    add a
    ld e, a
    ld d, 0
    ld hl, wIsles
    add hl, de
    ld a, [hli]
    ld b, a
    ld c, [hl]
    ; dx = isleX - shipCX, dy = isleY - shipCY
    ld a, b
    ld hl, wShipCX
    sub [hl]
    ld b, a
    ld a, c
    ld hl, wShipCY
    sub [hl]
    ld c, a
    ; dist = max(|dx|, |dy|)
    ld a, b
    call AbsA
    ld e, a
    ld a, c
    call AbsA
    cp e
    jr nc, .m
    ld a, e
.m
    ld hl, wNpDays
    cp [hl]
    jr nc, .skip
    ld [hl], a                     ; new best
    ld a, [wChX]
    ld [wBestIsle], a              ; remember which isle it is
    call SnapDir
    ld [wNpDir], a
.skip
    ld a, [wChX]
    inc a
    ld [wChX], a
    cp 9
    jr nz, .next
    ret

; ---------------------------------------------------------------------------
; Strings
; ---------------------------------------------------------------------------
SECTION "Isle strings", ROMX, BANK[3]
StrFound1: db "YOU FOUND A", 0
StrFound2: db "CHART FRAGMENT!", 0
StrDigSpot: db "X MARKS THE SPOT!", 0
StrDigging: db "DIGGING", 0
StrOf9:    db "OF 9", 0
StrFinal1: db "THE FINAL BATTLE", 0
StrFinal2: db "APPROACHES!", 0
StrWin1:   db "THE TREASURE OF THE", 0
StrWin2:   db "NINE ISLES IS YOURS!", 0
StrTheEnd: db "THE END", 0

; Legendary name per isle (lore: PIRATE_LORE.md). Printed in the tavern.
ISLE_NAMES::
    dw IsleN0, IsleN1, IsleN2, IsleN3, IsleN4, IsleN5, IsleN6, IsleN7, IsleN8
IsleN0: db "LIBERTALIA:", 0
IsleN1: db "WHYDAH DEEP:", 0
IsleN2: db "KRAKEN SKERRY:", 0
IsleN3: db "THE LOCKER:", 0
IsleN4: db "OLD ROGER ROCK:", 0
IsleN5: db "KIDDS CACHE:", 0
IsleN6: db "FIDDLERS GREEN:", 0
IsleN7: db "DUTCHMAN CAPE:", 0
IsleN8: db "MAROON SPIT:", 0

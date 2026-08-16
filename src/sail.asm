; Sailing mode: momentum physics, smooth scrolling over an on-demand
; procedural ocean, animated water, shadow-OAM ship sprite, window HUD.
;
; Streaming pipeline: UpdateSail (logic phase) detects tile-boundary
; crossings and generates the entering row/column into staging buffers;
; SailVBlank blits staged tiles into the BG map during Mode 1.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"
INCLUDE "text.inc"

SECTION "Sail WRAM", WRAM0
wPosX::     dw              ; 12.4 fixed-point ship position
wPosY::     dw
wOldPosX:   dw
wOldPosY:   dw
wVelX:      db              ; signed, 1/16 px/frame
wVelY:      db
wShipX::    dw              ; pixel position
wShipY::    dw
wCamX::     dw              ; viewport top-left in pixels
wCamY::     dw
wTileX::    dw              ; leftmost visible world tile (0..299)
wTileY::    dw
wHeading::  db              ; 0=N 1=E 2=S 3=W
wAnimPhase: db
wHudDigits: ds 8            ; TX (3), TY (3), SPD (2)
wQuitCfm::  db              ; B-quit confirm window (frames left)
wHudRow1:   ds 15           ; window row 1: stats line / quit message
wShakeT::   db              ; screen-shake frames (set on hull damage)
wHitFlashT:: db             ; BGP damage-flash frames

SECTION "Shadow OAM", WRAM0, ALIGN[8]
wShadowOAM:: ds 160

SECTION "Sail HRAM", HRAM
hOamDma::   ds 10

SECTION "OAM DMA routine", ROMX, BANK[3]
; Copied to HRAM at boot; call hOamDma during VBlank.
RunDmaROM::
    ld a, HIGH(wShadowOAM)
    ldh [rDMA], a
    ld a, 40                       ; 160 M-cycles
.wait
    dec a
    jr nz, .wait
    ret
.end::

SECTION "Sailing", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; Mode entry/exit
; ---------------------------------------------------------------------------

; Enters sailing mode from the editor: find a spawn if needed, reset the ship.
EnterSail::
    call LcdOff
    ld a, [wNeedSpawn]
    and a
    jr z, .noSpawn
    call FindSpawn                   ; sets wPosX/wPosY
    xor a
    ld [wNeedSpawn], a
.noSpawn
    xor a
    ld [wVelX], a
    ld [wVelY], a
    ld [wHeading], a
    ld [wAnimPhase], a
    ld [wStagePend], a
    ld [wDmgCool], a
    ld [wQuitCfm], a
    ld [wShakeT], a
    ld [wHitFlashT], a
    ld hl, wHudRow1            ; first SailVBlank runs before the first
    ld b, 15                   ; SailHud: don't show power-on garbage
.clrRow1
    ld [hli], a
    dec b
    jr nz, .clrRow1
    call ComputeShipPx
    call SailCamera
    call SailRedrawBody
    call SGBTransferBorder       ; the seed is final now: send its border
    and a
    jr z, .noSGB                 ; not SGB: nothing was touched
    call SailRedrawBody          ; rebuild what the transfer trashed
    call SGBUnfreeze
.noSGB
    ld a, SONG_SAIL
    call SetSong
    ret

; Rebuild the sailing screen (used by chart exit). LCD on.
SailRedraw::
    call LcdOff
    call SailRedrawBody
    ret

; LCD off -> fully rebuilt -> LCD on.
SailRedrawBody:
    call ComputeTiles
    call SailFillScreen
    call SetupHud
    call SailSprite
    ld a, [wCamX]
    ldh [rSCX], a
    ld a, [wCamY]
    ldh [rSCY], a
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01 | LCDC_OBJ_ON | LCDC_WIN_ON | LCDC_WIN_9C00
    ldh [rLCDC], a
    ret

; Back to the seed editor.
LeaveSail:
    call LcdOffHome                ; editor is unscrolled; restore palette
    xor a
    ld [$FE00], a                  ; hide ship sprite (LCD off: OAM free)
    call DrawSeedScreen
    call DrawSeedHints
    call RenderSeedRow
    call ShowTextScreen
    xor a
    ld [wState], a                 ; STATE_EDIT
    ret

; wTileX/wTileY = camera in whole tiles
ComputeTiles:
    ld a, [wCamX]
    ld l, a
    ld a, [wCamX+1]
    ld h, a
    SR16 h, l, 3
    ld a, l
    ld [wTileX], a
    ld a, h
    ld [wTileX+1], a
    ld a, [wCamY]
    ld l, a
    ld a, [wCamY+1]
    ld h, a
    SR16 h, l, 3
    ld a, l
    ld [wTileY], a
    ld a, h
    ld [wTileY+1], a
    ret

; Initial 21x19 fill of the BG map (LCD off; generation is slow, that's OK).
SailFillScreen:
    ld a, [wTileY]
    ld e, a
    ld a, [wTileY+1]
    ld d, a
    ld c, 19
.row
    push de
    push bc
    call GenRowStage
    call BlitRowStage
    pop bc
    pop de
    inc de
    dec c
    jr nz, .row
    ret

; Window map init: clear 2 rows, write static labels, set WX/WY (LCD off).
SetupHud:
    ld hl, $9C00
    ld b, 64
    xor a
.clr
    ld [hli], a
    dec b
    jr nz, .clr
    ld a, TILE_LET_X
    ld [$9C00], a
    ld a, TILE_LET_Y
    ld [$9C00+5], a
    ld a, TILE_LET_S
    ld [$9C00+10], a
    ld a, TILE_LET_P
    ld [$9C00+11], a
    ld a, 7
    ldh [rWX], a
    ld a, 128
    ldh [rWY], a
    ret

; ---------------------------------------------------------------------------
; Per-frame VBlank work (called first thing after halt; we are in Mode 1)
; ---------------------------------------------------------------------------
SailVBlank::
    ; damage flash beats the storm palette
    ld a, [wHitFlashT]
    and a
    jr z, .noFlash
    ld a, $1B                      ; inverted burst: you got hit
    jr .bgp
.noFlash
    ; storm palette override
    ld a, [wStormT]
    ld b, a
    ld a, [wStormT+1]
    or b
    jr z, .calm
    ld a, $F9                      ; one step darker per index
    jr .bgp
.calm
    ld a, $E4
.bgp
    ldh [rBGP], a
    ; screen shake while wShakeT is live (alternate SCX +-2 every 2 frames)
    ld a, [wCamX]
    ld b, a
    ld a, [wShakeT]
    and a
    jr z, .steady
    and 2
    jr z, .shakeL
    ld a, b
    add 2
    jr .scx
.shakeL
    ld a, b
    sub 2
    jr .scx
.steady
    ld a, b
.scx
    ldh [rSCX], a
    ld a, [wCamY]
    ldh [rSCY], a
    call hOamDma                 ; DMA mid-frame garbles sprites: VBlank only
    ; staged tiles from the logic phase. The blit loops poll STAT before
    ; each write, so overrunning VBlank stretches into the visible frame
    ; instead of dropping writes (see BlitRowPass).
    ld a, [wStagePend]
    and a
    jr z, .noPend
    bit 0, a
    jr z, .noCol
    call BlitColStage
.noCol
    ld a, [wStagePend]
    bit 1, a
    jr z, .noRow
    call BlitRowStage
.noRow
    xor a
    ld [wStagePend], a
.noPend
    call AnimWater
    call HudVBlank
    ret

; Swap the two water tiles' graphics every 16 frames.
AnimWater:
    ld a, [wFrameCounter]
    and $0F
    ret nz
    ld a, [wAnimPhase]
    xor 1
    ld [wAnimPhase], a
    ld hl, WaterFrames
    and a
    jr z, .copy
    ld bc, 32
    add hl, bc
.copy
    ld de, $8000 + 16              ; tiles 1 (deep) and 2 (shallow)
    ld bc, 32
    call CopyVRAM
    ret

; Write the 8 HUD digit tiles into the window map.
HudVBlank:
    ld hl, wHudDigits
    ld a, [hli]
    ld [$9C01], a
    ld a, [hli]
    ld [$9C02], a
    ld a, [hli]
    ld [$9C03], a
    ld a, [hli]
    ld [$9C06], a
    ld a, [hli]
    ld [$9C07], a
    ld a, [hli]
    ld [$9C08], a
    ld a, [hli]
    ld [$9C0C], a
    ld a, [hli]
    ld [$9C0D], a
    ; window row 1: 15 tiles staged by SailHud (stats or quit confirm)
    ld hl, wHudRow1
    ld de, $9C20
    ld b, 15
.row1
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .row1
    ret

; ---------------------------------------------------------------------------
; Game logic (runs after VBlank work; no VRAM access here)
; ---------------------------------------------------------------------------
UpdateSail::
    ; B quits to the seed screen UNSAVED: require a confirming second press
    ld a, [wJoyNew]
    and PADF_B
    jr z, .notB
    ld a, [wQuitCfm]
    and a
    jr nz, .quit
    ld a, QUIT_CFM_T
    ld [wQuitCfm], a
    jr .notB
.quit
    xor a
    ld [wQuitCfm], a
    call LeaveSail
    ret
.notB
    ld a, [wJoyNew]
    and PADF_START
    jr z, .stay
    call EnterChart
    ret
.stay
    ; damage cooldown tick
    ld a, [wDmgCool]
    and a
    jr z, .noCool
    dec a
    ld [wDmgCool], a
.noCool
    ; quit-confirm window tick
    ld a, [wQuitCfm]
    and a
    jr z, .noCfm
    dec a
    ld [wQuitCfm], a
.noCfm
    ; juice timers
    ld a, [wShakeT]
    and a
    jr z, .noShakeT
    dec a
    ld [wShakeT], a
.noShakeT
    ld a, [wHitFlashT]
    and a
    jr z, .noHitT
    dec a
    ld [wHitFlashT], a
.noHitT
    ; A = dock if possible, else fire cannons
    ld a, [wJoyNew]
    and PADF_A
    jr z, .noDock
    call TryDock
    ld a, [wState]
    cp STATE_SAIL
    ret nz                         ; docked or dug: no cannons either way
    call FireCannon
.noDock
    ; save position for collision revert
    ld a, [wPosX]
    ld [wOldPosX], a
    ld a, [wPosX+1]
    ld [wOldPosX+1], a
    ld a, [wPosY]
    ld [wOldPosY], a
    ld a, [wPosY+1]
    ld [wOldPosY+1], a
    call SailPhysics
    call StormTick                   ; storm drift is movement: it must run
                                     ; before the collision check below,
                                     ; else it drags the ship across land
    call ComputeShipPx
    call SailCollide
    call SailCamera
    call CheckStream               ; generate newly-visible row/column
    call MarkExplored
    and a
    jr z, .notNew
    dec a
    jr z, .firstChart
    call RevisitRoll               ; re-entered charted cell: reduced odds
    jr .notNew
.firstChart
    call SpawnCheck                ; newly charted cell: roll encounters
.notNew
    call CellWatch                 ; isle guardians / final battle
    call UpdateCombat
    call SailSprite
    call RenderCombat
    call SailHud
    ; music: battle theme while an enemy or storm is active
    ld a, [wEnemyActive]
    and a
    jr nz, .musBat
    ld a, [wStormT]
    ld b, a
    ld a, [wStormT+1]
    or b
    jr z, .musCalm
.musBat
    ld a, SONG_BATTLE
    jr .musSet
.musCalm
    ld a, SONG_SAIL
.musSet
    ld hl, wSongID
    cp [hl]
    call nz, SetSong
    ret

SailPhysics:
    ; --- thrust + drag, X axis (b = thrust flag for Drag) ---
    ld b, 0
    ld a, [wJoyHeld]
    and PADF_RIGHT
    jr z, .noRight
    ld a, [wVelX]
    inc a
    call ClampVel
    ld [wVelX], a
    ld b, 1
.noRight
    ld a, [wJoyHeld]
    and PADF_LEFT
    jr z, .noLeft
    ld a, [wVelX]
    dec a
    call ClampVel
    ld [wVelX], a
    ld b, 1
.noLeft
    ld a, [wVelX]
    call Drag
    ld [wVelX], a
    ; --- thrust + drag, Y axis ---
    ld b, 0
    ld a, [wJoyHeld]
    and PADF_UP
    jr z, .noUp
    ld a, [wVelY]
    dec a
    call ClampVel
    ld [wVelY], a
    ld b, 1
.noUp
    ld a, [wJoyHeld]
    and PADF_DOWN
    jr z, .noDown
    ld a, [wVelY]
    inc a
    call ClampVel
    ld [wVelY], a
    ld b, 1
.noDown
    ld a, [wVelY]
    call Drag
    ld [wVelY], a
    ; --- heading from d-pad ---
    ld a, [wJoyHeld]
    and PADF_UP
    jr z, .h1
    xor a
    jr .setH
.h1
    ld a, [wJoyHeld]
    and PADF_DOWN
    jr z, .h2
    ld a, 2
    jr .setH
.h2
    ld a, [wJoyHeld]
    and PADF_RIGHT
    jr z, .h3
    ld a, 1
    jr .setH
.h3
    ld a, [wJoyHeld]
    and PADF_LEFT
    jr z, .noH
    ld a, 3
.setH
    ld [wHeading], a
.noH
    ; --- integrate X ---
    ld a, [wVelX]
    ld l, a
    ld h, 0
    bit 7, a
    jr z, .posX
    dec h
.posX
    ld a, [wPosX]
    add l
    ld [wPosX], a
    ld a, [wPosX+1]
    adc h
    ld [wPosX+1], a
    ; clamp [0, SHIP_MAX_X<<4]: hi >= $F0 = wrapped negative
    cp $F0
    jr nc, .zeroX
    cp HIGH(SHIP_MAX_X << 4)
    jr c, .doneX
    jr nz, .clampX
    ld a, [wPosX]
    cp LOW(SHIP_MAX_X << 4)
    jr c, .doneX
.clampX
    ld a, LOW(SHIP_MAX_X << 4)
    ld [wPosX], a
    ld a, HIGH(SHIP_MAX_X << 4)
    ld [wPosX+1], a
    jr .doneX
.zeroX
    xor a
    ld [wPosX], a
    ld [wPosX+1], a
.doneX
    ; --- integrate Y ---
    ld a, [wVelY]
    ld l, a
    ld h, 0
    bit 7, a
    jr z, .posY
    dec h
.posY
    ld a, [wPosY]
    add l
    ld [wPosY], a
    ld a, [wPosY+1]
    adc h
    ld [wPosY+1], a
    cp $F0
    jr nc, .zeroY
    cp HIGH(SHIP_MAX_Y << 4)
    jr c, .doneY
    jr nz, .clampY
    ld a, [wPosY]
    cp LOW(SHIP_MAX_Y << 4)
    jr c, .doneY
.clampY
    ld a, LOW(SHIP_MAX_Y << 4)
    ld [wPosY], a
    ld a, HIGH(SHIP_MAX_Y << 4)
    ld [wPosY+1], a
    jr .doneY
.zeroY
    xor a
    ld [wPosY], a
    ld [wPosY+1], a
.doneY
    ret

; Clamp a to [-wMaxVel, +wMaxVel] (signed via $80 bias). The swift-sails
; shipyard upgrade raises wMaxVel from 40 to 48.
ClampVel:
    add $80
    ld c, a                      ; biased velocity
    ld a, [wMaxVel]
    add $80                      ; $80 + max
    ld b, a
    ld a, c
    cp b
    jr c, .lo
    ld a, b
.lo
    ld c, a
    ld a, [wMaxVel]
    cpl
    inc a                        ; -max
    add $80                      ; $80 - max
    ld b, a
    ld a, c
    cp b
    jr nc, .ok
    ld a, b
.ok
    sub $80
    ret

; Drag: a -= sign(a) * |a|/32 (truncate toward zero; sra would floor, and
; floor(v/32) = -1 for every v in [-32,-1], exactly canceling 1/frame
; thrust — that pinned negative velocity at 0 and made west/north
; unsailable). Swift sails halve the drag (|a|/64): the sustained top
; speed is thrust x divisor, so 32 stock and the 48 clamp when fitted.
; With no thrust, nudges by 1 so ships fully stop; while thrusting there
; is no low-speed drag (else thrust never wins).
; in: a = velocity, b = thrust flag (nonzero = thrusting); out: a = new velocity
Drag:
    and a
    ret z
    ld c, a                      ; c = vel (signed)
    bit 7, a
    jr z, .mag
    cpl
    inc a
.mag                             ; a = |vel|
    ld e, a
    ld a, [wMaxVel]
    cp 48                          ; swift sails fitted?
    ld a, e
    jr nz, .stdDrag
    REPT 6
    srl a
    ENDR                           ; a = |vel| / 64
    jr .dragSet
.stdDrag
    REPT 5
    srl a
    ENDR                           ; a = |vel| / 32
.dragSet
    jr nz, .haveMag
    ld a, b
    and a
    jr nz, .noDrag                 ; thrusting: skip the nudge
    ld a, 1
.haveMag                         ; a = drag magnitude (toward zero)
    bit 7, c
    jr z, .pos
    add c                          ; vel < 0: vel + mag
    ret
.pos
    ld b, a
    ld a, c
    sub b                          ; vel > 0: vel - mag
    ret
.noDrag
    ld a, c
    ret

; wShipX/Y = wPosX/Y >> 4
ComputeShipPx:
    ld a, [wPosX]
    ld l, a
    ld a, [wPosX+1]
    ld h, a
    SR16 h, l, 4
    ld a, l
    ld [wShipX], a
    ld a, h
    ld [wShipX+1], a
    ld a, [wPosY]
    ld l, a
    ld a, [wPosY+1]
    ld h, a
    SR16 h, l, 4
    ld a, l
    ld [wShipY], a
    ld a, h
    ld [wShipY+1], a
    ret

; Stop and revert if the ship's tile is land.
SailCollide:
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    SR16 h, l, 3
    ld c, l
    ld b, h                        ; bc = tx
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
    ld h, a
    SR16 h, l, 3
    ld e, l
    ld d, h                        ; de = ty
    push bc
    push de
    call WorldTile
    pop de
    pop bc
    cp TILE_SAND
    ret c                          ; water: keep sailing
    ; a port district's shore is a dock, not a rock (the same district
    ; hash that draws the dock planks): stop the ship, spare the hull
    SR16 b, c, 2
    ld b, c                        ; dx = tx / 4
    SR16 d, e, 2
    ld c, e                        ; dy = ty / 4
    call HasPortHash
    ld c, a                        ; survives the revert below (a-only)
    ld a, [wOldPosX]
    ld [wPosX], a
    ld a, [wOldPosX+1]
    ld [wPosX+1], a
    ld a, [wOldPosY]
    ld [wPosY], a
    ld a, [wOldPosY+1]
    ld [wPosY+1], a
    xor a
    ld [wVelX], a
    ld [wVelY], a
    call ComputeShipPx
    ld a, c
    and a
    ret nz                         ; docking bump: no damage
    ; hull damage (with cooldown)
    ld a, [wDmgCool]
    and a
    ret nz
    ld a, 45
    ld [wDmgCool], a
    ld a, 8
    ld [wShakeT], a                ; felt, not just heard
    ld a, 6
    ld [wHitFlashT], a
    ld a, [wHull]
    and a
    ret z
    dec a
    ld [wHull], a
    ld b, a
    ld a, SFX_HIT
    call PlaySfx
    ld a, b
    and a
    ret nz
    jp Wreck                       ; hull hit 0

; Shipwreck: lose half the gold, patch the hull, respawn in open water.
Wreck::
    ld a, [wGold+1]
    ld h, a
    ld a, [wGold]
    ld l, a
    srl h
    rr l
    ld a, h
    ld [wGold+1], a
    ld a, l
    ld [wGold], a
    ld a, 10
    ld [wHull], a
    xor a
    ld [wStormT], a                ; the storm spends itself on the wreck —
    ld [wStormT+1], a              ; else it sweeps the respawn into another
                                   ; wreck, over and over
    ; wreck message
    call ClearTextScreen
    ld hl, StrWreck
    ld de, $9800 + 8 * 32 + 5
    call PrintStr
    call ShowTextScreen
    ld a, JINGLE_WRECK
    call SetSong
    ld b, 90
.wait
    halt
    call UpdateSound               ; MainLoop is parked: tick music here
    dec b
    jr nz, .wait
    call FindSpawn
    ; the respawn is a discontinuous jump: re-derive ship px and camera so
    ; SailRedraw fills the window the screen will actually show. Without
    ; this the fill uses the pre-wreck camera, the camera then snaps to the
    ; spawn, and CheckStream only patches one edge per frame — the window
    ; shows stale pre-wreck tiles (land strips in open ocean) indefinitely.
    xor a
    ld [wVelX], a                ; a wrecked ship dead-stops (EnterSail parity)
    ld [wVelY], a
    call ComputeShipPx
    call SailCamera
    call SailRedraw
    ret

; Camera = ship - (80,72), clamped so streaming never leaves the world.
SailCamera:
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
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
    cp HIGH(SAIL_CAM_MAX_X)
    jr c, .storeX
    jr nz, .clampX
    ld a, l
    cp LOW(SAIL_CAM_MAX_X)
    jr c, .storeX
.clampX
    ld hl, SAIL_CAM_MAX_X
.storeX
    ld a, l
    ld [wCamX], a
    ld a, h
    ld [wCamX+1], a
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
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
    cp HIGH(SAIL_CAM_MAX_Y)
    jr c, .storeY
    jr nz, .clampY
    ld a, l
    cp LOW(SAIL_CAM_MAX_Y)
    jr c, .storeY
.clampY
    ld hl, SAIL_CAM_MAX_Y
.storeY
    ld a, l
    ld [wCamY], a
    ld a, h
    ld [wCamY+1], a
    ret

; Detect tile-boundary crossings and stage the entering row/column.
; (Generation here, in the logic phase; SailVBlank blits.)
CheckStream:
    ; --- X axis ---
    ld a, [wCamX]
    ld l, a
    ld a, [wCamX+1]
    ld h, a
    SR16 h, l, 3                ; hl = new tileX
    ld a, [wTileX]
    ld c, a
    ld a, [wTileX+1]
    ld b, a                        ; bc = old tileX
    ld a, l
    cp c
    jr nz, .xDiff
    ld a, h
    cp b
    jr z, .xDone
.xDiff
    ld a, l
    ld [wTileX], a
    ld a, h
    ld [wTileX+1], a
    ld a, h
    cp b
    jr c, .left
    jr nz, .right
    ld a, l
    cp c
    jr c, .left
.right
    ld a, [wTileX]
    add 20
    ld e, a
    ld a, [wTileX+1]
    adc 0
    ld d, a
    call GenColStage
    jr .markCol
.left
    ld a, [wTileX]
    ld e, a
    ld a, [wTileX+1]
    ld d, a
    call GenColStage
.markCol
    ld a, [wStagePend]
    or 1
    ld [wStagePend], a
.xDone
    ; --- Y axis ---
    ld a, [wCamY]
    ld l, a
    ld a, [wCamY+1]
    ld h, a
    SR16 h, l, 3
    ld a, [wTileY]
    ld c, a
    ld a, [wTileY+1]
    ld b, a
    ld a, l
    cp c
    jr nz, .yDiff
    ld a, h
    cp b
    ret z
.yDiff
    ld a, l
    ld [wTileY], a
    ld a, h
    ld [wTileY+1], a
    ld a, h
    cp b
    jr c, .up
    jr nz, .down
    ld a, l
    cp c
    jr c, .up
.down
    ld a, [wTileY]
    add 18
    ld e, a
    ld a, [wTileY+1]
    adc 0
    ld d, a
    call GenRowStage
    jr .markRow
.up
    ld a, [wTileY]
    ld e, a
    ld a, [wTileY+1]
    ld d, a
    call GenRowStage
.markRow
    ld a, [wStagePend]
    or 2
    ld [wStagePend], a
    ret

; Ship sprite into shadow OAM (entry 0).
SailSprite:
    ld a, [wShipX]
    ld hl, wCamX
    sub [hl]                       ; low-byte diff is exact (<256 apart)
    add 4                          ; +8 OAM offset, -4 to center 8px sprite
    ld b, a
    ld a, [wShipY]
    ld hl, wCamY
    sub [hl]
    add 12                         ; +16 OAM offset, -4 centering
    ld c, a
    ld a, [wHeading]
    add TILE_SHIP_N
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
    ret

; HUD digits: TX (3 hex), TY (3 hex), speed = |vx|+|vy| (2 hex)
SailHud:
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    SR16 h, l, 3
    ld de, wHudDigits
    call WriteHexTriple
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
    ld h, a
    SR16 h, l, 3
    call WriteHexTriple
    ld a, [wVelX]
    call AbsA
    ld b, a
    ld a, [wVelY]
    call AbsA
    add b
    call WriteHexPair
    ; --- window row 1: quit-confirm message or HULL/GOLD/FRAG stats ---
    ld a, [wQuitCfm]
    and a
    jr z, .stats
    ld hl, StrQuitCfm
    ld de, wHudRow1
    ld b, 15
.cfm
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .cfm
    ret
.stats
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
    push de
    call CountFrags                  ; clobbers d!
    pop de
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

AbsA::
    bit 7, a
    ret z
    cpl
    inc a
    ret

; in: hl = value (12 bits shown), de = dest (3 bytes, advanced)
WriteHexTriple:
    ld a, h
    and $0F
    add TILE_HEX0
    ld [de], a
    inc de
    ld a, l
    swap a
    and $0F
    add TILE_HEX0
    ld [de], a
    inc de
    ld a, l
    and $0F
    add TILE_HEX0
    ld [de], a
    inc de
    ret

; in: a = value, de = dest (2 bytes, advanced)
WriteHexPair:
    ld b, a
    swap a
    and $0F
    add TILE_HEX0
    ld [de], a
    inc de
    ld a, b
    and $0F
    add TILE_HEX0
    ld [de], a
    inc de
    ret

SECTION "Sail strings", ROMX, BANK[3]
StrWreck:   db "SHIPWRECK!", 0
StrQuitCfm: db "B AGAIN TO QUIT"    ; exactly 15 chars, no terminator

; PIRATE'S FOLLY — M0 generator demo
; Seed editor (d-pad edits 8 hex digits, A generates) → island view
; (A = random new seed, B = back to editor).

INCLUDE "hardware.inc"
INCLUDE "defs.inc"
INCLUDE "text.inc"

SECTION "Reset vector", ROM0[$0000]
    jp EntryPoint               ; for emulators that skip the boot ROM

SECTION "VBlank vector", ROM0[$0040]
    jp VBlankHandler

SECTION "Header", ROM0[$0100]
    nop
    jp EntryPoint
    ds $0146 - @, 0             ; rgbfix -v fills the logo and checksums
    db $03                      ; $0146: SGB flag — unlock SGB functions
    ds $014B - @, 0
    db $33                      ; $014B: old licensee $33 — required for SGB
    ds $0150 - @, 0

SECTION "Shared WRAM", WRAM0
wVBlankFlag::   db
wFrameCounter:: db
wState::        db
wCursor::       db
wRepCtr::       db
wRepEff::       db
wJoyHeld::      db
wJoyNew::       db
wSeed::         ds 4           ; nibbles n0..n7, big-endian pairs
wSeedNib::      ds 8
wSeed16::      dw             ; seed folded to 16 bits for the generator
wRngState::    dw
wIsCGB::       db             ; $11 = CGB/AGB (boot ROM leaves it in a)
wIsSGB::       db             ; $14 = SGB/SGB2 (boot ROM leaves it in c)

SECTION "Main", ROM0[$0150]
EntryPoint:
    di
    ld b, a                      ; stash boot ROM's hardware id
    ld a, 3
    ld [$2000], a                ; data bank (tiles/sound/text) at $4000 —
                                 ; ComputeIsles below already reads it.
                                 ; Invariant: bank 3 stays mapped except
                                 ; inside SGBTransferBorder, which ends in
                                 ; LoadTiles and thereby restores it.
    ld a, b
    ld [wIsCGB], a               ; boot ROM: $11 on CGB/AGB, $01 on DMG
    ld a, c
    ld [wIsSGB], a               ; boot ROM: $14 on SGB/SGB2, $13 on DMG/MGB
    ld sp, $E000

.waitVb                          ; LCD is on after boot ROM; find VBlank
    ldh a, [rLY]
    cp 144
    jr c, .waitVb
    xor a
    ldh [rLCDC], a               ; LCD off (safe: in VBlank)

    ; try to load a saved game BEFORE drawing: hint text depends on it
    call LoadGame
    ld a, [wHasSave]
    and a
    jr z, .noSave
    call SplitSeedNibbles        ; show the loaded seed in the editor
    call ComputeIsles            ; isles are derived, never saved
    jr .saveDone
.noSave
    xor a                        ; fresh cart: no best haul, no chart bounty
    ld [wBestGold], a
    ld [wBestGold+1], a
    ld [wCartDone], a
    ld [wSaveSlot], a
    ld [wSaveSeq], a
.saveDone

    ; power-on WRAM is random on hardware (PyBoy zeroes it, emulators like
    ; binjgb do not): clear volatile combat/storm state so no phantom
    ; storm, enemy, or cannonball is already "active" on the first frame
    xor a
    ld [wStormT], a
    ld [wStormT+1], a
    ld [wStormDX], a
    ld [wStormDY], a
    ld [wStormDmgT], a
    ld [wEnemyActive], a
    ld [wBallPActive], a
    ld [wBallEActive], a
    ld [wFireCool], a
    ld [wEnemyFireCool], a
    ld [wEnemyFlash], a
    ld [wSinkT], a
    ld [wSplashT], a
    ld [wSmokeT], a
    ld [wCursor], a
    ld [wMerchActive], a           ; a merchant is per-voyage, never saved
    ld [wMerchT], a
    ld [wMerchT+1], a
    ld [wMerchHailed], a
    ld [wEscortPend], a
    ld [wMuted], a
    ld [wPriceDrift], a
    ld a, PIRATE_FIRECOOL          ; sane default for hand-placed enemies
    ld [wEnemyFireRate], a
    ld a, 25
    ld [wEnemyLoot], a
    ld a, $FF                    ; MarkExplored tile cache: invalid
    ld [wMarkTX], a
    ld [wMarkTX+1], a
    ld [wMarkTY], a
    ld [wMarkTY+1], a
    ld [wShipCX], a              ; cell cache invalid too: the first
    ld [wShipCY], a              ; MarkExplored always counts as a cell entry

    call SoundInit
    call LoadTiles
    call CGBInit                 ; palettes + attrmaps (no-op on DMG)
    call DrawTitleScreen
    ld a, SONG_TITLE
    call SetSong
    ld a, STATE_TITLE
    ld [wState], a               ; boot into the title, not the editor

    ; copy the OAM DMA routine into HRAM
    ld hl, RunDmaROM
    ld de, hOamDma
    ld b, RunDmaROM.end - RunDmaROM
.dmaCopy
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .dmaCopy

    ; clear shadow OAM (all 40 objects hidden)
    ld hl, wShadowOAM
    ld b, 160
    xor a
.oamClr
    ld [hli], a
    dec b
    jr nz, .oamClr

    ld a, %11100100              ; canonical BGP: 3=black ... 0=white
    ldh [rBGP], a
    ldh [rOBP0], a               ; player objects: same
    ld a, %11111000              ; pirate objects: dark hull
    ldh [rOBP1], a

    ; default seed DEADBEEF (a loaded save keeps its own seed in the editor)
    ld a, [wHasSave]
    and a
    jr nz, .seedDone
    ld hl, DefaultSeedNibs
    ld de, wSeedNib
    ld b, 8
.copySeed
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .copySeed
.seedDone

    ; init runtime RNG from DIV jitter; must be nonzero for xorshift
    ldh a, [rDIV]
    ld h, a
    ldh a, [rDIV]
    xor $5A
    ld l, a
    or h
    jr nz, .rngOk
    ld l, $39
.rngOk
    ld a, h
    ld [wRngState], a
    ld a, l
    ld [wRngState+1], a

    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    ; SGB: give the title screen the saved voyage's border, if there is one
    ; (no save: the seed isn't final until the editor, so EnterSail does it)
    ld a, [wHasSave]
    and a
    jr z, .noBorder
    call SGBTransferBorder
    and a
    jr z, .noBorder
    call DrawTitleScreen         ; redraw what the transfer trashed (LCD off)
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    call SGBUnfreeze
.noBorder
    xor a
    ldh [rIF], a
    ld a, IE_VBLANK
    ldh [rIE], a
    ei

MainLoop:
    halt                         ; only VBlank is enabled: wakes once/frame
    ld a, [wVBlankFlag]
    and a
    jr z, MainLoop
    xor a
    ld [wVBlankFlag], a
    ld hl, wFrameCounter
    inc [hl]
    ; SELECT toggles sound everywhere but the seed editor (there it
    ; re-rolls the seed). Uses last frame's edges: ReadJoypad runs later.
    ld a, [wState]
    and a                          ; STATE_EDIT
    jr z, .noMute
    ld a, [wJoyNew]
    and PADF_SELECT
    call nz, ToggleMute
.noMute
    call UpdateSound
    ld a, [wState]
    cp STATE_TITLE
    jr z, .title
    cp STATE_SAIL
    jr z, .sail
    cp STATE_CHART
    jr z, .chart
    cp STATE_PORT
    jr z, .port
    cp STATE_DIG
    jr z, .dig
    cp STATE_MERCH
    jr z, .merch
    cp STATE_WIN
    jr z, .win
    call ReadJoypad
    call ComputeRepeat
    call UpdateEdit
    jr MainLoop
.sail
    call SailVBlank              ; time-critical: runs inside VBlank
    call ReadJoypad
    call UpdateSail
    jr MainLoop
.chart
    call ReadJoypad
    call UpdateChart
    jr MainLoop
.port
    call ReadJoypad
    call UpdatePort
    jr MainLoop
.dig
    call ReadJoypad
    call UpdateDig
    jr MainLoop
.merch
    call ReadJoypad
    call UpdateMerch
    jr MainLoop
.win
    call ReadJoypad
    call UpdateWin
    jr MainLoop
.title
    call ReadJoypad
    call UpdateTitle
    jp MainLoop                  ; .merch grew the loop past jr range

VBlankHandler:
    push af
    ld a, 1
    ld [wVBlankFlag], a
    pop af
    reti

; ---------------------------------------------------------------------------
; Seed editor state
; ---------------------------------------------------------------------------
SECTION "Main UI", ROMX, BANK[3]
UpdateEdit:
    ; LEFT/RIGHT move the digit cursor
    ld a, [wRepEff]
    ld c, a                      ; repeated-direction bits for all four tests
    and PADF_RIGHT
    jr z, .notRight
    ld a, [wCursor]
    inc a
    and 7
    ld [wCursor], a
.notRight
    ld a, c
    and PADF_LEFT
    jr z, .notLeft
    ld a, [wCursor]
    dec a
    and 7
    ld [wCursor], a
.notLeft
    ; UP/DOWN change the selected nibble
    ld a, c
    and PADF_UP
    jr z, .notUp
    call GetNibblePtr
    ld a, [hl]
    inc a
    and $0F
    ld [hl], a
.notUp
    ld a, c
    and PADF_DOWN
    jr z, .notDown
    call GetNibblePtr
    ld a, [hl]
    dec a
    and $0F
    ld [hl], a
.notDown
    ; A = new game, START = continue loaded game
    ld a, [wJoyNew]
    and PADF_START
    jr z, .notStart
    ld a, [wHasSave]
    and a
    jr z, .notStart
    call EnterSail               ; continue (vars already loaded)
    ld a, STATE_SAIL
    ld [wState], a
    ret
.notStart
    ld a, [wJoyNew]
    and PADF_A
    jr z, .notNewGame
    call ComposeSeed
    call FoldSeed16
    call InitNewGame
    call EnterSail
    ld a, STATE_SAIL
    ld [wState], a
    ret
.notNewGame
    ld a, [wJoyNew]
    and PADF_SELECT
    jr z, .render
    ; SELECT: roll a fresh random seed into the editor
    ld de, wSeedNib
    ld b, 4
.reroll
    push de                        ; Rand16 clobbers d, e
    call Rand16
    pop de
    ld a, h
    and $0F
    ld [de], a
    inc de
    ld a, l
    and $0F
    ld [de], a
    inc de
    dec b
    jr nz, .reroll
.render
    call RenderSeedRow
    ret

; hl = wSeedNib + cursor
GetNibblePtr:
    ld a, [wCursor]
    ld l, a
    ld h, 0
    ld de, wSeedNib
    add hl, de
    ret

; wSeedNib (8 nibbles) -> wSeed (4 bytes)
ComposeSeed:
    ld hl, wSeedNib
    ld de, wSeed
    ld b, 4
.loop
    ld a, [hli]
    swap a                       ; n -> n<<4
    or [hl]
    inc hl
    ld [de], a
    inc de
    dec b
    jr nz, .loop
    ret

; wSeed16 = Mix16(b0:b1) + Mix16(b2:b3). A plain XOR fold collapses every
; repeated-pattern seed (00000000 = FFFFFFFF = AAAAAAAA = ...) to $0000.
FoldSeed16::
    ld a, [wSeed]
    ld h, a
    ld a, [wSeed+1]
    ld l, a
    call Mix16
    push hl
    ld a, [wSeed+2]
    ld h, a
    ld a, [wSeed+3]
    ld l, a
    call Mix16
    pop de
    add hl, de
    ld a, h
    ld [wSeed16], a
    ld a, l
    ld [wSeed16+1], a
    ret

; Draws digits (tilemap row 2) + blinking cursor (row 3). VBlank or LCD-off only.
RenderSeedRow::
    ld hl, wSeedNib
    ld de, $9800 + 2 * 32 + 6
    ld b, 8
.digitLoop
    ld a, [hli]
    add TILE_HEX0
    ld [de], a
    inc de
    dec b
    jr nz, .digitLoop
    ld a, [wFrameCounter]
    and %00010000                ; blink at ~2 Hz
    ld c, a
    ld de, $9800 + 3 * 32 + 6
    ld b, 0                      ; column index
.cursorLoop
    ld a, [wCursor]
    cp b
    jr nz, .blank
    ld a, c
    and a
    jr z, .blank
    ld a, TILE_CURSOR
    jr .store
.blank
    ld a, TILE_BLANK
.store
    ld [de], a
    inc de
    inc b
    ld a, b
    cp 8
    jr nz, .cursorLoop
    ret

; ---------------------------------------------------------------------------
; Screen helpers
; ---------------------------------------------------------------------------

; Poll for the START of VBlank. LCD must be on. ROM0: SGBTransferBorder
; calls this while banks 1/2 (border art) are mapped.
PUSHS "Main low", ROM0
WaitVBlankPoll::
.waitOut
    ldh a, [rLY]
    cp 144
    jr nc, .waitOut
.waitIn
    ldh a, [rLY]
    cp 144
    jr c, .waitIn
    ret
POPS

; Wait for VBlank, then LCD off. clobbers a
LcdOff::
    call WaitVBlankPoll
    xor a
    ldh [rLCDC], a
    ret

; LcdOff + scroll home + canonical BGP (UI screens are unscrolled)
LcdOffHome::
    call LcdOff
    xor a
    ldh [rSCX], a
    ldh [rSCY], a
    ld a, $E4
    ldh [rBGP], a
    ret

; Fill the whole BG map with TILE_BLANK. LCD must be off.
; On CGB also clears the attribute bank (text screens use palette 0).
DrawSeedScreen::
    xor a
    ld hl, $9800
    ld bc, 1024                  ; b = 4 pages, c wraps 256..1
.loop
    ld [hli], a
    dec c
    jr nz, .loop
    dec b
    jr nz, .loop
    ld a, [wIsCGB]
    cp $11                      ; not CGB: single VRAM bank, no attrs
    ret nz
    ld a, 1
    ldh [rVBK], a
    xor a
    ld hl, $9800
    ld bc, 1024
.aloop
    ld [hli], a
    dec c
    jr nz, .aloop
    dec b
    jr nz, .aloop
    xor a
    ldh [rVBK], a
    ret

; Editor-only continue hint (when a save exists). LCD off or VBlank.
DrawSeedHints::
    ld a, [wHasSave]
    and a
    ret z
    ld hl, StrNewGame
    ld de, $9800 + 5 * 32 + 5
    call PrintStr
    ld hl, StrLoadGame
    ld de, $9800 + 6 * 32 + 5
    call PrintStr
    ld a, [wWon]
    and a
    jr z, .noTag
    ld hl, StrWonTag
    ld de, $9800 + 7 * 32 + 5
    call PrintStr
.noTag
    ld hl, StrBest
    ld de, $9800 + 8 * 32 + 5
    call PrintStr
    ld a, [wBestGold+1]
    ld h, a
    ld a, [wBestGold]
    ld l, a
    ld de, $9800 + 8 * 32 + 10
    call PrintDec4
    ld a, TILE_SPACE
    ld [de], a
    inc de
    ld a, TILE_A + 6                 ; 'G'
    ld [de], a
    ret

; LCD-off redraw of the editor screen, LCD back on.
ShowSeedScreen::
    call LcdOffHome
    call DrawSeedScreen
    call DrawSeedHints
    call RenderSeedRow
    ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
    ldh [rLCDC], a
    ret

; wSeed (4 bytes) -> wSeedNib (8 nibbles)
SplitSeedNibbles:
    ld hl, wSeed
    ld de, wSeedNib
    ld b, 4
.loop
    ld a, [hl]
    swap a
    and $0F
    ld [de], a
    inc de
    ld a, [hli]
    and $0F
    ld [de], a
    inc de
    dec b
    jr nz, .loop
    ret

; Fresh game state (new game from the editor).
InitNewGame:
    ld a, LOW(GOLD_START)
    ld [wGold], a
    ld a, HIGH(GOLD_START)
    ld [wGold+1], a
    ld a, HULL_MAX
    ld [wHull], a
    ld [wHullMax], a               ; fresh ship: no shipyard upgrades
    ld a, SAIL_MAX_VEL
    ld [wMaxVel], a
    ld a, 40
    ld [wBallLife], a
    ld a, 5
    ld [wCrew], a
    xor a
    ld [wCargo], a
    ld [wCargo+1], a
    ld [wCargo+2], a
    ld [wCargo+3], a
    ld [wLastPortDX], a
    ld [wLastPortDY], a
    ld [wFragMask], a
    ld [wFragMask+1], a
    ld [wGuardMask], a
    ld [wGuardMask+1], a
    ld [wFinal], a
    ld [wWon], a
    ld [wIsGuardian], a
    ld [wCartDone], a            ; bounty is per-voyage (wBestGold persists)
    ld [wPriceDrift], a
    ld [wMerchActive], a         ; a fresh sea: no leftover encounters
    ld [wMerchT], a
    ld [wMerchT+1], a
    ld [wMerchHailed], a
    ld [wEscortPend], a
    ld [wStormT], a              ; a storm/enemy from a B-quit voyage must
    ld [wStormT+1], a            ; not follow the player into the new one
    ld [wStormDX], a
    ld [wStormDY], a
    ld [wStormDmgT], a
    ld [wEnemyActive], a
    ld [wBallPActive], a
    ld [wBallEActive], a
    ld [wFireCool], a
    ld [wEnemyFireCool], a
    ld [wEnemyFlash], a
    ld [wSinkT], a
    ld [wSplashT], a
    ld [wSmokeT], a
    ld hl, wExplored             ; + wPortCells (contiguous, 64 B total)
    ld b, 64
.clr
    ld [hli], a
    dec b
    jr nz, .clr
    ld a, PIRATE_FIRECOOL          ; sane default for hand-placed enemies
    ld [wEnemyFireRate], a         ; (AFTER .clr: the loop stores a)
    ld a, 25
    ld [wEnemyLoot], a
    ld a, 1
    ld [wNeedSpawn], a           ; pick a fresh spawn
    call ComputeIsles
    ret

; ---------------------------------------------------------------------------
; Title screen (M6)
; ---------------------------------------------------------------------------

; LCD-off draw of the title. Sea rows + a ship, then text.
DrawTitleScreen::
    call DrawSeedScreen            ; clear to blank (LCD off)
    ; two sea rows at the bottom
    ld hl, $9800 + 14 * 32
    ld b, 64
.sea
    ld a, TILE_DEEP
    ld [hli], a
    dec b
    jr nz, .sea
    ; a lone ship on the horizon
    ld a, TILE_SHIP_S
    ld [$9800 + 13 * 32 + 9], a
    ld hl, StrTitle
    ld de, $9800 + 4 * 32 + 3
    call PrintStr
    ld hl, StrTitleSub1
    ld de, $9800 + 6 * 32 + 4
    call PrintStr
    ld hl, StrTitleSub2
    ld de, $9800 + 7 * 32 + 3
    call PrintStr
    ld hl, StrTitleSub3
    ld de, $9800 + 9 * 32 + 2
    call PrintStr
    ld hl, StrPressStart
    ld de, $9800 + 12 * 32 + 4
    call PrintStr
    ret

; Any A/START press -> seed editor.
UpdateTitle::
    ld a, [wJoyNew]
    and PADF_A | PADF_START
    ret z
    call ShowSeedScreen
    xor a
    ld [wState], a                 ; STATE_EDIT
    ret

SECTION "Default data", ROMX, BANK[3]
DefaultSeedNibs:
    db $D, $E, $A, $D, $B, $E, $E, $F
StrNewGame:  db "A  NEW GAME", 0
StrLoadGame: db "START LOAD", 0
StrWonTag:   db "TREASURE WON!", 0
StrBest:     db "BEST ", 0
StrTitle:    db "PIRATES FOLLY", 0
StrTitleSub1: db "A PROCEDURAL", 0
StrTitleSub2: db "PIRATE VOYAGE", 0
StrTitleSub3: db "65536 SEAS AWAIT", 0
StrPressStart: db "PRESS START", 0

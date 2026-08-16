; Combat & hazards: pirate encounters, broadside cannonballs, storms.
; Sprites: OAM 0 = player, 1 = enemy, 2 = player ball, 3 = enemy ball.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"

SECTION "Combat WRAM", WRAM0
wEnemyActive::  db
wEnemyX:        dw              ; 12.4 fixed point
wEnemyY:        dw
wEnemyHP::      db
wEnemyFireCool:: db
wEnemyFireRate:: db             ; per-enemy refire rate (scaled at spawn)
wFireCool::     db
wBallPActive::  db
wBallPX:        dw
wBallPY:        dw
wBallPVX:       db              ; signed 1/16 px/frame
wBallPVY:       db
wBallPLife:     db
wBallEActive::  db
wBallEX:        dw
wBallEY:        dw
wBallEVX:       db
wBallEVY:       db
wBallELife:     db
wStormT::       dw              ; storm frames remaining
wStormDX::      db
wStormDY::      db
wStormDmgT::    db
wEvX:           db              ; enemy move temps
wEvY:           db
wEvC:           db              ; enemy chebyshev range (fire control)
wLoX0:          db              ; LOS sampling: enemy tile
wLoY0:          db
wLoDX:          dw              ; LOS sampling: signed tile deltas
wLoDY:          dw
wLoI:           db              ; LOS sampling: sample index
wLosT:          db              ; frames until next LOS check
wNoLOS:         db              ; consecutive failed LOS checks
; --- combat juice: these four timers MUST stay contiguous (fx tick loop) ---
wEnemyFlash::   db              ; enemy hit-flash frames (blink)
wSinkT::        db              ; sinking-animation frames
wSplashT::      db              ; ball splash frames
wSmokeT::       db              ; muzzle-smoke frames
wSinkX:         dw              ; world px of the sinking ship
wSinkY:         dw
wSplashX:       dw              ; world px of the splash
wSplashY:       dw
wSmokeX:        dw              ; world px of the smoke puff
wSmokeY:        dw
wFxX:           dw              ; render scratch (sink slide offset)
wFxY:           dw
wMerchActive::  db
wMerchX:        dw              ; 12.4 fixed point
wMerchY:        dw
wMerchT::       dw              ; despawn timer
wMerchHailed::  db              ; 1 = the offer was already made
wEscortPend::   db              ; 1 = a robbed merchant's escort still seeks water

SECTION "Combat", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; Encounter rolls (called when a cell is newly explored)
; ---------------------------------------------------------------------------
SpawnCheck::
    ld a, [wEnemyActive]
    and a
    ret nz                       ; one enemy at a time
    ld a, [wMerchActive]
    and a
    ret nz                       ; and one merchant at a time
    ld a, [wShipCX]
    ld b, a
    ld a, [wShipCY]
    ld c, a
    call IsIsleCell
    cp $FF
    ret nz                       ; isle waters are guardian territory: no rolls
    ld a, [wShipCX]
    ld b, 73
    call Mul8
    push hl
    ld a, [wShipCY]
    ld b, 41
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
    xor $C3                      ; encounter salt
    ld h, a
    ld a, l
    xor $7A
    ld l, a
    call Mix16
    push hl
    ld a, l
    cp 48                          ; pirate ~19%
    call c, SpawnEnemy
    pop hl
    push hl
    ld a, l
    sub 48                         ; merchant lane 48..67 (~8%)
    cp 20
    call c, SpawnMerchant
    pop hl
    ld a, h
    cp 13                          ; storm ~5%
    call c, StartStorm
    ret

; Re-entry roll for an already-charted cell: reduced odds (~1/4 of the
; new-cell rates), drawn from the stateful RNG — the cell hash is constant
; per cell, so hash-based re-rolls would be deterministic (a cell that
; either always or never spawns).
RevisitRoll::
    ld a, [wEnemyActive]
    and a
    ret nz
    ld a, [wMerchActive]
    and a
    ret nz                       ; one enemy at a time
    ld a, [wShipCX]
    ld b, a
    ld a, [wShipCY]
    ld c, a
    call IsIsleCell
    cp $FF
    ret nz                       ; isle waters are guardian territory: no rolls
    ld a, [wWon]
    and a
    jr z, .calm
    ld c, 48                         ; the Treasure's curse: a won sea stays
    ld b, 13                         ; as wild as uncharted water
    jr .roll
.calm
    ld c, 12                         ; pirate ~4.7%
    ld b, 3                          ; storm ~1.2%
.roll
    call Rand16
    push hl
    ld a, l
    cp c                           ; pirate
    call c, SpawnEnemy
    pop hl
    push hl
    ld a, l
    sub c
    cp 20                          ; merchant lane: 20 values above the pirates'
    call c, SpawnMerchant
    pop hl
    ld a, h
    cp b                           ; storm
    call c, StartStorm
    ret

; Spawn a pirate ship near the player, in open water. 8 candidate offsets:
; far ring first, near ring second (guardians near big islands need options;
; callers retry on later frames when the pick lands on land).
PUSHS "Spawn offset table", ROMX, BANK[3]
SPAWN_OFF: db 100, 0, 0, 100, -100, 0, 0, -100   ; E S W N
           db  60, 0, 0, 60,  -60, 0, 0,  -60    ; near E S W N
POPS

; Pick a water spawn spot on the ring around the ship. 8 candidate
; offsets: far ring first, near ring second (guardians near big islands
; need options; callers retry on later frames when the pick lands on land).
; out: carry set + de = ex, hl = ey (world px) on success; carry clear on land.
; clobbers all.
PickSpawnSpot:
    call Rand16
    and 7
    add a
    ld e, a
    ld d, 0
    ld hl, SPAWN_OFF
    add hl, de
    ld a, [hli]
    ld b, a                        ; dx (signed)
    ld c, [hl]                     ; dy (signed)
    ; ex = shipPx + dx (sign-extended 16-bit add)
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    ld e, b
    ld d, 0
    bit 7, b
    jr z, .p1
    dec d
.p1
    ld a, l
    add e
    ld l, a
    ld a, h
    adc d
    ld h, a
    push hl                        ; ex
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
    ld h, a
    ld e, c
    ld d, 0
    bit 7, c
    jr z, .p2
    dec d
.p2
    ld a, l
    add e
    ld l, a
    ld a, h
    adc d
    ld h, a                        ; ey
    pop de                         ; de = ex, hl = ey
    ; clamp ex to [16, WORLD_W*8-16]
    bit 7, d
    jr z, .xPos
    ld de, 16
    jr .xDone
.xPos
    ld a, d
    cp HIGH(WORLD_W * 8 - 16)
    jr c, .xDone
    jr nz, .xClamp
    ld a, e
    cp LOW(WORLD_W * 8 - 16)
    jr c, .xDone
.xClamp
    ld de, WORLD_W * 8 - 16
.xDone
    ; clamp ey to [16, WORLD_H*8-16]
    bit 7, h
    jr z, .yPos
    ld hl, 16
    jr .yDone
.yPos
    ld a, h
    cp HIGH(WORLD_H * 8 - 16)
    jr c, .yDone
    jr nz, .yClamp
    ld a, l
    cp LOW(WORLD_H * 8 - 16)
    jr c, .yDone
.yClamp
    ld hl, WORLD_H * 8 - 16
.yDone
    ; water check: WorldTile(ex>>3, ey>>3)
    push de
    push hl
    ld b, d
    ld c, e
    REPT 3
    srl b
    rr c
    ENDR                           ; bc = tx
    ld d, h
    ld e, l
    REPT 3
    srl d
    rr e
    ENDR                           ; de = ty
    call WorldTile
    pop hl
    pop de
    cp TILE_SAND
    jr nc, .land
    scf
    ret
.land
    and a                          ; carry clear: the pick was land
    ret

; Spawn a pirate ship near the player, in open water.
SpawnEnemy::
    call PickSpawnSpot
    ret nc                         ; land: abort spawn
    ; activate
    ld a, 1
    ld [wEnemyActive], a
    xor a
    ld [wIsGuardian], a            ; normal pirate, not a guardian
    ld [wNoLOS], a
    ld a, 16
    ld [wLosT], a
    ; wEnemyY = ey << 4 (ey in hl)
    REPT 4
    add hl, hl
    ENDR
    ld a, l
    ld [wEnemyY], a
    ld a, h
    ld [wEnemyY+1], a
    ; wEnemyX = ex << 4 (ex in de)
    ld l, e
    ld h, d
    REPT 4
    add hl, hl
    ENDR
    ld a, l
    ld [wEnemyX], a
    ld a, h
    ld [wEnemyX+1], a
    ; the seas grow bolder as the chart assembles: +1 HP at 3 and 6
    ; fragments, volleys 5 frames quicker per fragment. Guardians get
    ; their own stats: SpawnGuardian overrides both right after this.
    call CountFrags                ; a = fragments (0..9); clobbers c, d, h, l
    ld b, a
    ld a, PIRATE_HP
    ld c, a
    ld a, b
    cp 3
    jr c, .hpSet
    inc c
    cp 6
    jr c, .hpSet
    inc c
.hpSet
    ld a, c
    ld [wEnemyHP], a
    ld a, b
    add a
    add a
    add b                          ; 5 * fragments
    ld b, a
    ld a, PIRATE_FIRECOOL
    sub b                          ; >= 30 even at 9 fragments
    ld [wEnemyFireCool], a
    ld [wEnemyFireRate], a
    ret

; A merchant sail on the ring: becalmed, hails once, leaves after ~15 s.
SpawnMerchant::
    ld a, [wMerchActive]
    and a
    ret nz
    call PickSpawnSpot
    ret nc
    ld a, 1
    ld [wMerchActive], a
    xor a
    ld [wMerchHailed], a
    ld a, LOW(900)
    ld [wMerchT], a
    ld a, HIGH(900)
    ld [wMerchT+1], a
    ; wMerchY = ey << 4 (ey in hl)
    REPT 4
    add hl, hl
    ENDR
    ld a, l
    ld [wMerchY], a
    ld a, h
    ld [wMerchY+1], a
    ; wMerchX = ex << 4 (ex in de)
    ld l, e
    ld h, d
    REPT 4
    add hl, hl
    ENDR
    ld a, l
    ld [wMerchX], a
    ld a, h
    ld [wMerchX+1], a
    ret

; out: a = rough pixel range to the merchant (255 if either axis >= 256).
; clobbers a, b, c, d, e, h, l
MerchRange:
    ld a, [wMerchX]
    ld l, a
    ld a, [wMerchX+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR                           ; hl = merch px X
    ld a, [wShipX]
    ld c, a
    ld a, [wShipX+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call AbsHL                     ; |dx|
    push hl
    ld a, [wMerchY]
    ld l, a
    ld a, [wMerchY+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, [wShipY]
    ld c, a
    ld a, [wShipY+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call AbsHL                     ; |dy|
    pop de                         ; de = |dx|
    ld a, d
    or h
    jr nz, .far
    ld a, e
    cp l
    jr nc, .max
    ld a, l
.max
    ret
.far
    ld a, 255
    ret

; Per-frame merchant: despawn on timeout or distance; hail once when the
; player sails close. Called from UpdateCombat (sailing only).
UpdateMerchant:
    ld a, [wMerchActive]
    and a
    ret z
    ld a, [wMerchT]
    ld l, a
    ld a, [wMerchT+1]
    ld h, a
    dec hl
    ld a, l
    ld [wMerchT], a
    ld a, h
    ld [wMerchT+1], a
    or l
    jr z, .gone
    call MerchRange
    cp 141
    jr nc, .gone                   ; left behind
    ld a, [wMerchHailed]
    and a
    ret nz                         ; he made his offer already
    call MerchRange
    cp 20
    ret nc
    ld a, 1
    ld [wMerchHailed], a
    call MerchScene
    ret
.gone
    xor a
    ld [wMerchActive], a
    ld [wShadowOAM + 24], a
    ret

; ---------------------------------------------------------------------------
; Storm
; ---------------------------------------------------------------------------
StartStorm:
    ld hl, 480
    ld a, l
    ld [wStormT], a
    ld a, h
    ld [wStormT+1], a
    ; drift -32..31 (1/16 px/frame): strong enough to ride as a fast but
    ; dangerous current — risk/reward, not pure punishment
    call Rand16
    and $3F
    sub 32
    ld [wStormDX], a
    call Rand16
    and $3F
    sub 32
    ld [wStormDY], a
    ld a, 60
    ld [wStormDmgT], a
    ld a, SFX_STORM
    call PlaySfx
    ret

StormTick::
    ld a, [wStormT]
    ld l, a
    ld a, [wStormT+1]
    ld h, a
    or l
    ret z                          ; no storm
    dec hl
    ld a, l
    ld [wStormT], a
    ld a, h
    ld [wStormT+1], a
    ld a, [wStormDX]
    ld hl, wPosX
    call AddSignedToPos
    ld a, [wStormDY]
    ld hl, wPosY
    call AddSignedToPos
    ld a, [wStormDmgT]
    dec a
    ld [wStormDmgT], a
    ret nz
    ld a, 120
    ld [wStormDmgT], a
    ld a, [wJoyHeld]
    and DIR_MASK
    ret nz                         ; actively steering: no damage
    ld a, [wDmgCool]
    and a
    ret nz
    ld a, [wHull]
    and a
    ret z
    dec a
    ld [wHull], a
    ld a, 8
    ld [wShakeT], a
    ld a, 6
    ld [wHitFlashT], a
    ld a, [wHull]
    and a
    ret nz
    ld a, 20
    ld [wDmgCool], a
    jp Wreck

; 16-bit value at hl += sign-extend(a). clobbers a, d, e, hl
AddSignedToPos:
    ld e, a
    ld d, 0
    bit 7, a
    jr z, .p
    dec d
.p
    ld a, [hl]
    add e
    ld [hli], a
    ld a, [hl]
    adc d
    ld [hl], a
    ret

; ---------------------------------------------------------------------------
; Direction helpers
; ---------------------------------------------------------------------------

; in: b = dx, c = dy (signed bytes); out: a = 0..7 (N,NE,E,SE,S,SW,W,NW)
SnapDir::
    ld a, b
    call AbsA
    ld e, a
    ld a, c
    call AbsA
    ld d, a
    ld a, d
    add a
    cp e
    jr c, .ew                      ; 2|dy| < |dx|
    ld a, e
    add a
    cp d
    jr c, .ns                      ; 2|dx| < |dy|
    bit 7, c
    jr nz, .dn
    bit 7, b
    jr nz, .sw
    ld a, 3                        ; SE
    ret
.sw
    ld a, 5
    ret
.dn
    bit 7, b
    jr nz, .nw
    ld a, 1                        ; NE
    ret
.nw
    ld a, 7
    ret
.ew
    bit 7, b
    jr nz, .w
    ld a, 2                        ; E
    ret
.w
    ld a, 6
    ret
.ns
    bit 7, c
    jr nz, .n
    ld a, 4                        ; S
    ret
.n
    xor a                          ; N
    ret

PUSHS "Direction velocity tables", ROMX, BANK[3]
DIR_VX: db 0, 34, 48, 34, 0, -34, -48, -34
DIR_VY: db -48, -34, 0, 34, 48, 34, 0, -34
POPS

; hl += sign-extend(a). clobbers a, d, e, h, l
AddSignedHL:
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

; clamp signed 16-bit hl to signed byte in a
ClampHLSigned:
    bit 7, h
    jr z, .pos
    ld a, h
    cp $FF
    jr nz, .big                      ; < -256
    bit 7, l
    jr z, .big                       ; -256..-129 (h=$FF alone is not enough)
    ld a, l
    ret
.big
    ld a, -128
    ret
.pos
    ld a, h
    and a
    jr nz, .bigp                     ; >= 256
    bit 7, l
    jr nz, .bigp                     ; 128..255
    ld a, l
    ret
.bigp
    ld a, 127
    ret

; load dir a's velocity: b = vx, c = vy
DirVel:
    ld hl, DIR_VX
    ld e, a
    ld d, 0
    add hl, de
    ld b, [hl]
    ld hl, DIR_VY
    add hl, de
    ld c, [hl]
    ret

; pixel diffs: b = dx, c = dy (enemy minus ship, each clamped to a signed
; byte via ClampHLSigned). clobbers a, d, e, h, l
EnemyDelta:
    ld a, [wEnemyX]
    ld l, a
    ld a, [wEnemyX+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, [wShipX]
    ld c, a
    ld a, [wShipX+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call ClampHLSigned
    push af
    ld a, [wEnemyY]
    ld l, a
    ld a, [wEnemyY+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, [wShipY]
    ld c, a
    ld a, [wShipY+1]
    ld b, a
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call ClampHLSigned
    ld c, a
    pop af
    ld b, a
    ret

; ---------------------------------------------------------------------------
; Firing
; ---------------------------------------------------------------------------

; Player cannon (A at sea): aims at the enemy if active, else fires ahead.
FireCannon::
    ld a, [wFireCool]
    and a
    ret nz
    ld a, [wBallPActive]
    and a
    ret nz
    ld a, [wCrew]
    srl a                        ; more hands aboard, faster reload
    ld b, a
    ld a, 30
    sub b
    ld [wFireCool], a
    ld a, [wEnemyActive]
    and a
    jr z, .ahead
    call EnemyDelta
    call SnapDir
    jr .fire
.ahead
    ld a, [wHeading]               ; 0=N,1=E,2=S,3=W -> dir 0,2,4,6
    add a
.fire
    call DirVel
    ld a, 1
    ld [wBallPActive], a
    ld a, b
    ld [wBallPVX], a
    ld a, c
    ld [wBallPVY], a
    ld a, [wPosX]
    ld [wBallPX], a
    ld a, [wPosX+1]
    ld [wBallPX+1], a
    ld a, [wPosY]
    ld [wBallPY], a
    ld a, [wPosY+1]
    ld [wBallPY+1], a
    ld a, [wBallLife]                ; long guns upgrade: 40 -> 56 frames
    ld [wBallPLife], a
    ; muzzle smoke at the ship's bow
    ld a, [wShipX]
    ld [wSmokeX], a
    ld a, [wShipX+1]
    ld [wSmokeX+1], a
    ld a, [wShipY]
    ld [wSmokeY], a
    ld a, [wShipY+1]
    ld [wSmokeY+1], a
    ld a, 10
    ld [wSmokeT], a
    ld a, SFX_CANNON
    call PlaySfx
    ret

EnemyFire:
    ld a, [wBallEActive]
    and a
    ret nz
    call EnemyDelta
    ld a, b
    cpl
    inc a                          ; dx = ship - enemy
    ld b, a
    ld a, c
    cpl
    inc a
    ld c, a
    call SnapDir
    call DirVel
    ld a, 1
    ld [wBallEActive], a
    ld a, b
    ld [wBallEVX], a
    ld a, c
    ld [wBallEVY], a
    ld a, [wEnemyX]
    ld [wBallEX], a
    ld a, [wEnemyX+1]
    ld [wBallEX+1], a
    ld a, [wEnemyY]
    ld [wBallEY], a
    ld a, [wEnemyY+1]
    ld [wBallEY+1], a
    ld a, 40
    ld [wBallELife], a
    ld a, SFX_CANNON
    call PlaySfx
    ret

; ---------------------------------------------------------------------------
; Per-frame updates
; ---------------------------------------------------------------------------
UpdateCombat::
    call UpdateEnemy
    call UpdateBalls
    ld a, [wFireCool]
    and a
    jr z, .cd
    dec a
    ld [wFireCool], a
.cd
    ; juice timers (wEnemyFlash..wSmokeT are contiguous)
    ld hl, wEnemyFlash
    ld b, 4
.fxTick
    ld a, [hl]
    and a
    jr z, .fxNext
    dec [hl]
.fxNext
    inc hl
    dec b
    jr nz, .fxTick
    call UpdateMerchant
    ; a robbed merchant's escort keeps trying until it finds water
    ld a, [wEscortPend]
    and a
    jr z, .noEscort
    ld a, [wEnemyActive]
    and a
    jr nz, .noEscort
    call SpawnEnemy
    ld a, [wEnemyActive]
    and a
    jr z, .noEscort
    xor a
    ld [wEscortPend], a
.noEscort
    ret

UpdateEnemy:
    ld a, [wEnemyActive]
    and a
    ret z
    ; LOS watchdog: an enemy that has had no clear line to the ship for a
    ; long time (stuck behind land, e.g. spawned into a disconnected
    ; lagoon) gives up and despawns, so it can respawn somewhere useful
    ld a, [wLosT]
    and a
    jr z, .doLOS
    dec a
    ld [wLosT], a
    jr .losDone
.doLOS
    ld a, 16
    ld [wLosT], a
    call HasLOS
    and a
    jr nz, .losClear
    ld a, [wNoLOS]
    inc a
    ld [wNoLOS], a
    cp 40                          ; ~640 frames without a shot line
    jp nc, .despawn
    jr .losDone
.losClear
    xor a
    ld [wNoLOS], a
.losDone
    ; dx/dy as signed bytes (clamped)
    call EnemyDelta                ; b = dx, c = dy
    ; despawn if |dx| or |dy| > 120 (they were clamped at 127: check raw-ish)
    ld a, b
    call AbsA
    cp 121
    jp nc, .despawn
    ld a, c
    call AbsA
    cp 121
    jp nc, .despawn
    ; chebyshev = max(|dx|, |dy|)
    ld a, b
    call AbsA
    ld e, a
    ld a, c
    call AbsA
    cp e
    jr nc, .m0
    ld a, e
.m0
    ld [wEvX], a                   ; cheb distance
    ld [wEvC], a                   ; keep for fire control (wEvX is reused for vx)
    ; velocity: approach if cheb > 40, deadzone < 4 per axis
    xor a
    ld [wEvY], a                   ; reuse as scratch 0
    ld a, e                        ; |dx|
    cp 4
    jr c, .vx0
    ld a, b
    bit 7, a
    jr z, .vxP
    ld a, 20                       ; dx<0: enemy west of ship -> move east
    jr .vxSet
.vxP
    ld a, -20                      ; dx>0: enemy east of ship -> move west
    jr .vxSet
.vx0
    xor a
.vxSet
    ld e, a                        ; vx
    ld a, c
    call AbsA
    cp 4
    jr c, .vy0
    ld a, c
    bit 7, a
    jr z, .vyP
    ld a, 20
    jr .vySet
.vyP
    ld a, -20
    jr .vySet
.vy0
    xor a
.vySet
    ld d, a                        ; vy
    ld a, [wEvX]                   ; cheb
    cp 41
    jr c, .hold
    ld a, e
    ld [wEvX], a                   ; vx
    ld a, d
    ld [wEvY], a                   ; vy
    jr .apply
.hold
    xor a
    ld [wEvX], a
    ld [wEvY], a
.apply
    ; land check at target tile: 12.4 -> tile = >>7
    ld a, [wEnemyX]
    ld l, a
    ld a, [wEnemyX+1]
    ld h, a
    ld a, [wEvX]
    call AddSignedHL               ; hl = enemyX + vx
    REPT 7
    srl h
    rr l
    ENDR
    ld c, l
    ld b, h                        ; target tx
    ld a, [wEnemyY]
    ld l, a
    ld a, [wEnemyY+1]
    ld h, a
    ld a, [wEvY]
    call AddSignedHL
    REPT 7
    srl h
    rr l
    ENDR
    ld e, l
    ld d, h                        ; target ty
    push bc
    push de
    call WorldTile
    pop de
    pop bc
    cp TILE_SAND
    jr nc, .noMove                 ; land: hold position
    ; integrate
    ld a, [wEnemyX]
    ld l, a
    ld a, [wEnemyX+1]
    ld h, a
    ld a, [wEvX]
    call AddSignedHL
    ld a, l
    ld [wEnemyX], a
    ld a, h
    ld [wEnemyX+1], a
    ld a, [wEnemyY]
    ld l, a
    ld a, [wEnemyY+1]
    ld h, a
    ld a, [wEvY]
    call AddSignedHL
    ld a, l
    ld [wEnemyY], a
    ld a, h
    ld [wEnemyY+1], a
.noMove
    ; fire control
    ld a, [wEnemyFireCool]
    and a
    jr z, .ready
    dec a
    ld [wEnemyFireCool], a
    ret
.ready
    ld a, [wEvC]                   ; true range, not the velocity byte
    cp 90
    ret nc                         ; too far to fire
    ld a, [wEnemyFireRate]
    ld [wEnemyFireCool], a
    call EnemyFire
    ret
.despawn
    xor a
    ld [wEnemyActive], a
    ld [wBallEActive], a
    ld [wShadowOAM + 4], a
    ; a despawned final-battle guardian must not consume its wave (e.g.
    ; the player wrecked and respawned far away): hand it back so
    ; CellWatch spawns it again — otherwise the finale can never be won.
    ld a, [wIsGuardian]
    and a
    ret z
    ld a, [wFinal]
    and a
    ret z
    cp 6
    ret z
    dec a
    ld [wFinal], a
    ret

UpdateBalls:
    ; --- player ball ---
    ld a, [wBallPActive]
    and a
    jp z, .enemyBall
    ; integrate
    ld a, [wBallPX]
    ld l, a
    ld a, [wBallPX+1]
    ld h, a
    ld a, [wBallPVX]
    call AddSignedHL
    ld a, l
    ld [wBallPX], a
    ld a, h
    ld [wBallPX+1], a
    ld a, [wBallPY]
    ld l, a
    ld a, [wBallPY+1]
    ld h, a
    ld a, [wBallPVY]
    call AddSignedHL
    ld a, l
    ld [wBallPY], a
    ld a, h
    ld [wBallPY+1], a
    ; lifetime
    ld a, [wBallPLife]
    dec a
    ld [wBallPLife], a
    jp z, .killP
    ; land check
    ld a, [wBallPX]
    ld l, a
    ld a, [wBallPX+1]
    ld h, a
    REPT 7
    srl h
    rr l
    ENDR                           ; ball tile x (12.4 -> tile = >>7)
    ld c, l
    ld b, h
    ld a, [wBallPY]
    ld l, a
    ld a, [wBallPY+1]
    ld h, a
    REPT 7
    srl h
    rr l
    ENDR
    ld e, l
    ld d, h
    call WorldTile
    cp TILE_SAND
    jp nc, .killP
    ; hit enemy?
    ld a, [wEnemyActive]
    and a
    jp z, .enemyBall
    ; |ballPx - enemyPx| < 6 (pixel space)
    ld a, [wBallPX]
    ld l, a
    ld a, [wBallPX+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR                           ; hl = ballPx
    ld a, [wEnemyX]
    ld c, a
    ld a, [wEnemyX+1]
    ld b, a
    REPT 4
    srl b
    rr c
    ENDR                           ; bc = enemyPx
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call AbsHL                     ; hl = |dx|
    ld a, h
    and a
    jp nz, .enemyBall              ; too far
    ld a, l
    cp 6
    jp nc, .enemyBall
    ld a, [wBallPY]
    ld l, a
    ld a, [wBallPY+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, [wEnemyY]
    ld c, a
    ld a, [wEnemyY+1]
    ld b, a
    REPT 4
    srl b
    rr c
    ENDR
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    call AbsHL
    ld a, h
    and a
    jp nz, .enemyBall
    ld a, l
    cp 6
    jp nc, .enemyBall
    ; HIT!
    call .killP2
    ld a, SFX_HIT
    call PlaySfx
    ld a, 8
    ld [wEnemyFlash], a            ; blink the stricken ship
    ld a, [wEnemyHP]
    dec a
    ld [wEnemyHP], a
    jp nz, .enemyBall
    ; sink!
    xor a
    ld [wEnemyActive], a
    ; run the sinking animation from her last position
    ld a, 24
    ld [wSinkT], a
    ld a, [wEnemyX]
    ld l, a
    ld a, [wEnemyX+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld [wSinkX], a
    ld a, h
    ld [wSinkX+1], a
    ld a, [wEnemyY]
    ld l, a
    ld a, [wEnemyY+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld [wSinkY], a
    ld a, h
    ld [wSinkY+1], a
    ld a, SFX_SINK
    call PlaySfx
    ld a, SFX_COIN
    call PlaySfx
    call Rand16
    and 31
    add 15
    ld b, a
    ld a, [wGold]
    add b
    ld [wGold], a
    ld a, [wGold+1]
    adc 0
    ld [wGold+1], a
    ; guardian bookkeeping
    ld a, [wIsGuardian]
    and a
    jp z, .enemyBall
    ld a, [wFinal]
    and a
    jr z, .normalSink
    cp 5
    jp z, .victorySink
    jp .enemyBall                  ; mid-final-battle: next wave via CellWatch
.normalSink
    ld a, [wCurIsle]
    call SetGuardBit
    jp .enemyBall
.victorySink
    call Victory
    jp .enemyBall
.killP
    call .killP2
.enemyBall
    ; --- enemy ball ---
    ld a, [wBallEActive]
    and a
    ret z
    ld a, [wBallEX]
    ld l, a
    ld a, [wBallEX+1]
    ld h, a
    ld a, [wBallEVX]
    call AddSignedHL
    ld a, l
    ld [wBallEX], a
    ld a, h
    ld [wBallEX+1], a
    ld a, [wBallEY]
    ld l, a
    ld a, [wBallEY+1]
    ld h, a
    ld a, [wBallEVY]
    call AddSignedHL
    ld a, l
    ld [wBallEY], a
    ld a, h
    ld [wBallEY+1], a
    ld a, [wBallELife]
    dec a
    ld [wBallELife], a
    jp z, .killE                 ; SFX code grew this branch past jr range
    ; hit player? |ballPx - shipPx| < 6 both axes
    ld a, [wBallEX]
    ld l, a
    ld a, [wBallEX+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, [wShipX]
    ld c, a
    ld a, [wShipX+1]
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
    cp 6
    ret nc
    ld a, [wBallEY]
    ld l, a
    ld a, [wBallEY+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, [wShipY]
    ld c, a
    ld a, [wShipY+1]
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
    cp 6
    ret nc
    ; HIT!
    xor a
    ld [wBallEActive], a
    ld a, [wDmgCool]
    and a
    ret nz
    ld a, 20
    ld [wDmgCool], a
    ld a, 8
    ld [wShakeT], a
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
    jp Wreck
.killE
    xor a
    ld [wBallEActive], a
    ld de, wBallEX
    call .setSplashP
    ret
.killP2
    xor a
    ld [wBallPActive], a
    ld de, wBallPX
    call .setSplashP
    ret

; in: de = ptr to a ball's 12.4 X (Y at de+2). Splash there for 8 frames.
; clobbers a, d, e, h, l
.setSplashP
    ld a, [de]
    ld l, a
    inc de
    ld a, [de]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld [wSplashX], a
    ld a, h
    ld [wSplashX+1], a
    inc de
    ld a, [de]
    ld l, a
    inc de
    ld a, [de]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld [wSplashY], a
    ld a, h
    ld [wSplashY+1], a
    ld a, 8
    ld [wSplashT], a
    ret

; ---------------------------------------------------------------------------
; Rendering into shadow OAM (entries 1-3). Called from UpdateSail.
; ---------------------------------------------------------------------------
RenderCombat::
    ; --- enemy (entry 1) ---
    ld a, [wEnemyActive]
    and a
    jr z, .trySink
    ; hit flash: blink the sprite every 2 frames while the timer is live
    ld a, [wEnemyFlash]
    and a
    jr z, .showE
    and 2
    jr nz, .hideE
.showE
    ld a, [wEnemyX]
    ld l, a
    ld a, [wEnemyX+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld hl, wCamX
    sub [hl]
    add 4
    ld b, a                        ; sx
    ld a, [wEnemyY]
    ld l, a
    ld a, [wEnemyY+1]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld hl, wCamY
    sub [hl]
    add 12
    ld c, a                        ; sy
    ; off-screen? hide
    ld a, b
    cp 169
    jr nc, .hideE
    ld a, c
    cp 160
    jr nc, .hideE
    ld hl, wShadowOAM + 4
    ld a, c
    ld [hli], a
    ld a, b
    ld [hli], a
    ld a, TILE_SHIP_S
    ld [hli], a
    ld a, $10                      ; OBP1 (dark pirate)
    ld [hl], a
    jr .ballP
.hideE
    xor a
    ld [wShadowOAM + 4], a
    jr .ballP
.trySink
    ld a, [wSinkT]
    and a
    jr z, .hideE
    ; she slides under: sink Y offset = (24 - t) / 4 px
    ld a, 24
    ld hl, wSinkT
    sub [hl]
    srl a
    srl a
    ld hl, wSinkY
    add [hl]
    ld [wFxY], a
    ld a, [wSinkY+1]
    ld [wFxY+1], a
    ld a, [wSinkX]
    ld [wFxX], a
    ld a, [wSinkX+1]
    ld [wFxX+1], a
    ld de, wFxX
    ld hl, wShadowOAM + 4
    ld b, TILE_SHIP_S
    ld c, $10                      ; OBP1 (dark pirate)
    call .pxSprite
.ballP
    ld a, [wBallPActive]
    and a
    jr z, .hideBP
    ld de, wBallPX
    ld hl, wShadowOAM + 8
    call .ballSprite
    jr .ballE
.hideBP
    xor a
    ld [wShadowOAM + 8], a
.ballE
    ld a, [wBallEActive]
    and a
    jr z, .hideBE
    ld de, wBallEX
    ld hl, wShadowOAM + 12
    call .ballSprite
    jr .fx
.hideBE
    xor a
    ld [wShadowOAM + 12], a
.fx
    ; --- splash (entry 4) ---
    ld a, [wSplashT]
    and a
    jr z, .noSplash
    ld de, wSplashX
    ld hl, wShadowOAM + 16
    ld b, TILE_SPLASH
    ld c, 0
    call .pxSprite
    jr .smoke
.noSplash
    xor a
    ld [wShadowOAM + 16], a
.smoke
    ; --- muzzle smoke (entry 5) ---
    ld a, [wSmokeT]
    and a
    jr z, .noSmoke
    ld de, wSmokeX
    ld hl, wShadowOAM + 20
    ld b, TILE_SPLASH
    ld c, $10                      ; dark puff
    call .pxSprite
    jr .merch
.noSmoke
    xor a
    ld [wShadowOAM + 20], a
.merch
    ; --- merchant (entry 6) ---
    ld a, [wMerchActive]
    and a
    jr z, .hideM
    ld de, wMerchX
    ld hl, wShadowOAM + 24
    ld b, TILE_SHIP_E
    ld c, 0
    call .pxSprite
    ret
.hideM
    xor a
    ld [wShadowOAM + 24], a
    ret

; helper: write a sprite at a world-pixel position.
; in: de = ptr to world-px X (Y at de+2), hl = OAM entry, b = tile, c = attr
; off-screen: entry hidden. clobbers a, d, e, hl
.pxSprite
    ld a, [de]
    push hl
    ld hl, wCamX
    sub [hl]                       ; low-byte diff is exact (<256 apart)
    add 4
    inc de
    inc de
    push af
    ld a, [de]
    ld hl, wCamY
    sub [hl]
    add 12
    ld e, a                        ; e = sy
    pop af                         ; a = sx
    pop hl
    cp 169
    jr nc, .pxHide
    ld d, a
    ld a, e
    cp 160
    jr nc, .pxHide
    ld a, e
    ld [hli], a                    ; Y
    ld a, d
    ld [hli], a                    ; X
    ld a, b
    ld [hli], a                    ; tile
    ld a, c
    ld [hl], a                     ; attr
    ret
.pxHide
    xor a
    ld [hl], a
    ret

; helper: write ball sprite from 12.4 pos at [de] to OAM entry at hl
.ballSprite
    push hl
    ld a, [de]
    ld l, a
    inc de
    ld a, [de]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld hl, wCamX
    sub [hl]
    add 4
    ld b, a                        ; sx
    inc de
    ld a, [de]
    ld l, a
    inc de
    ld a, [de]
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld hl, wCamY
    sub [hl]
    add 12
    ld c, a                        ; sy
    pop hl
    ; off-screen?
    ld a, b
    cp 169
    jr nc, .hide
    ld a, c
    cp 160
    jr nc, .hide
    ld a, c
    ld [hli], a
    ld a, b
    ld [hli], a
    ld a, TILE_BALL
    ld [hli], a
    xor a
    ld [hl], a
    ret
.hide
    xor a
    ld [hl], a
    ret

; a = 1 iff the enemy has a clear tile line to the ship (samples the
; quarter points; any land tile blocks). Clobbers a, b, c, d, e, h, l.
HasLOS:
    ; enemy tile -> wLoX0/wLoY0
    ld a, [wEnemyX]
    ld l, a
    ld a, [wEnemyX+1]
    ld h, a
    REPT 7
    srl h
    rr l
    ENDR                           ; 12.4 -> tile
    ld a, l
    ld [wLoX0], a
    ld a, [wEnemyY]
    ld l, a
    ld a, [wEnemyY+1]
    ld h, a
    REPT 7
    srl h
    rr l
    ENDR
    ld a, l
    ld [wLoY0], a
    ; dx = shipTileX - enemyTileX (signed)
    ld a, [wShipX]
    ld l, a
    ld a, [wShipX+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, [wLoX0]
    ld c, a
    ld b, 0
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    ld a, l
    ld [wLoDX], a
    ld a, h
    ld [wLoDX+1], a
    ; dy = shipTileY - enemyTileY (signed)
    ld a, [wShipY]
    ld l, a
    ld a, [wShipY+1]
    ld h, a
    REPT 3
    srl h
    rr l
    ENDR
    ld a, [wLoY0]
    ld c, a
    ld b, 0
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    ld a, l
    ld [wLoDY], a
    ld a, h
    ld [wLoDY+1], a
    ; sample i = 1..3: point = base + (delta >> 2) * i
    ld a, 1
    ld [wLoI], a
.sample
    ; --- x ---
    ld a, [wLoDX]
    ld l, a
    ld a, [wLoDX+1]
    ld h, a
    sra h
    rr l
    sra h
    rr l                           ; hl = dx/4 (floor)
    ld c, l
    ld b, h                          ; bc = dx/4
    ld a, [wLoI]
.xMul
    dec a
    jr z, .xDone
    add hl, bc
    jr .xMul
.xDone
    ld a, [wLoX0]
    ld c, a
    ld a, l
    add c
    ld l, a
    ld a, h
    adc 0
    ld h, a                          ; hl = sample x (tile, in-world)
    push hl
    ; --- y ---
    ld a, [wLoDY]
    ld l, a
    ld a, [wLoDY+1]
    ld h, a
    sra h
    rr l
    sra h
    rr l
    ld c, l
    ld b, h
    ld a, [wLoI]
.yMul
    dec a
    jr z, .yDone
    add hl, bc
    jr .yMul
.yDone
    ld a, [wLoY0]
    ld c, a
    ld a, l
    add c
    ld e, a
    ld a, h
    adc 0
    ld d, a                          ; de = sample y (tile)
    pop bc                           ; bc = sample x
    call WorldTile
    cp TILE_SAND
    jr c, .nextSample                ; water: line still clear
    xor a                            ; land blocks the line
    ret
.nextSample
    ld a, [wLoI]
    inc a
    ld [wLoI], a
    cp 4
    jr nz, .sample
    ld a, 1
    ret

; hl = |hl| (16-bit absolute value)
AbsHL:
    bit 7, h
    ret z
    ld a, l
    cpl
    ld l, a
    ld a, h
    cpl
    ld h, a
    inc hl
    ret

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
wFireCool:      db
wBallPActive:   db
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
wStormDX:       db
wStormDY:       db
wStormDmgT:     db
wEvX:           db              ; enemy move temps
wEvY:           db
wEvC:           db              ; enemy chebyshev range (fire control)

SECTION "Combat", ROM0

; ---------------------------------------------------------------------------
; Encounter rolls (called when a cell is newly explored)
; ---------------------------------------------------------------------------
SpawnCheck::
    ld a, [wEnemyActive]
    and a
    ret nz                       ; one enemy at a time
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
    ld a, h
    cp 13                          ; storm ~5%
    call c, StartStorm
    ret

; Spawn a pirate ship near the player, in open water. 8 candidate offsets:
; far ring first, near ring second (guardians near big islands need options;
; callers retry on later frames when the pick lands on land).
SPAWN_OFF: db 100, 0, 0, 100, -100, 0, 0, -100   ; E S W N
           db  60, 0, 0, 60,  -60, 0, 0,  -60    ; near E S W N

SpawnEnemy::
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
    ret nc                         ; land: abort spawn
    ; activate
    ld a, 1
    ld [wEnemyActive], a
    ld a, PIRATE_HP
    ld [wEnemyHP], a
    ld a, PIRATE_FIRECOOL
    ld [wEnemyFireCool], a
    xor a
    ld [wIsGuardian], a            ; normal pirate, not a guardian
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
    call Rand16
    and $1F
    sub 16
    ld [wStormDX], a
    call Rand16
    and $1F
    sub 16
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
    call AddSignedToPosX
    ld a, [wStormDY]
    call AddSignedToPosY
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
    ret nz
    ld a, 20
    ld [wDmgCool], a
    jp Wreck

AddSignedToPosX:
    ld l, a
    ld h, 0
    bit 7, a
    jr z, .p
    dec h
.p
    ld a, [wPosX]
    add l
    ld [wPosX], a
    ld a, [wPosX+1]
    adc h
    ld [wPosX+1], a
    ret

AddSignedToPosY:
    ld l, a
    ld h, 0
    bit 7, a
    jr z, .p
    dec h
.p
    ld a, [wPosY]
    add l
    ld [wPosY], a
    ld a, [wPosY+1]
    adc h
    ld [wPosY+1], a
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

DIR_VX: db 0, 34, 48, 34, 0, -34, -48, -34
DIR_VY: db -48, -34, 0, 34, 48, 34, 0, -34

; clamp signed 16-bit hl to signed byte in a
ClampHLSigned:
    bit 7, h
    jr z, .pos
    ld a, h
    cp $FF
    jr nz, .big
    ld a, l
    ret
.big
    ld a, -128
    ret
.pos
    ld a, h
    and a
    jr nz, .bigp
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

; pixel diff: hl = a16-position minus b16-position...
; computes dx = (wEnemyX>>4) - wShipX clamped, in a
EnemyDxByte:
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
    ret

EnemyDyByte:
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
    ld a, 30
    ld [wFireCool], a
    ld a, [wEnemyActive]
    and a
    jr z, .ahead
    call EnemyDxByte
    push af
    call EnemyDyByte
    ld c, a
    pop af
    ld b, a
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
    ld a, 40
    ld [wBallPLife], a
    ld a, SFX_CANNON
    call PlaySfx
    ret

EnemyFire:
    ld a, [wBallEActive]
    and a
    ret nz
    call EnemyDxByte
    cpl
    inc a                          ; dx = ship - enemy
    push af
    call EnemyDyByte
    cpl
    inc a
    ld c, a
    pop af
    ld b, a
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
    ret

UpdateEnemy:
    ld a, [wEnemyActive]
    and a
    ret z
    ; dx/dy as signed bytes (clamped); NOTE: EnemyDyByte clobbers b!
    call EnemyDxByte
    ld [wEvX], a                   ; stash dx
    call EnemyDyByte
    ld c, a                        ; c = dy
    ld a, [wEvX]
    ld b, a                        ; b = dx
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
    and a
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
    and a
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
    call .addSignedHL              ; hl = enemyX + vx
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
    call .addSignedHL
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
    call .addSignedHL
    ld a, l
    ld [wEnemyX], a
    ld a, h
    ld [wEnemyX+1], a
    ld a, [wEnemyY]
    ld l, a
    ld a, [wEnemyY+1]
    ld h, a
    ld a, [wEvY]
    call .addSignedHL
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
    ld a, PIRATE_FIRECOOL
    ld [wEnemyFireCool], a
    call EnemyFire
    ret
.despawn
    xor a
    ld [wEnemyActive], a
    ld [wBallEActive], a
    ld [wShadowOAM + 4], a
    ret

; helper: hl += sign-extend(a). clobbers a, h, l
.addSignedHL
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
    call .addS
    ld a, l
    ld [wBallPX], a
    ld a, h
    ld [wBallPX+1], a
    ld a, [wBallPY]
    ld l, a
    ld a, [wBallPY+1]
    ld h, a
    ld a, [wBallPVY]
    call .addS
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
    jr nz, .enemyBall
    ld a, l
    cp 6
    jr nc, .enemyBall
    ; HIT!
    call .killP2
    ld a, SFX_HIT
    call PlaySfx
    ld a, [wEnemyHP]
    dec a
    ld [wEnemyHP], a
    jp nz, .enemyBall
    ; sink!
    xor a
    ld [wEnemyActive], a
    ld [wShadowOAM + 4], a
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
    cp 3
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
    call .addS
    ld a, l
    ld [wBallEX], a
    ld a, h
    ld [wBallEX+1], a
    ld a, [wBallEY]
    ld l, a
    ld a, [wBallEY+1]
    ld h, a
    ld a, [wBallEVY]
    call .addS
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
    ret
.killP2
    xor a
    ld [wBallPActive], a
    ret

; helper: hl += sign-extend(a)
.addS
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

; ---------------------------------------------------------------------------
; Rendering into shadow OAM (entries 1-3). Called from UpdateSail.
; ---------------------------------------------------------------------------
RenderCombat::
    ; --- enemy (entry 1) ---
    ld a, [wEnemyActive]
    and a
    jr z, .hideE
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
    ret
.hideBE
    xor a
    ld [wShadowOAM + 12], a
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
    ld bc, wCamX
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

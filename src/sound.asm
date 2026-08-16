; Sound engine (M6): 3-channel music (pulse melody, pulse bass, noise
; percussion) + priority SFX on ch1/ch4.
;
; Music streams are (note, dur) byte pairs; note 0 = rest, $FF = loop to
; stream start, $FE = end (one-shot jingle; channel parks silent).
; Pulse notes index NOTE_PERIODS (1 = C2 .. 48 = B5). Noise notes index
; PERC (1 = kick, 2 = hat, 3 = snare). Durations are in frames (60 Hz).
;
; Tunes are public-domain shanties transcribed from ABC notation:
;   TITLE  = Drunken Sailor (thesession.org/tunes/15961, chorus)
;   SAIL   = Wellerman      (thesession.org/tunes/20383, setting 6)
;   PORT   = Spanish Ladies (musicaviva.com, farewell-and-adieu)
;   BATTLE = Blow the Man Down (sea-shanties.com)
;   WRECK  = Leave Her, Johnny, Leave Her (sea-shanties.com)
;   WIN    = Rolling Home (chorus; sea-shanties.com)

INCLUDE "hardware.inc"
INCLUDE "defs.inc"

; (SONG_*/JINGLE_*/SFX_* ids live in defs.inc: rgbasm DEFs don't export.)

; --- Note indices (NOTE_PERIODS entry, 1-based) ---
DEF N_E2  EQU 5
DEF N_F2  EQU 6
DEF N_G2  EQU 8
DEF N_A2  EQU 10
DEF N_B2  EQU 12
DEF N_C3  EQU 13
DEF N_D3  EQU 15
DEF N_E3  EQU 17
DEF N_F3  EQU 18
DEF N_G3  EQU 20
DEF N_A3  EQU 22
DEF N_C4  EQU 25
DEF N_CS4 EQU 26
DEF N_D4  EQU 27
DEF N_E4  EQU 29
DEF N_F4  EQU 30
DEF N_FS4 EQU 31
DEF N_G4  EQU 32
DEF N_GS4 EQU 33
DEF N_A4  EQU 34
DEF N_AS4 EQU 35
DEF N_B4  EQU 36
DEF N_C5  EQU 37
DEF N_D5  EQU 39
DEF N_E5  EQU 41

; --- Percussion ---
DEF P_KICK  EQU 1
DEF P_HAT   EQU 2
DEF P_SNARE EQU 3

SECTION "Sound WRAM", WRAM0
; per-channel state blocks, 5 bytes each, MUST stay contiguous and in order:
; {stream ptr dw, stream base dw, note timer db}
wMusCh1Ptr:  dw
wMusCh1Base: dw
wMusCh1T:    db
wMusCh2Ptr:  dw
wMusCh2Base: dw
wMusCh2T:    db
wMusCh4Ptr:  dw
wMusCh4Base: dw
wMusCh4T:    db
wMusCh:      db           ; MusTick channel index temp
wSongID::    db
wMuted::     db           ; SELECT toggles: 1 = all audio gated off
wSfx1T:      db           ; ch1 SFX frames remaining (steals melody)
wSfx4T:      db           ; ch4 SFX frames remaining (steals percussion)

SECTION "Sound", ROMX, BANK[3]

SoundInit::
    ld a, $80
    ldh [rAUDENA], a             ; APU on
    ld a, $77
    ldh [rAUDVOL], a             ; max master volume both sides
    ld a, $FF
    ldh [rAUDTERM], a            ; all channels to both ears
    ld a, $80
    ldh [rAUD1LEN], a            ; ch1 duty 50%
    ld a, $40
    ldh [rAUD2LEN], a            ; ch2 duty 25% (bass)
    xor a
    ld [wSongID], a
    ld [wSfx1T], a
    ld [wSfx4T], a
    ld [wMusCh1T], a
    ld [wMusCh2T], a
    ld [wMusCh4T], a
    ret

; in: a = SONG_* / JINGLE_*
SetSong::
    ld [wSongID], a
    and a
    jr nz, .load
    ; song 0 = silence everything
    xor a
    ldh [rAUD1ENV], a
    ldh [rAUD2ENV], a
    ldh [rAUD4ENV], a
    ret
.load
    dec a
    ld b, a
    add a
    add b
    add a                          ; a = (id-1) * 6
    ld e, a
    ld d, 0
    ld hl, SONG_TABLE
    add hl, de
    ld a, [hli]
    ld [wMusCh1Ptr], a
    ld [wMusCh1Base], a
    ld a, [hli]
    ld [wMusCh1Ptr+1], a
    ld [wMusCh1Base+1], a
    ld a, [hli]
    ld [wMusCh2Ptr], a
    ld [wMusCh2Base], a
    ld a, [hli]
    ld [wMusCh2Ptr+1], a
    ld [wMusCh2Base+1], a
    ld a, [hli]
    ld [wMusCh4Ptr], a
    ld [wMusCh4Base], a
    ld a, [hli]
    ld [wMusCh4Ptr+1], a
    ld [wMusCh4Base+1], a
    ld a, 1
    ld [wMusCh1T], a
    ld [wMusCh2T], a
    ld [wMusCh4T], a
    ret

; Called once per frame from MainLoop.
UpdateSound::
    ld a, [wMuted]
    and a
    ret nz
    ld a, [wSongID]
    and a
    ret z                          ; no music
    ; ch1: SFX steals the channel while active
    ld a, [wSfx1T]
    and a
    jr z, .mus1
    dec a
    ld [wSfx1T], a
    jr .ch2
.mus1
    xor a
    call MusTick
.ch2
    ld a, 1
    call MusTick
    ; ch4: SFX steals percussion
    ld a, [wSfx4T]
    and a
    jr z, .mus4
    dec a
    ld [wSfx4T], a
    ret
.mus4
    ld a, 2
    call MusTick
    ret

; in: a = channel index (0 = ch1 melody, 1 = ch2 bass, 2 = ch4 percussion)
MusTick:
    ld [wMusCh], a
    ld b, a
    add a
    add a
    add b                          ; a * 5
    ld e, a
    ld d, 0
    ld hl, wMusCh1Ptr
    add hl, de                     ; hl = channel state block
    push hl
    inc hl
    inc hl
    inc hl
    inc hl                         ; hl = &timer
    dec [hl]
    pop hl
    ret nz                         ; note still sounding
    ; --- fetch next (note, dur) ---
    ld e, [hl]
    inc hl
    ld d, [hl]                     ; de = stream pos
    dec hl
.read
    ld a, [de]
    cp $FF
    jr z, .loop
    cp $FE
    jr z, .end
    inc de
    ld b, a                        ; b = note
    ld a, [de]
    inc de
    ld c, a                        ; c = dur
    jr .store
.loop
    inc hl
    inc hl
    ld a, [hli]                    ; base lo
    ld d, [hl]                     ; base hi
    ld e, a
    dec hl                         ; back to block start (+3 -> +0)
    dec hl
    dec hl
    jr .read
.end
    ld b, 0                        ; park: long rests
    ld c, 250
.store
    ld [hl], e                     ; stream ptr
    inc hl
    ld [hl], d
    inc hl
    inc hl
    inc hl
    ld [hl], c                     ; note timer
    ; --- play note b ---
    ld a, [wMusCh]
    cp 2
    jr z, .noise
    ld a, b
    and a
    jr z, .rest
    ; period = NOTE_PERIODS + (b-1)*2
    dec b
    sla b
    ld hl, NOTE_PERIODS
    ld e, b
    ld d, 0
    add hl, de
    ld a, [hli]
    ld e, a                        ; e = period lo
    ld d, [hl]                     ; d = period hi
    ld a, [wMusCh]
    and a
    jr nz, .ch2
    ld a, e
    ldh [rAUD1LOW], a
    ld a, $F3                      ; vol 15, decay 3
    ldh [rAUD1ENV], a
    ld a, d
    or $80                         ; trigger
    ldh [rAUD1HIGH], a
    ret
.ch2
    ld a, e
    ldh [rAUD2LOW], a
    ld a, $C3                      ; vol 12, decay 3
    ldh [rAUD2ENV], a
    ld a, d
    or $80
    ldh [rAUD2HIGH], a
    ret
.rest
    ld a, [wMusCh]
    and a
    jr nz, .rest2
    xor a
    ldh [rAUD1ENV], a
    ret
.rest2
    xor a
    ldh [rAUD2ENV], a
    ret
.noise
    ld a, b
    and a
    jr z, .restN
    dec b
    sla b
    ld hl, PERC
    ld e, b
    ld d, 0
    add hl, de
    ld a, [hli]
    ldh [rAUD4ENV], a
    ld a, [hl]
    ldh [rAUD4POLY], a
    ld a, $C0                      ; trigger
    ldh [rAUD4GO], a
    ret
.restN
    xor a
    ldh [rAUD4ENV], a
    ret

; SELECT anywhere (but the seed editor) toggles all audio.
ToggleMute::
    ld a, [wMuted]
    xor 1
    ld [wMuted], a
    ret z                          ; unmuted: music resumes on the next note
    xor a                          ; muted: cut every channel right now
    ldh [rAUD1ENV], a
    ldh [rAUD2ENV], a
    ldh [rAUD4ENV], a
    ret

; in: a = SFX_* id (1..9). Plays immediately; music channel resumes after.
PlaySfx::
    ld c, a                        ; keep the id: the gate needs a, and
    ld a, [wMuted]                 ; callers keep their own values in b
    and a
    ret nz
    ld a, c
    dec a
    add a
    add a                          ; (id-1) * 4
    ld e, a
    ld d, 0
    ld hl, SFX_TABLE
    add hl, de
    ld a, [hli]                    ; channel: 1 = tone, 4 = noise
    cp 1
    jr z, .tone
    ld a, [hli]                    ; env
    ldh [rAUD4ENV], a
    ld a, [hli]                    ; poly
    ldh [rAUD4POLY], a
    ld a, $C0
    ldh [rAUD4GO], a
    ld a, [hl]                     ; dur
    ld [wSfx4T], a
    ret
.tone
    ld a, [hli]                    ; period lo
    ldh [rAUD1LOW], a
    ld a, $C3                      ; vol 12, decay 3
    ldh [rAUD1ENV], a
    ld a, [hli]                    ; period hi
    or $80
    ldh [rAUD1HIGH], a
    ld a, [hl]                     ; dur
    ld [wSfx1T], a
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------

SECTION "Sound data", ROMX, BANK[3]

; GB pulse period = 2048 - 131072/f. 48 entries: C2..B5.
NOTE_PERIODS:
    dw   44,  157,  263,  363,  457,  547,  631,  710  ; C2..G2
    dw  786,  856,  923,  986, 1046, 1102, 1155, 1205  ; G#2..D#3
    dw 1253, 1297, 1339, 1379, 1417, 1452, 1486, 1517  ; E3..B3
    dw 1547, 1575, 1602, 1627, 1650, 1673, 1694, 1714  ; C4..G4
    dw 1732, 1750, 1767, 1783, 1797, 1812, 1825, 1837  ; G#4..D#5
    dw 1849, 1860, 1871, 1881, 1890, 1899, 1907, 1915  ; E5..B5

; percussion: (NR42 env, NR43 poly)
PERC:
    db $F3, $23                    ; kick
    db $61, $D0                    ; hat
    db $93, $61                    ; snare

; SFX: (channel, p1, p2, dur). ch1: p1/p2 = period lo/hi. ch4: env, poly.
SFX_TABLE:
    db 4, $F6, $37, 24             ; CANNON: low boom
    db 4, $A4, $52, 10             ; HIT: crack
    db 4, $85, $71, 14             ; SPLASH
    db 4, $C9, $43, 100            ; STORM: long wind rumble
    db 4, $F9, $47, 70             ; WRECK: crash
    db 4, $E6, $27, 30             ; SINK: deep boom
    db 1, $7B, $07, 7              ; COIN: B5 ping
    db 1, $59, $07, 24             ; BELL: G5 ring
    db 4, $A2, $03, 6              ; KNOCK: woody tap

SONG_TABLE:
    dw TitleCh1, TitleCh2, TitleCh4
    dw SailCh1,  SailCh2,  SailCh4
    dw PortCh1,  PortCh2,  PortCh4
    dw BatCh1,   BatCh2,   BatCh4
    dw DigJingle, SilentStream, SilentStream
    dw WinJingle, SilentStream, SilentStream
    dw WreckSting, SilentStream, SilentStream

SilentStream:
    db 0, 250, $FF

; --- Drunken Sailor (chorus), D dorian, eighth = 12 ---
TitleCh1:
    db N_A4,24, N_A4,12, N_A4,12, N_A4,24, N_A4,12, N_A4,12
    db N_A4,24, N_D4,24, N_F4,24, N_A4,24
    db N_G4,24, N_G4,12, N_G4,12, N_G4,24, N_G4,12, N_G4,12
    db N_G4,24, N_C4,24, N_E4,24, N_G4,24
    db N_A4,24, N_A4,12, N_A4,12, N_A4,24, N_A4,12, N_A4,12
    db N_A4,24, N_B4,24, N_C5,24, N_D5,24
    db N_C5,24, N_A4,24, N_G4,24, N_E4,24
    db N_D4,48, N_D4,48, $FF
TitleCh2:
    db N_D3,24, N_D3,24, N_D3,24, N_D3,24
    db N_D3,24, N_D3,24, N_D3,24, N_D3,24
    db N_G2,24, N_G2,24, N_G2,24, N_G2,24
    db N_C3,24, N_C3,24, N_C3,24, N_C3,24
    db N_D3,24, N_D3,24, N_D3,24, N_D3,24
    db N_D3,24, N_D3,24, N_D3,24, N_D3,24
    db N_C3,24, N_C3,24, N_C3,24, N_C3,24
    db N_D3,24, N_D3,24, N_D3,24, N_D3,24, $FF
TitleCh4:
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12, $FF

; --- Wellerman, E minor, eighth = 12 ---
SailCh1:
    db N_B4,12
    db N_E4,12, N_E4,12, N_E4,12, N_G4,12
    db N_B4,12, N_B4,12, N_B4,12, N_B4,12
    db N_C5,12, N_A4,12, N_A4,6, N_B4,6, N_C5,6, N_D5,6
    db N_E5,12, N_B4,12, N_B4,12, N_B4,12
    db N_E4,12, N_E4,12, N_E4,12, N_G4,12
    db N_B4,12, N_B4,12, N_B4,12, N_C5,12
    db N_B4,12, N_A4,12, N_G4,12, N_FS4,12
    db N_E4,24, N_E4,24
    db N_E5,24, N_E5,12, N_C5,12
    db N_D5,12, N_B4,12, N_B4,12, N_B4,12
    db N_C5,12, N_A4,12, N_A4,6, N_B4,6, N_C5,6, N_A4,6
    db N_B4,12, N_E4,12, N_E4,24
    db N_E5,24, N_E5,12, N_C5,12
    db N_D5,12, N_B4,12, N_B4,12, N_C5,12
    db N_B4,12, N_A4,12, N_G4,12, N_FS4,12
    db N_E4,24, N_E4,24, $FF
SailCh2:
    db 0,12
    db N_E3,48, N_E3,48, N_C3,48, N_D3,48
    db N_E3,48, N_E3,48, N_B2,48, N_E3,48
    db N_E3,48, N_E3,48, N_C3,48, N_E3,48
    db N_E3,48, N_E3,48, N_B2,48, N_E3,48, $FF
SailCh4:                                 ; full 780-frame loop (16 bars)
    db 0,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_HAT,12, P_HAT,12
    db P_KICK,12, P_HAT,12, P_SNARE,12, P_HAT,12, $FF

; --- Spanish Ladies, A harmonic minor, 3/4, eighth = 14 ---
PortCh1:
    db N_E4,28
    db N_A4,28, N_A4,28, N_GS4,28
    db N_A4,56, N_A4,14, N_B4,14
    db N_C5,28, N_B4,28, N_A4,28
    db N_GS4,28, N_E4,28, N_E4,28
    db N_A4,28, N_A4,28, N_GS4,28
    db N_A4,56, N_A4,14, N_B4,14
    db N_C5,28, N_B4,28, N_A4,28
    db N_B4,56, N_B4,28
    db N_C5,28, N_B4,28, N_A4,28
    db N_D5,28, N_C5,28, N_B4,28
    db N_E5,28, N_A4,28, N_B4,28
    db N_GS4,14, N_FS4,14, N_E4,28, N_E5,14, N_D5,14
    db N_C5,28, N_B4,28, N_A4,28
    db N_GS4,28, N_E4,28, N_E4,28
    db N_E4,28, N_A4,28, N_GS4,28
    db N_A4,56, 0,28, $FF
PortCh2:
    db 0,28
    db N_A2,84, N_A2,84, N_A2,84, N_E2,84
    db N_A2,84, N_A2,84, N_A2,84, N_E2,84
    db N_A2,84, N_F2,84, N_A2,84, N_E2,84
    db N_A2,84, N_E2,84, N_A2,84, N_A2,84, $FF
PortCh4:                                 ; full 1372-frame loop (16 bars)
    db 0,28
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14
    db P_KICK,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, P_HAT,14, $FF

; --- Blow the Man Down (battle), D major, 3/8, eighth = 12 ---
; Loop is exactly 600 frames; all three channels total 600.
BatCh1:
    db N_D4,12, N_FS4,12                          ; pickup
    db N_A4,12, N_B4,12, N_A4,12                  ; roll-in' down Pa-ra-dise
    db N_FS4,12, N_D4,12, N_FS4,12
    db N_G4,12, N_B4,12, N_A4,12
    db N_FS4,12, N_D4,12, N_FS4,12
    db N_A4,36                                    ; tum-me way
    db N_B4,36                                    ; hay
    db N_G4,12, N_FS4,12, N_G4,12                 ; blow the man
    db N_E4,24, N_B4,12                           ; down! A
    db N_B4,12, N_B4,12, N_B4,12                  ; sas-sy flash
    db N_B4,12, N_FS4,12, N_E4,12                 ; clip-per I
    db N_CS4,12, N_D4,12, N_G4,12                 ; chanc't for to
    db N_B4,24                                    ; meet
    db N_D5,24                                    ; Ooh! (fermata, held)
    db N_A4,12, N_A4,12, N_A4,12                  ; give us some
    db N_A4,24, N_G4,12                           ; time to blow
    db N_FS4,18, N_E4,6, N_FS4,12                 ; the man
    db N_D4,24                                    ; down!
    db $FF
BatCh2:
    db 0,24                                       ; pickup rest
    db N_D3,36, N_D3,36, N_G2,36, N_D3,36
    db N_A2,36, N_G2,36, N_C3,36, N_A2,36
    db N_G2,36, N_E3,36, N_C3,36
    db N_G2,24, N_D3,24
    db N_D3,36, N_A2,36, N_D3,36, N_D3,24
    db $FF
BatCh4:
    db P_KICK,12, P_HAT,12                        ; pickup bar (2 eighths)
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M1
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M2
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M3
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M4
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M5
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M6
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M7
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M8
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M9
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M10
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M11
    db P_KICK,12, P_HAT,12                        ; M12 (2 eighths)
    db P_KICK,12, P_HAT,12                        ; M13 (fermata)
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M14
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M15
    db P_KICK,12, P_HAT,12, P_HAT,12              ; M16
    db P_KICK,12, P_HAT,12                        ; M17
    db $FF

; --- One-shot jingles ($FE = end) ---
DigJingle:
    db N_D4,8, N_F4,8, N_A4,8, N_D5,8, N_A4,8, N_D5,24, $FE
; --- Rolling Home (chorus), C major, quarter = 18 ---
WinJingle:
    db N_G4,36, N_E4,9, N_G4,9                    ; rol-lin' home
    db N_C5,36, N_E4,9, N_G4,9                    ; rol-lin' home
    db N_E5,27, N_C5,9, N_G4,9, N_E4,9            ; rol-lin' home a-cross the
    db N_D5,36, N_B4,9, N_C5,9                    ; sea, rol-lin'
    db N_D5,54, N_C5,18                           ; home to dear Ol'
    db N_B4,18, N_F4,18, N_A4,36                  ; Eng-land, rol-lin'
    db N_G4,18, N_FS4,18, N_G4,18                 ; home fair
    db N_B4,54, N_G4,18                           ; land to
    db N_A4,18, N_B4,18, N_C5,36                  ; thee.
    db $FE
; --- Leave Her, Johnny, Leave Her (wreck), F major, quarter = 10 ---
WreckSting:
    db N_F4,10, N_G4,10                           ; oh the
    db N_A4,10, N_A4,10, N_A4,5, N_G4,5, N_F4,5, N_G4,5  ; times wuz hard an' the wa-ges
    db N_A4,5, N_AS4,5, N_A4,5, N_G4,5, N_F4,20   ; low, leave her
    db $FE

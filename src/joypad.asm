; Joypad reading with new-press detection and direction auto-repeat.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"

SECTION "Joypad", ROM0

; Reads the joypad into hJoyHeld (all held buttons) and hJoyNew (newly
; pressed this frame). Combined byte layout: see PADF_* in defs.inc.
ReadJoypad::
    ld a, JOYP_GET_CTRL_PAD      ; select d-pad (0 in bit 4)
    ldh [rJOYP], a
    ldh a, [rJOYP]               ; several reads to let inputs stabilize
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    cpl                          ; pressed = 1
    and JOYP_INPUTS
    swap a                       ; d-pad -> high nibble
    ld b, a
    ld a, JOYP_GET_BUTTONS       ; select buttons (0 in bit 5)
    ldh [rJOYP], a
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    cpl
    and JOYP_INPUTS
    or b                         ; A = all 8 inputs (PADF_* layout)
    ld b, a
    ld a, JOYP_GET_NONE
    ldh [rJOYP], a               ; deselect
    ; hJoyNew = held & ~previous
    ldh a, [hJoyHeld]
    cpl
    and b
    ldh [hJoyNew], a
    ld a, b
    ldh [hJoyHeld], a
    ret

; Direction auto-repeat: wRepEff gets new presses immediately, then repeats
; while a direction is held (REPEAT_DELAY frames, then every REPEAT_RATE).
ComputeRepeat::
    ldh a, [hJoyNew]
    and DIR_MASK
    jr nz, .fresh
    ldh a, [hJoyHeld]
    and DIR_MASK
    jr z, .none
    ld b, a                      ; b = held directions
    ld a, [wRepCtr]
    and a
    jr z, .repeat
    dec a
    jr z, .repeat
    ld [wRepCtr], a
.none
    xor a
    ld [wRepEff], a
    ret
.fresh
    ld [wRepEff], a
    ld a, REPEAT_DELAY
    ld [wRepCtr], a
    ret
.repeat
    ld a, b
    ld [wRepEff], a
    ld a, REPEAT_RATE
    ld [wRepCtr], a
    ret

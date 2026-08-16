; PRNG and hashing: 8x8 multiply, 16-bit mix (coordinate hashing for
; worldgen), and xorshift16 (stateful runtime RNG).

INCLUDE "defs.inc"

SECTION "RNG", ROM0

; in:  a = value, b = multiplier
; out: hl = a * b
; clobbers: a, b, c, d, e
Mul8::
    ld d, 0
    ld e, a                      ; de = value
    ld hl, 0
    ld c, 8
.loop
    srl b
    jr nc, .noAdd
    add hl, de
.noAdd
    sla e
    rl d
    dec c
    jr nz, .loop
    ret

; in: a = index (0..255), hl = word-table base; out: hl = table[a].
; The coordinate-hash multiplies are constant-per-axis, so the hot paths
; (LatHash, TileDetail, DistrictHash) read them from LUTs via this helper.
; clobbers: a, b, c
IdxWord::
    add a                          ; 2*index; carry set for index >= 128
    ld c, a
    ld b, 0
    jr nc, .noCarry
    inc b
.noCarry
    add hl, bc
    ld a, [hli]
    ld h, [hl]
    ld l, a
    ret

; Stateless 16-bit mixer (xorshift rounds: >>8, <<7, >>9, <<8).
; Deterministic: same input always gives same output. Used as the
; coordinate hash for world generation.
; in/out: hl
; clobbers: a, d, e
Mix16::
    ; x ^= x >> 8
    ld a, h
    xor l
    ld l, a
    ; x ^= x << 7
    ld d, h
    ld e, l
    SL16 d, e, 7
    ld a, l
    xor e
    ld l, a
    ld a, h
    xor d
    ld h, a
    ; x ^= x >> 9
    ld d, h
    ld e, l
    SR16 d, e, 9
    ld a, l
    xor e
    ld l, a
    ld a, h
    xor d
    ld h, a
    ; x ^= x << 8
    ld a, l
    xor h
    ld h, a
    ret

; Stateful xorshift16 (triplet 7,9,8; state must never be 0).
; out: hl = new random value (also stored back to wRngState)
; clobbers: a, d, e
Rand16::
    ld a, [wRngState]
    ld h, a
    ld a, [wRngState+1]
    ld l, a
    ; x ^= x << 7
    ld d, h
    ld e, l
    SL16 d, e, 7
    ld a, l
    xor e
    ld l, a
    ld a, h
    xor d
    ld h, a
    ; x ^= x >> 9
    ld d, h
    ld e, l
    SR16 d, e, 9
    ld a, l
    xor e
    ld l, a
    ld a, h
    xor d
    ld h, a
    ; x ^= x << 8
    ld a, l
    xor h
    ld h, a
    ; store back
    ld a, h
    ld [wRngState], a
    ld a, l
    ld [wRngState+1], a
    ret

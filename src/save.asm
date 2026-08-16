; Battery save/load (MBC5 cart RAM at $A000): two rotating slots with
; magic, version, and a checksum; a corrupted slot falls back to the other.
; The RS group below is the SINGLE SOURCE OF TRUTH for the record layout:
; both copy directions and the checksum range derive from its offsets.

INCLUDE "hardware.inc"
INCLUDE "defs.inc"

DEF SAVE_MAGIC_0 EQU $53
DEF SAVE_MAGIC_1 EQU $46
DEF SAVE_VERSION EQU 6          ; v6: two rotating slots + sequence byte. v5 rejected.

; Record layout (offsets into a slot)
    RSRESET
DEF SAVE_F_MAGIC0    RB 1
DEF SAVE_F_MAGIC1    RB 1
DEF SAVE_F_VERSION   RB 1
DEF SAVE_F_CSUM      RB 1
DEF SAVE_F_SEQ       RB 1
DEF SAVE_F_SEED      RB 4       ; wSeed
DEF SAVE_F_POS       RB 4       ; wPosX/wPosY (contiguous)
DEF SAVE_F_ECON      RB 8       ; wGold/wHull/wCrew/wCargo (contiguous)
DEF SAVE_F_EXPLORED  RB 32      ; wExplored
DEF SAVE_F_LASTPORT  RB 2       ; wLastPortDX/DY (contiguous)
DEF SAVE_F_MASKS     RB 4       ; wFragMask/wGuardMask (contiguous)
DEF SAVE_F_FINAL     RB 2       ; wFinal/wWon (contiguous)
DEF SAVE_F_PORTCELLS RB 32      ; wPortCells
DEF SAVE_F_BESTGOLD  RB 2       ; wBestGold
DEF SAVE_F_CARTDONE  RB 1       ; wCartDone
DEF SAVE_F_UPGRADES  RB 3       ; wHullMax/wMaxVel/wBallLife (contiguous)
DEF SAVE_REC_SIZE    RB 0

DEF SAVE_DATA_START EQU SAVE_F_SEED
DEF SAVE_DATA_LEN   EQU SAVE_REC_SIZE - SAVE_F_SEED
DEF SAVE_SLOT1      EQU $A070   ; slot 0 is $A000; $70 stride >= record size

STATIC_ASSERT SAVE_REC_SIZE == 99
STATIC_ASSERT SAVE_DATA_LEN == 94

SECTION "Save WRAM", WRAM0
wSaveSlot:: db          ; which slot the next SaveGame writes (0/1)
wSaveSeq::  db          ; rolling sequence: the newer save wins on load
wSlot0Ok:   db          ; LoadGame probe results
wSlot1Ok:   db

SECTION "Save", ROMX, BANK[3]

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
    ; best haul: keep the largest gold pile this cart has ever held
    ld a, [wGold]
    ld l, a
    ld a, [wGold+1]
    ld h, a
    ld a, [wBestGold+1]
    cp h
    jr c, .newBest
    jr nz, .bestDone
    ld a, [wBestGold]
    cp l
    jr nc, .bestDone
.newBest
    ld a, h
    ld [wBestGold+1], a
    ld a, l
    ld [wBestGold], a
.bestDone
    ld a, $0A
    ld [$0000], a                  ; RAM enable. INVARIANT: SRAM is enabled
                                   ; only inside SaveGame/LoadGame, never
                                   ; across a halt — power-loss with RAM
                                   ; enabled is the classic corruption vector
    ; two rotating slots: one corrupted save never costs the whole voyage
    ld a, [wSaveSlot]
    and a
    ld hl, $A000
    jr z, .haveBase
    ld hl, SAVE_SLOT1
.haveBase
    push hl                        ; slot base
    ; header, in RS-group order (magic0, magic1, version, csum, seq)
    ld a, SAVE_MAGIC_0
    ld [hli], a
    ld a, SAVE_MAGIC_1
    ld [hli], a
    ld a, SAVE_VERSION
    ld [hli], a
    xor a
    ld [hli], a                    ; checksum placeholder
    ld a, [wSaveSeq]
    ld [hli], a
    ; data fields, in RS-group order; lengths derived from the layout
    ld de, wSeed
    ld b, SAVE_F_POS - SAVE_F_SEED
    call CopyToSRAM
    ld de, wPosX                   ; wPosX/wPosY are contiguous
    ld b, SAVE_F_ECON - SAVE_F_POS
    call CopyToSRAM
    ld de, wGold                   ; wGold/wHull/wCrew/wCargo are contiguous
    ld b, SAVE_F_EXPLORED - SAVE_F_ECON
    call CopyToSRAM
    ld de, wExplored
    ld b, SAVE_F_LASTPORT - SAVE_F_EXPLORED
    call CopyToSRAM
    ld de, wLastPortDX             ; DX/DY contiguous
    ld b, SAVE_F_MASKS - SAVE_F_LASTPORT
    call CopyToSRAM
    ld de, wFragMask               ; wFragMask/wGuardMask contiguous
    ld b, SAVE_F_FINAL - SAVE_F_MASKS
    call CopyToSRAM
    ld de, wFinal                  ; wFinal/wWon contiguous
    ld b, SAVE_F_PORTCELLS - SAVE_F_FINAL
    call CopyToSRAM
    ld de, wPortCells
    ld b, SAVE_F_BESTGOLD - SAVE_F_PORTCELLS
    call CopyToSRAM
    ld de, wBestGold
    ld b, SAVE_F_CARTDONE - SAVE_F_BESTGOLD
    call CopyToSRAM
    ld de, wCartDone
    ld b, SAVE_F_UPGRADES - SAVE_F_CARTDONE
    call CopyToSRAM
    ld de, wHullMax                ; 3 contiguous upgrade bytes
    ld b, SAVE_REC_SIZE - SAVE_F_UPGRADES
    call CopyToSRAM
    ; checksum = sum of the data bytes at slot base + SAVE_DATA_START
    pop de                         ; slot base
    ld h, d
    ld l, e
    ld bc, SAVE_DATA_START
    add hl, bc
    ld c, SAVE_DATA_LEN
    xor a
.sum
    add a, [hl]
    inc hl
    dec c
    jr nz, .sum
    ld hl, SAVE_F_CSUM
    add hl, de                     ; checksum lives at base + SAVE_F_CSUM
    ld [hl], a
    ld a, [wSaveSeq]               ; roll the sequence and the slot
    inc a
    ld [wSaveSeq], a
    ld a, [wSaveSlot]
    xor 1
    ld [wSaveSlot], a
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

; in: hl = slot base; out: a = 1 iff magic+version+checksum pass.
; clobbers a, c, h, l
ValidateSlot:
    push hl
    ld a, [hli]
    cp SAVE_MAGIC_0
    jr nz, .bad
    ld a, [hli]
    cp SAVE_MAGIC_1
    jr nz, .bad
    ld a, [hli]
    cp SAVE_VERSION
    jr nz, .bad
    inc hl                         ; checksum byte
    inc hl                         ; sequence byte -> hl = base + SAVE_DATA_START
    ld c, SAVE_DATA_LEN
    xor a
.sum
    add a, [hl]
    inc hl
    dec c
    jr nz, .sum
    pop hl
    push hl
    inc hl
    inc hl
    inc hl                         ; stored checksum at base + SAVE_F_CSUM
    cp [hl]
    jr nz, .bad
    pop hl
    ld a, 1
    ret
.bad
    pop hl
    xor a
    ret

; Validate both slots and load the newest valid one. Sets wHasSave (1 =
; loaded). Called at boot.
LoadGame::
    ld a, $0A
    ld [$0000], a
    ld hl, $A000
    call ValidateSlot
    ld [wSlot0Ok], a
    ld hl, SAVE_SLOT1
    call ValidateSlot
    ld [wSlot1Ok], a
    ld a, [wSlot0Ok]
    and a
    jr z, .noSlot0
    ld a, [wSlot1Ok]
    and a
    jr z, .slot0                   ; only slot 0 is good
    ld a, [SAVE_SLOT1 + SAVE_F_SEQ] ; both good: the higher sequence wins
    ld hl, $A000 + SAVE_F_SEQ
    sub [hl]                       ; seq1 - seq0 (8-bit; wraps at 256)
    jr z, .slot0
    bit 7, a                       ; negative: slot 0 is newer
    jr z, .slot1
.slot0
    ld de, $A000
    xor a
    jr .load
.noSlot0
    ld a, [wSlot1Ok]
    and a
    jp z, .fail                    ; the copy block pushed .fail past jr range
.slot1
    ld de, SAVE_SLOT1
    ld a, 1
.load
    xor 1
    ld [wSaveSlot], a              ; next save goes to the other slot
    ld h, d
    ld l, e
    ld bc, SAVE_F_SEQ
    add hl, bc
    ld a, [hl]                     ; sequence byte
    ld [wSaveSeq], a
    inc hl                         ; data starts at base + SAVE_DATA_START
    ; load fields (hl walks the data; runs mirror SaveGame)
    ld de, wSeed
    ld b, SAVE_F_POS - SAVE_F_SEED
    call CopyFromSRAM
    ld de, wPosX
    ld b, SAVE_F_ECON - SAVE_F_POS
    call CopyFromSRAM
    ld de, wGold
    ld b, SAVE_F_EXPLORED - SAVE_F_ECON
    call CopyFromSRAM
    ld de, wExplored
    ld b, SAVE_F_LASTPORT - SAVE_F_EXPLORED
    call CopyFromSRAM
    ld de, wLastPortDX
    ld b, SAVE_F_MASKS - SAVE_F_LASTPORT
    call CopyFromSRAM
    ld de, wFragMask
    ld b, SAVE_F_FINAL - SAVE_F_MASKS
    call CopyFromSRAM
    ld de, wFinal
    ld b, SAVE_F_PORTCELLS - SAVE_F_FINAL
    call CopyFromSRAM
    ld de, wPortCells
    ld b, SAVE_F_BESTGOLD - SAVE_F_PORTCELLS
    call CopyFromSRAM
    ld de, wBestGold
    ld b, SAVE_F_CARTDONE - SAVE_F_BESTGOLD
    call CopyFromSRAM
    ld de, wCartDone
    ld b, SAVE_F_UPGRADES - SAVE_F_CARTDONE
    call CopyFromSRAM
    ld de, wHullMax
    ld b, SAVE_REC_SIZE - SAVE_F_UPGRADES
    call CopyFromSRAM
    call FoldSeed16                ; wSeed16 first: ComputeIsles hashes with it
    call ComputeIsles              ; isles are derived, never saved
    call CountFrags                ; rebuild the cached fragment count
    ld [wFragCount], a
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

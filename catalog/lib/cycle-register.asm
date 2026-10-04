; Shared body for tests that change one CRTC register on every raster
; interrupt. The including file defines CYCLE_REG (register number) and a
; 6-byte table CYCLE_VALUES; value 0 is used by the interrupt that falls
; inside VSYNC, then 1-5 for the following interrupts. Include it from a
; test's src/test.asm (pasmo resolves includes from the working directory).
include "../../../lib/prelude.asm"   ; relative to the including test.asm

CYCLE_IDX equ 0A000h

irq_handler:
        push af
        push bc
        push hl
        ld b,0F5h
        in a,(c)
        rra
        ld a,(CYCLE_IDX)
        jr nc,cy_go
        xor a
cy_go:
        ld l,a
        inc a
        cp 6
        jr c,cy_st
        xor a
cy_st:
        ld (CYCLE_IDX),a
        ld h,0
        ld bc,CYCLE_VALUES
        add hl,bc
        ld bc,0BC00h + CYCLE_REG
        out (c),c
        ld b,0BDh
        ld a,(hl)
        out (c),a
        pop hl
        pop bc
        pop af
        ei
        ret

main:
        call fill_pattern
        xor a
        ld (CYCLE_IDX),a
        ei
cy_loop:
        halt
        jr cy_loop

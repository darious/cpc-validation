; Changes R8 on every raster interrupt: display skew 0, 1 and 2 characters
; (bits 4-5) and display disabled (bits 4-5 = 11).
; CRTC types handle R8 differently (type 1 ignores skew and disable).
include "../../../lib/prelude.asm"

IDX equ 0A000h

irq_handler:
        push af
        push bc
        push hl
        ld b,0F5h
        in a,(c)
        rra
        ld a,(IDX)
        jr nc,r8_go
        xor a
r8_go:
        ld l,a
        inc a
        cp 6
        jr c,r8_st
        xor a
r8_st:
        ld (IDX),a
        ld h,0
        ld bc,VALUES
        add hl,bc
        ld bc,0BC08h
        out (c),c
        ld b,0BDh
        ld a,(hl)
        out (c),a
        pop hl
        pop bc
        pop af
        ei
        ret

VALUES: db 000h,010h,020h,030h,000h,020h

main:
        call fill_pattern
        xor a
        ld (IDX),a
        ei
r8_loop:
        halt
        jr r8_loop

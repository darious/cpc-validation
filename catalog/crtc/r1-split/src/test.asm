; Changes R1 (displayed characters per line) on every raster interrupt:
; 40, 32, 48, 24, 40, 36. R1 sets both the border position and how far the
; memory address advances per character row (latched on each row's last
; scanline), so the picture shears where the value changes.
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
        jr nc,r1_go
        xor a
r1_go:
        ld l,a
        inc a
        cp 6
        jr c,r1_st
        xor a
r1_st:
        ld (IDX),a
        ld h,0
        ld bc,WIDTHS
        add hl,bc
        ld bc,0BC01h
        out (c),c
        ld b,0BDh
        ld a,(hl)
        out (c),a
        pop hl
        pop bc
        pop af
        ei
        ret

WIDTHS: db 40,32,48,24,40,36

main:
        call fill_pattern
        xor a
        ld (IDX),a
        ei
r1_loop:
        halt
        jr r1_loop

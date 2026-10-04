; Short VSYNC (R3=&28) variant of hardware/interrupt-bands.
; IM 1 handler changes the border colour on every raster interrupt, cycling
; through six colours and restarting on the interrupt that falls inside
; VSYNC. The main loop is HALT. Validates the Gate Array interrupt counter,
; the VSYNC resynchronisation, interrupt acknowledge and HALT timing.
include "../../../lib/prelude.asm"

COLOURS equ 0A000h              ; index at COLOURS, table follows

irq_handler:
        push af
        push bc
        push hl
        ld b,0F5h
        in a,(c)
        rra
        ld a,(COLOURS)
        jr nc,ib_next
        xor a                   ; interrupt during VSYNC: restart the cycle
ib_next:
        ld l,a
        inc a
        cp 6
        jr c,ib_store
        xor a
ib_store:
        ld (COLOURS),a
        ld h,0
        ld bc,TABLE
        add hl,bc
        ld bc,07F10h
        out (c),c
        ld a,(hl)
        out (c),a
        pop hl
        pop bc
        pop af
        ei
        ret

TABLE:  db 054h,04Bh,04Ch,052h,055h,04Ah

main:
        ld bc,0BC03h            ; R3 = &28: VSYNC 2 lines (types 0, 3, 4), HSYNC 8
        out (c),c
        ld bc,0BD28h
        out (c),c
        call fill_pattern
        xor a
        ld (COLOURS),a
        ei
mb_loop:
        halt
        jr mb_loop

; Screen mode changes on every raster interrupt (0, 1, 2, 3, 1, 2), with a
; pattern filling the screen. Mode changes take effect at the next HSYNC,
; so the band boundaries test where the Gate Array latches the mode. The
; border changes at the same time to mark each interrupt.
include "../../../lib/prelude.asm"

STATE equ 0A000h

irq_handler:
        push af
        push bc
        push hl
        ld b,0F5h
        in a,(c)
        rra
        ld a,(STATE)
        jr nc,ms_next
        xor a
ms_next:
        ld l,a
        inc a
        cp 6
        jr c,ms_store
        xor a
ms_store:
        ld (STATE),a
        ld h,0
        ld bc,MODES
        add hl,bc
        ld a,(hl)
        ld b,07Fh
        out (c),a               ; MRER: mode, lower ROM on, upper off
        ld c,010h
        out (c),c               ; border
        and 3
        add a,054h - 0          ; 54/55/56/57: black/blue/green/sky blue
        out (c),a
        pop hl
        pop bc
        pop af
        ei
        ret

MODES:  db 088h,089h,08Ah,08Bh,089h,08Ah

main:
        call fill_pattern
        xor a
        ld (STATE),a
        ei
ms_loop:
        halt
        jr ms_loop

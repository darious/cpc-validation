; Scans all ten keyboard lines continuously into RESULTS (one byte per
; line). The manifest's input script holds a set of keys down, so the final
; scan shows which matrix positions each key name maps to.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
km_scan:
        ld hl,RESULTS
        ld d,040h               ; PSG read + keyboard line 0
        ld a,14
        ld b,0F4h
        out (c),a
        ld bc,0F6C0h            ; latch register 14
        out (c),c
        ld c,0
        out (c),c
        ld bc,0F792h            ; port A input
        out (c),c
km_line:
        ld b,0F6h
        out (c),d               ; PSG read, select line
        ld b,0F4h
        in a,(c)
        ld (hl),a
        inc hl
        inc d
        ld a,d
        cp 04Ah
        jr nz,km_line
        ld bc,0F600h
        out (c),c
        ld bc,0F782h
        out (c),c
        jr km_scan

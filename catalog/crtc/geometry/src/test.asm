; Non-standard character geometry: 4-line characters (R9=3), 77 rows plus 4
; vertical-adjust lines (R4=76, R5=4: still 312 lines), a narrower display
; (R1=32), moved HSYNC (R2=44) and a start address offset (R13=&10).
; Validates the row/raster counters, vertical adjust and address counting.
include "../../../lib/prelude.asm"
include "../../../lib/crtc.asm"

irq_handler:
        ret

main:
        call fill_pattern
        ld hl,REGS
        call set_crtc
cg_loop:
        jr cg_loop

REGS:   db 9,3, 4,76, 5,4, 6,50, 7,60, 1,32, 2,44, 13,010h, 0FFh

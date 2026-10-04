; Reads the PPI ports in various configurations: port B (VSYNC and the
; distributor/refresh/expansion/printer/cassette inputs), port C after
; writes and bit set/reset commands, port A in output mode, and the effect
; of a mode-set command on the output latches. Results at RESULTS.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        ld hl,RESULTS
        call wait_vsync
        in a,(c)                ; port B during VSYNC
        ld (hl),a
        inc hl
        call wait_vsync
        ld e,0
pp_wait:                        ; leave VSYNC
        dec e
        jr nz,pp_wait
        ld b,0F5h
        in a,(c)                ; port B outside VSYNC
        ld (hl),a
        inc hl
        ld bc,0F65Ah            ; port C = &5A (keyboard line 10, motor on)
        out (c),c
        in a,(c)
        ld (hl),a
        inc hl
        ld bc,0F70Fh            ; set bit 7 of port C
        out (c),c
        ld bc,0F608h            ; bit set/reset: clear bit 4 (&08)
        ld b,0F7h
        out (c),c
        ld b,0F6h
        in a,(c)
        ld (hl),a
        inc hl
        ld bc,0F4A5h            ; port A output latch
        out (c),c
        in a,(c)
        ld (hl),a
        inc hl
        ld bc,0F782h            ; mode set clears the output latches
        out (c),c
        ld b,0F4h
        in a,(c)
        ld (hl),a
        inc hl
        ld b,0F6h
        in a,(c)
        ld (hl),a
        inc hl
pp_done:
        jr pp_done

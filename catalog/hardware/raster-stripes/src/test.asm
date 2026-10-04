; Border colour changes at fixed microsecond offsets on every line, with
; the display disabled (R6=0) so the whole frame is border. Validates when
; OUT (C),r reaches the Gate Array inside the instruction.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        ld bc,0BC06h            ; R6 = 0: no display rows
        out (c),c
        ld bc,0BD00h
        out (c),c
        ld d,054h               ; black
        ld e,04Bh               ; white
        ld h,04Ch               ; red
        ld l,052h               ; green
frame:
        call sync_irq
        ld bc,07F10h            ; select the border
        out (c),c
        xor a                   ; 256 lines
line:                           ; exactly 64 us per iteration
        out (c),d               ; 4
        out (c),e               ; 8
        nop                     ; 9
        out (c),h               ; 13
        nop                     ; 14
        nop                     ; 15
        out (c),l               ; 19
        nop                     ; 20
        nop                     ; 21
        nop                     ; 22
        out (c),d               ; 26
        out (c),e               ; 30
        out (c),h               ; 34
        out (c),l               ; 38
        nop                     ; 39
        nop                     ; 40
        nop                     ; 41
        nop                     ; 42
        out (c),d               ; 46
        out (c),e               ; 50
        nop                     ; 51
        nop                     ; 52
        nop                     ; 53
        nop                     ; 54
        nop                     ; 55
        nop                     ; 56
        out (c),h               ; 60
        dec a                   ; 61
        jp nz,line              ; 64
        jr frame

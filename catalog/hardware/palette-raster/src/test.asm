; Changes the colour of pen 1 at fixed points inside every line while the
; display shows a pattern using pens 0-3, then a second block changes pen 0
; with LD/OUT sequences of different lengths. Validates palette writes in
; the middle of displayed characters.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        call fill_pattern
        ld d,04Ch               ; red
        ld e,052h               ; green
        ld h,04Eh               ; orange
        ld l,05Fh               ; pastel blue
frame:
        call sync_irq
        ld bc,07F01h            ; select pen 1
        out (c),c
        ld a,128
p1_line:                        ; 64 us per iteration
        out (c),d               ; 4
        nop                     ; 5
        out (c),e               ; 9
        nop                     ; 10
        nop                     ; 11
        out (c),h               ; 15
        nop                     ; 16
        nop                     ; 17
        nop                     ; 18
        out (c),l               ; 22
        out (c),d               ; 26
        out (c),e               ; 30
        nop                     ; 31
        nop                     ; 32
        out (c),h               ; 36
        nop                     ; 37
        out (c),l               ; 41
        nop                     ; 42
        nop                     ; 43
        nop                     ; 44
        nop                     ; 45
        nop                     ; 46
        nop                     ; 47
        nop                     ; 48
        out (c),d               ; 52
        nop                     ; 53
        nop                     ; 54
        nop                     ; 55
        nop                     ; 56
        out (c),e               ; 60
        dec a                   ; 61
        jp nz,p1_line           ; 64
        ld c,0                  ; select pen 0
        out (c),c
        ld a,100
p0_line:                        ; 64 us per iteration
        ld c,04Bh               ; 2
        out (c),c               ; 6
        ld c,054h               ; 8
        out (c),c               ; 12
        ld c,04Ah               ; 14
        out (c),c               ; 18
        nop                     ; 19
        ld c,054h               ; 21
        out (c),c               ; 25
        ld c,05Ch               ; 27
        out (c),c               ; 31
        nop                     ; 32
        nop                     ; 33
        ld c,054h               ; 35
        out (c),c               ; 39
        ld c,046h               ; 41
        out (c),c               ; 45
        nop                     ; 46
        nop                     ; 47
        nop                     ; 48
        ld c,054h               ; 50
        out (c),c               ; 54
        nop                     ; 55
        nop                     ; 56
        nop                     ; 57
        nop                     ; 58
        nop                     ; 59
        nop                     ; 60
        dec a                   ; 61
        jp nz,p0_line           ; 64
        ld bc,07F00h            ; restore pen 0 to black
        out (c),c
        ld c,054h
        out (c),c
        jp frame

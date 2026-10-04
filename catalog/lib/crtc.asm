; set_crtc: program CRTC registers from a table of (register, value) pairs
; ending with &FF. HL = table. Corrupts A, BC, HL.
set_crtc:
        ld a,(hl)
        cp 0FFh
        ret z
        ld b,0BCh
        out (c),a
        inc hl
        ld a,(hl)
        inc hl
        ld b,0BDh
        out (c),a
        jr set_crtc

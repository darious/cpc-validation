; Vertical rupture: each 312-line refresh is two CRTC frames. Frame A
; (R4=19: 160 lines, screen at &C000, no VSYNC) is followed by frame B
; (R4=18: 152 lines, screen at &8000, VSYNC on its row 10). Every refresh
; the main loop synchronises on VSYNC (V), resets the Gate Array interrupt
; counter so that interrupts fall at V+54, V+106, V+158, V+210, V+262, and
; writes each register where the right frame latches it:
;   V      R7=127 (no VSYNC in A), R12/R13 = A   (B is running)
;   V+106  R4=19, R12/R13 = B                     (A started at V+72)
;   V+210  R7=10                                  (A is past its row 10;
;                                                  writing it while A is on
;                                                  row 10 would start VSYNC)
;   V+262  R4=18                                  (B started at V+232)
; Validates the CRTC register latching rules.
include "../../../lib/prelude.asm"
include "../../../lib/crtc.asm"

irq_handler:
        ret                     ; interrupts stay disabled until the next EI

main:
        ld sp,07E00h
        call fill_pattern       ; screen A at &C000
        ld hl,08000h            ; screen B at &8000: blocks
ru_fill:
        ld a,h
        and 007h
        add a,a
        add a,a
        add a,a
        xor l
        and 0F0h
        ld (hl),a
        inc hl
        ld a,h
        cp 0C0h
        jr nz,ru_fill
        ld hl,R_INIT
        call set_crtc
refresh:
        call wait_vsync
        ld hl,R_V0
        call set_crtc
        ld bc,07F99h            ; reset the interrupt counter
        out (c),c
        ei
        halt                    ; V+54
        ei
        halt                    ; V+106
        ld hl,R_V106
        call set_crtc
        ei
        halt                    ; V+158
        ei
        halt                    ; V+210
        ld hl,R_V210
        call set_crtc
        ei
        halt                    ; V+262
        ld hl,R_V262
        call set_crtc
        jr refresh

R_INIT: db 6,19, 0FFh
R_V0:   db 7,127, 12,030h, 13,0, 0FFh
R_V106: db 4,19, 12,020h, 13,0, 0FFh
R_V210: db 7,10, 0FFh
R_V262: db 4,18, 0FFh

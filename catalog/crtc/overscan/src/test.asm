; A 32K overscan screen: R1=48, R2=50, R6=34, R7=35 with R12 bits 2-3 set so
; the memory address carries from &8000-&BFFF into &C000-&FFFF. Memory is
; filled with a pattern. Validates MA generation, the 16K page carry, and
; display/border/sync positions for a non-standard geometry.
include "../../../lib/prelude.asm"
include "../../../lib/crtc.asm"

irq_handler:
        ret

main:
        ld hl,08000h            ; fill &8000-&FFFF
os_fill:
        ld a,l
        rrca
        rrca
        xor h
        ld (hl),a
        inc hl
        ld a,h
        or a
        jr nz,os_fill
        ld hl,REGS
        call set_crtc
os_loop:
        jr os_loop

REGS:   db 1,48, 2,50, 6,34, 7,35, 12,02Ch, 13,0, 0FFh

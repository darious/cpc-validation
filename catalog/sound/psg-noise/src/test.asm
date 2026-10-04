; Noise only, on channel C (right) with noise period 16, and a 500 Hz tone
; on channel A (left). The noise level changes about 1e6/(16*16) times a
; second; the verdict compares the rate of its zero crossings.
;
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        ld hl,REGS
pt_loop:
        ld a,(hl)
        cp 0FFh
        jr z,pt_done
        inc hl
        ld e,(hl)
        inc hl
        push hl
        call psg_write
        pop hl
        jr pt_loop
pt_done:
        jr pt_done

;       register, value
REGS:   db 0,125, 1,0           ; A period 125 (500 Hz)
        db 6,16                 ; noise period 16
        db 8,15, 9,0, 10,15     ; volumes A, B, C
        db 7,01Eh               ; tone A and noise C on, everything else off
        db 0FFh

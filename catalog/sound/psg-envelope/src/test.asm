; Channel A plays a 3125 Hz tone (period 20) with its amplitude driven by
; the envelope generator: repeating sawtooth (shape 12) with period 200,
; i.e. one ramp every 256*200 us (~19.5 Hz). Channel C plays a noise-gated
; tone at a fixed volume. Checks envelope timing and the tone under it.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        ld hl,REGS
pe_loop:
        ld a,(hl)
        cp 0FFh
        jr z,pe_done
        inc hl
        ld e,(hl)
        inc hl
        push hl
        call psg_write
        pop hl
        jr pe_loop
pe_done:
        jr pe_done

REGS:   db 0,20, 1,0            ; A period 20
        db 4,125, 5,0           ; C period 125 (500 Hz)
        db 6,31                 ; noise period
        db 11,200, 12,0         ; envelope period 200
        db 13,12                ; repeating sawtooth up
        db 8,16, 9,0, 10,0      ; A follows the envelope, B and C silent
        db 7,03Eh               ; tone A only
        db 0FFh

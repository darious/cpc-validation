; Programs the PSG directly: channel A 250 Hz (period 250) at volume 15,
; channel C ~992 Hz (period 63) at volume 12, channel B silent (volume 0),
; noise off. The CPC mixes A to the left and C to the right, so audio.wav
; should carry 250 Hz on the left and ~992 Hz on the right.
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
REGS:   db 0,250, 1,0           ; A period 250
        db 2,0F4h, 3,1          ; B period 500
        db 4,63, 5,0            ; C period 63
        db 8,15, 9,0, 10,12     ; volumes A, B, C
        db 7,03Ah               ; tones A and C on, B off, noise off
        db 0FFh

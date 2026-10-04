; Writes &FF and then &00 to every PSG register and reads each back through
; the PPI, storing 16 bytes per pass at RESULTS and RESULTS+16. Register 14
; is read in input mode (keyboard line 15: no keys) and, at RESULTS+32, in
; output mode (R7 bit 6 set). Validates register masks and the PSG bus
; protocol through the PPI.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        ld e,0FFh
        ld hl,RESULTS
        call write_read
        ld e,0
        ld hl,RESULTS+16
        call write_read
        ; R7 bit 6 set: port A output, R14 reads back its latch
        ld a,14
        ld e,05Ah
        call psg_write
        ld a,7
        ld e,07Fh
        call psg_write
        ld a,14
        call psg_read
        ld (RESULTS+32),a
        ld a,15
        call psg_read
        ld (RESULTS+33),a
pr_done:
        jr pr_done

write_read:                     ; write E to R0-R15 then read them into (HL)
        xor a
wr_w:
        push af
        cp 7
        jr nz,wr_w2
        push de
        ld e,03Fh               ; keep R7 port A as input (bit 6 clear)
        call psg_write
        pop de
        jr wr_w3
wr_w2:
        call psg_write
wr_w3:
        pop af
        inc a
        cp 16
        jr nz,wr_w
        xor a
wr_r:
        push af
        call psg_read
        ld (hl),a
        inc hl
        pop af
        inc a
        cp 16
        jr nz,wr_r
        ret

psg_read:                       ; read PSG register A into A; keyboard line 15
        ld b,0F4h
        out (c),a
        ld bc,0F6CFh            ; latch address, keyboard line 15
        out (c),c
        ld c,00Fh
        out (c),c
        ld bc,0F792h            ; port A input
        out (c),c
        ld bc,0F64Fh            ; PSG read
        out (c),c
        ld b,0F4h
        in a,(c)
        ld bc,0F60Fh
        out (c),c
        ld bc,0F782h            ; port A output again
        out (c),c
        ret

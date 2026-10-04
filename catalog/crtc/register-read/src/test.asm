; Writes distinct values to R12 and R13, then reads each of
; registers 0-31 through the register port (&BFxx) and the status port
; (&BExx). Results: 32 bytes from &BFxx then 32 from &BExx at RESULTS, and
; again with the display in the vertical border at RESULTS+64. Readable
; registers and the status port differ between CRTC types.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        ; write R12-R13 (R0-R11 keep the standard screen running; R14-R17
        ; are left alone: R16/R17 are read-only light pen registers)
        ld a,12
rr_write:
        ld b,0BCh
        out (c),a
        ld b,0BDh
        ld e,a
        sla e
        sla e
        sla e
        sla e
        add a,e                 ; value = r*17
        out (c),a
        sub e
        inc a
        cp 14
        jr nz,rr_write

        call wait_vsync         ; in VSYNC (vertical border)
        ld hl,RESULTS+64
        call read_all
        call wait_vsync         ; wait until the display area
        ld bc,0F5FFh
        ld e,100
rr_delay:                       ; ~ 100 lines into the frame
        ld d,13
rr_d2:
        dec d
        jr nz,rr_d2
        dec e
        jr nz,rr_delay
        ld hl,RESULTS
        call read_all
rr_done:
        jr rr_done

read_all:                       ; HL = destination
        push hl
        xor a
ra_bf:
        ld b,0BCh
        out (c),a
        ld b,0BFh
        in e,(c)
        ld (hl),e
        inc hl
        inc a
        cp 32
        jr nz,ra_bf
        pop hl
        ld de,32
        add hl,de
        xor a
ra_be:
        ld b,0BCh
        out (c),a
        ld b,0BEh
        in e,(c)
        ld (hl),e
        inc hl
        inc a
        cp 32
        jr nz,ra_be
        ret

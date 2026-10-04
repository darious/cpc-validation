; Writes a marker through every 16K slot in each of the eight RAM
; configurations (&C0-&C7) and leaves the physical RAM for the verdicts:
; in configuration c the byte c*16+slot goes to slot*&4000 + &100 + c*4 +
; slot. On a 6128 the markers land in the banks the configuration maps; on a
; 64K machine the configuration writes are ignored. Code runs from the ROM
; and uses no stack while a configuration other than 0 is selected.
include "../../../lib/prelude.asm"

irq_handler:
        ret

main:
        ; clear &100-&11F in banks 0-3 (config 0) and 4-7 (config 2)
        ld bc,07FC0h
        out (c),c
        call clear_slots
        ld bc,07FC2h
        out (c),c
        call clear_slots
        ld bc,07FC0h
        out (c),c

        ld d,0                  ; configuration
rb_config:
        ld a,d
        or 0C0h
        ld b,07Fh
        out (c),a
        ld a,d                  ; offset = &100 + c*4
        add a,a
        add a,a
        ld l,a
        ld e,0                  ; slot
rb_slot:
        ld a,e                  ; H = slot*&40 + 1
        rrca
        rrca
        or 001h
        ld h,a
        push hl                 ; (stack is in bank 2/6 - not checked)
        ld a,l
        add a,e
        ld l,a
        ld a,d                  ; marker = c*16 + slot
        add a,a
        add a,a
        add a,a
        add a,a
        add a,e
        ld (hl),a
        pop hl
        inc e
        ld a,e
        cp 4
        jr nz,rb_slot
        inc d
        ld a,d
        cp 8
        jr nz,rb_config
        ld bc,07FC0h
        out (c),c
rb_done:
        jr rb_done

clear_slots:                    ; clear &x100-&x11F in all four slots
        ld a,001h
cs_slot:
        ld h,a
        ld l,0
        ld b,020h
cs_byte:
        ld (hl),0
        inc l
        djnz cs_byte
        add a,040h
        cp 001h
        jr nz,cs_slot
        ret

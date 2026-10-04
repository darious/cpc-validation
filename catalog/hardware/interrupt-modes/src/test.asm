; Interrupt response in IM 1, IM 2 and IM 0. For each mode the main loop
; counts (INC DE) between raster interrupts; the handler stores the count
; and restarts it. The counts depend on the response time of each mode and
; on IM 2 fetching its vector from (I*256 + &FF), the CPC's floating data
; bus value; IM 0 executes that &FF as RST &38. Results: 4 counts per mode
; (IM 1, IM 2, IM 0) as 16-bit words at RESULTS.
include "../../../lib/prelude.asm"

COUNT   equ 0A000h              ; interrupts handled in this mode
OUTPTR  equ 0A002h              ; where the next count goes

irq_handler:
        push af
        push hl
        ld hl,(OUTPTR)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (OUTPTR),hl
        ld de,0
        ld hl,COUNT
        inc (hl)
        pop hl
        pop af
        ei
        ret

main:
        ld hl,RESULTS
        ld (OUTPTR),hl
        ld hl,irq_handler       ; IM 2 vector at &40FF
        ld (040FFh),hl
        ld a,040h
        ld i,a

        im 1
        call measure
        im 2
        call measure
        im 0
        call measure
im_done:
        jr im_done

measure:                        ; discard the first count, keep 4
        xor a
        ld (COUNT),a
        call wait_vsync
        ld bc,07F99h            ; reset the interrupt counter
        out (c),c
        ld de,0
        ei
        halt                    ; first interrupt: count starts from here
        ld hl,(OUTPTR)
        dec hl
        dec hl
        ld (OUTPTR),hl          ; overwrite the partial count
        xor a
        ld (COUNT),a
ms_loop:
        inc de
        ld a,(COUNT)
        cp 4
        jr nz,ms_loop
        di
        ret

; Common start-up code for direct-boot test ROMs (assembled with pasmo).
;
; A test ROM replaces the lower (OS) ROM through the runner's --rom option
; and runs from reset without any firmware. The prelude brings the hardware
; into a known state, independent of each emulator's power-on defaults:
;   - interrupts disabled, IM 1, SP = &C000
;   - Gate Array: mode 1, lower ROM on, upper ROM off, RAM configuration 0
;   - palette: border blue, pens 0-15 set from PALETTE below
;   - CRTC: the firmware's standard 50 Hz screen at &C000
;   - PPI: port A output, port C output; PSG silent
;   - screen memory &C000-&FFFF cleared
; then jumps to MAIN, which the test defines.
;
; Results conventionally go to RESULTS (&9000) so manifests can check them
; with ram_bytes verdicts.

RESULTS equ 09000h

        org 0
        di
        im 1
        jp prelude

        org 038h
        jp irq_handler          ; tests define irq_handler (or leave the RET)

        org 040h
prelude:
        ld sp,0C000h
        ld bc,07F00h + 089h     ; MRER: mode 1, lower ROM on, upper ROM off
        out (c),c
        ld c,0C0h               ; RAM configuration 0
        out (c),c

        ; palette: pen 0-15 then border
        ld hl,PALETTE
        xor a
pal_loop:
        out (c),a               ; select pen
        ld e,(hl)
        out (c),e               ; set ink
        inc hl
        inc a
        cp 17
        jr nz,pal_loop

        ; CRTC registers 0-15
        ld hl,CRTC_STD
        xor a
crtc_loop:
        ld b,0BCh
        out (c),a
        ld b,0BDh
        ld e,(hl)
        out (c),e
        inc hl
        inc a
        cp 16
        jr nz,crtc_loop

        ; PPI: port A out, B in, C out; then silence the PSG (R7 = &3F)
        ld bc,0F782h
        out (c),c
        ld a,7
        ld e,03Fh
        call psg_write

        ; clear the screen
        ld hl,0C000h
        ld de,0C001h
        ld bc,03FFFh
        ld (hl),0
        ldir

        jp main

; psg_write: write E to PSG register A (PPI port A must be an output)
psg_write:
        ld b,0F4h
        out (c),a               ; register number on port A
        ld bc,0F6C0h            ; latch address
        out (c),c
        ld c,0
        out (c),c               ; inactive
        ld b,0F4h
        out (c),e               ; data on port A
        ld bc,0F680h            ; write
        out (c),c
        ld c,0
        out (c),c               ; inactive
        ret

; wait_vsync: return just after the start of VSYNC. Corrupts A and B.
wait_vsync:
        ld b,0F5h
wv_high:
        in a,(c)
        rra
        jr c,wv_high            ; wait while VSYNC is active
wv_low:
        in a,(c)
        rra
        jr nc,wv_low            ; wait for VSYNC to start
        ret

;             0    1    2    3    4    5    6    7    8    9   10   11   12   13   14   15  border
PALETTE: db 054h,04Bh,04Ch,052h,04Ah,043h,055h,05Ch,046h,057h,05Eh,040h,04Eh,047h,05Bh,04Dh,044h

;             R0  R1  R2   R3  R4 R5  R6  R7 R8 R9 R10 R11  R12 R13 R14 R15
CRTC_STD: db  63, 40, 46, 08Eh, 38, 0, 25, 30, 0, 7,  0,  0, 030h, 0,  0,  0

; sync_irq: wait for a fixed raster position. Waits for VSYNC, resets the Gate
; Array interrupt counter, then halts until the interrupt 52 lines later.
; The test's irq_handler must return with interrupts disabled (plain RET) or
; re-enable them itself. Corrupts A and BC.
sync_irq:
        call wait_vsync
        ld bc,07F99h            ; MRER mode 1, lower ROM on, upper off, reset counter
        out (c),c
        ei
        halt
        ret

; fill_pattern: fill &C000-&FFFF with the low byte of each address XOR
; (address >> 8), a pattern that differs on every line and column.
fill_pattern:
        ld hl,0C000h
fp_loop:
        ld a,l
        xor h
        ld (hl),a
        inc hl
        ld a,h
        or a
        jr nz,fp_loop
        ret

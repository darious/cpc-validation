; Drives the uPD765 directly with a table of commands and records every
; result byte (each command's results start with an &EE marker) at RESULTS
; and all data read in execution phases from &4000. The disk is
; fixtures/fdc-test.dsk (scripts/make-fdc-test-dsk.py): normal tracks 0-4
; and a track 5 with a mismatched ID, a 256-byte sector, a deleted-data
; sector and a CRC-error sector. Covers SPECIFY, RECALIBRATE, SEEK, SENSE
; INTERRUPT STATUS, SENSE DRIVE STATUS, READ ID, READ DATA, READ DELETED
; DATA, WRITE DATA, FORMAT TRACK and an invalid command.
include "../../../lib/prelude.asm"

DATA    equ 04000h
WRBUF   equ 08000h
MODE    equ 0A000h

irq_handler:
        ret

main:
        ld hl,RESULTS           ; clear results, data and write buffer
        ld de,RESULTS+1
        ld bc,007FFh
        ld (hl),0
        ldir
        ld hl,DATA
        ld de,DATA+1
        ld bc,01FFFh
        ld (hl),0
        ldir
        ld hl,WRBUF             ; write buffer pattern: i*5+1
        ld de,512
        ld a,1
wb_fill:
        ld (hl),a
        add a,5
        inc hl
        dec de
        ld b,a
        ld a,d
        or e
        ld a,b
        jr nz,wb_fill

        ld bc,0FA7Eh            ; drive motor on, then wait about a second
        ld a,1
        out (c),a
        ld c,2
mo_delay:
        ld de,0
mo_d2:
        dec de
        ld a,d
        or e
        jr nz,mo_d2
        dec c
        jr nz,mo_delay

        ld ix,RESULTS
        ld hl,DATA
        ld iy,CMDS
next_cmd:
        ld a,(iy+0)
        or a
        jr z,all_done
        ld d,a                  ; number of command bytes
        ld a,(iy+1)
        ld (MODE),a
        inc iy
        inc iy
        ld (ix+0),0EEh
        inc ix
send_loop:
        ld a,(iy+0)
        inc iy
        call fdc_send
        dec d
        jr nz,send_loop
        ld a,(MODE)
        or a
        jr z,results
        cp 3
        jr z,next_cmd           ; no result phase
        cp 1
        jr nz,cmd_write
        call fdc_exec_read
        jr results
cmd_write:
        ld de,WRBUF
        cp 2
        jr z,cmd_w2
        ld de,FMTIDS
cmd_w2:
        call fdc_exec_write
results:
        call fdc_results
        jr next_cmd
all_done:
        ld bc,0FA7Eh            ; motor off
        xor a
        out (c),a
fd_done:
        jr fd_done

fdc_send:                       ; send A to the FDC data register
        push bc
        push af
        ld bc,0FB7Eh
fs_wait:
        in a,(c)
        jp p,fs_wait            ; wait for RQM
        pop af
        inc c
        out (c),a
        pop bc
        ret

fdc_exec_read:                  ; read execution-phase bytes to (HL)
        ld bc,0FB7Eh
fer_wait:
        in a,(c)
        jp p,fer_wait
        and 020h                ; still in execution phase?
        ret z
        inc c
        in a,(c)
        dec c
        ld (hl),a
        inc hl
        jr fer_wait

fdc_exec_write:                 ; send execution-phase bytes from (DE)
        ld bc,0FB7Eh
few_wait:
        in a,(c)
        jp p,few_wait
        and 020h
        ret z
        inc c
        ld a,(de)
        out (c),a
        dec c
        inc de
        jr few_wait

fdc_results:                    ; read result bytes to (IX)
        ld bc,0FB7Eh
fr_wait:
        in a,(c)
        jp p,fr_wait
        and 040h                ; FDC has data for us?
        ret z
        inc c
        in a,(c)
        dec c
        ld (ix+0),a
        inc ix
        jr fr_wait

; count, mode (0 results only, 1 read data, 2 write WRBUF, 3 no results,
; 4 write format IDs), command bytes
CMDS:
        db 1,0, 008h                            ; sense interrupt: none pending
        db 3,3, 003h,0A1h,003h                  ; specify
        db 2,3, 007h,000h                       ; recalibrate drive 0
        db 1,0, 008h
        db 2,0, 00Ah,000h                       ; read ID, FM: no address mark
        db 2,0, 04Ah,000h                       ; read ID, MFM x3
        db 2,0, 04Ah,000h
        db 2,0, 04Ah,000h
        db 3,3, 00Fh,000h,002h                  ; seek track 2
        db 1,0, 008h
        db 9,1, 046h,000h,002h,000h,0C1h,002h,0C1h,02Ah,0FFh  ; read C1
        db 9,1, 046h,000h,002h,000h,055h,002h,055h,02Ah,0FFh  ; missing sector
        db 9,1, 046h,000h,002h,000h,0C3h,002h,0C5h,02Ah,0FFh  ; read C3-C5
        db 9,1, 04Ch,000h,002h,000h,0C2h,002h,0C2h,02Ah,0FFh  ; read deleted, normal sector
        db 1,0, 000h                            ; invalid command
        db 2,0, 04Ah,001h                       ; read ID drive B (empty)
        db 3,3, 00Fh,000h,005h                  ; seek track 5
        db 1,0, 008h
        db 9,1, 046h,000h,005h,000h,001h,002h,001h,02Ah,0FFh  ; R1
        db 9,1, 046h,000h,005h,000h,002h,002h,002h,02Ah,0FFh  ; R2 as C=5: no data
        db 9,1, 046h,000h,006h,000h,002h,002h,002h,02Ah,0FFh  ; R2 as C=6
        db 9,1, 046h,000h,005h,000h,003h,001h,003h,02Ah,0FFh  ; R3, 256 bytes
        db 9,1, 046h,000h,005h,000h,004h,002h,004h,02Ah,0FFh  ; R4 deleted, read data
        db 9,1, 04Ch,000h,005h,000h,004h,002h,004h,02Ah,0FFh  ; R4 read deleted
        db 9,1, 046h,000h,005h,000h,005h,002h,005h,02Ah,0FFh  ; R5 CRC error
        db 3,3, 00Fh,000h,003h                  ; seek track 3
        db 1,0, 008h
        db 9,2, 045h,000h,003h,000h,0C1h,002h,0C1h,02Ah,0FFh  ; write C1
        db 9,1, 046h,000h,003h,000h,0C1h,002h,0C1h,02Ah,0FFh  ; read it back
        db 3,3, 00Fh,000h,004h                  ; seek track 4
        db 1,0, 008h
        db 6,4, 04Dh,000h,003h,004h,050h,0AAh   ; format: 4 x 1K, filler &AA
        db 2,0, 00Ah,000h                       ; read ID, FM
        db 2,0, 04Ah,000h                       ; read ID, MFM
        db 9,1, 046h,000h,004h,000h,002h,003h,002h,02Ah,0FFh  ; read 1K sector 2
        db 2,0, 004h,000h                       ; sense drive status A
        db 2,0, 004h,001h                       ; sense drive status B (empty)
        db 0

FMTIDS: db 4,0,1,3, 4,0,2,3, 4,0,3,3, 4,0,4,3

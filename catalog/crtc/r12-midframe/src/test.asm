; Start address (R12) changed mid-frame; only some CRTC types and moments latch it.
CYCLE_REG equ 12
include "../../../lib/cycle-register.asm"

CYCLE_VALUES: db 030h,020h,030h,010h,034h,000h

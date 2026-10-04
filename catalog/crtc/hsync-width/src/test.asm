; HSYNC width (R3 low nibble) 14, 6, 4, 2, 1, 0 on successive raster interrupts: monitor position, Gate Array HSYNC length and interrupt counting (width 0 means no HSYNC on types 0/1).
CYCLE_REG equ 3
include "../../../lib/cycle-register.asm"

CYCLE_VALUES: db 08Eh,086h,084h,082h,081h,080h

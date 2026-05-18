"""Decode CPC text-mode screen RAM into ASCII rows.

The decoder reads a raw RAM dump (the contents of `ram.bin` from the runner)
plus a screen-mode hint and returns the 25 character rows visible on the
default screen. It supports mode 1 (40x25) at present; modes 0 and 2 fall
back to None.

A pixel is treated as "on" if its 2-bit (mode 1) value is non-zero, regardless
of which pen number the program selected. The 8x8 glyph signature for each
cell is looked up in GLYPHS; unknown signatures become '?'.
"""

from __future__ import annotations

from cpc_validation.glyphs import GLYPHS

DEFAULT_SCREEN_BASE = 0xC000
MODE1_COLS = 40
MODE2_COLS = 80
TEXT_ROWS = 25


def decode_screen(ram: bytes, screen_mode: int) -> list[str] | None:
    """Return 25 strings of column-count chars each, or None for unsupported modes."""
    if screen_mode == 1:
        return _decode_mode1(ram, DEFAULT_SCREEN_BASE)
    if screen_mode == 2:
        return _decode_mode2(ram, DEFAULT_SCREEN_BASE)
    return None


def decode_screen_text(ram: bytes, screen_mode: int) -> str:
    """Return the screen contents as a single newline-joined string.

    Unsupported modes yield an empty string. Trailing spaces on each line are
    stripped to make `contains` and `regex` verdicts insensitive to padding.
    """
    rows = decode_screen(ram, screen_mode)
    if rows is None:
        return ""
    return "\n".join(r.rstrip() for r in rows)


def _decode_mode1(ram: bytes, base: int) -> list[str]:
    rows: list[str] = []
    for char_row in range(TEXT_ROWS):
        line: list[str] = []
        for col in range(MODE1_COLS):
            glyph = _read_cell_mode1(ram, base, char_row, col)
            line.append(GLYPHS.get(glyph, "?"))
        rows.append("".join(line))
    return rows


def _decode_mode2(ram: bytes, base: int) -> list[str]:
    # Mode 2: 80x25 chars, 8 pixels per byte (1bpp), one byte per char cell row.
    rows: list[str] = []
    for char_row in range(TEXT_ROWS):
        line: list[str] = []
        for col in range(MODE2_COLS):
            out = bytearray(8)
            for sub in range(8):
                addr = base + sub * 0x800 + char_row * 80 + col
                if addr >= len(ram):
                    out[sub] = 0
                else:
                    out[sub] = ram[addr]
            line.append(GLYPHS.get(bytes(out), "?"))
        rows.append("".join(line))
    return rows


def _read_cell_mode1(ram: bytes, base: int, char_row: int, col: int) -> bytes:
    """Read one 8x8 cell and return its glyph signature (8 bytes, MSB first)."""
    out = bytearray(8)
    for sub in range(8):
        addr = base + sub * 0x800 + char_row * 80 + col * 2
        if addr + 2 > len(ram):
            return bytes(8)
        b0 = ram[addr]
        b1 = ram[addr + 1]
        out[sub] = _mode1_row_bits(b0, b1)
    return bytes(out)


def _mode1_row_bits(b0: int, b1: int) -> int:
    """Pack the 8 mode-1 pixels of two adjacent screen bytes into 8 bits.

    Mode 1 byte layout per pixel (4 pixels per byte):
        pixel 0: bits 7 and 3
        pixel 1: bits 6 and 2
        pixel 2: bits 5 and 1
        pixel 3: bits 4 and 0
    Any non-zero 2-bit pixel value is treated as ON.
    """
    bits = 0
    pos = 7  # MSB-first output, mirroring the GLYPHS table layout.
    for byte in (b0, b1):
        for shift_hi, shift_lo in ((7, 3), (6, 2), (5, 1), (4, 0)):
            hi = (byte >> shift_hi) & 1
            lo = (byte >> shift_lo) & 1
            on = 1 if (hi | lo) else 0
            bits |= on << pos
            pos -= 1
    return bits

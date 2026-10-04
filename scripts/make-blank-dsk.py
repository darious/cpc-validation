#!/usr/bin/env python3
"""Write a blank AMSDOS DATA-format disk image (standard CPCEMU DSK).

40 tracks, 1 side, 9 sectors of 512 bytes per track with IDs &C1-&C9 in the
usual interleaved order, every byte &E5 (an empty directory).

usage: make-blank-dsk.py OUTPUT.dsk
"""

import struct
import sys

TRACKS = 40
SECTORS = [0xC1, 0xC6, 0xC2, 0xC7, 0xC3, 0xC8, 0xC4, 0xC9, 0xC5]
SECTOR_SIZE = 512
TRACK_SIZE = 0x100 + len(SECTORS) * SECTOR_SIZE


def main() -> None:
    header = bytearray(0x100)
    header[0:34] = b"MV - CPCEMU Disk-File\r\nDisk-Info\r\n"
    header[0x22:0x30] = b"cpc-validation"
    header[0x30] = TRACKS
    header[0x31] = 1
    struct.pack_into("<H", header, 0x32, TRACK_SIZE)
    out = bytearray(header)
    for track in range(TRACKS):
        info = bytearray(0x100)
        info[0:12] = b"Track-Info\r\n"
        info[0x10] = track
        info[0x11] = 0
        info[0x14] = 2  # 512-byte sectors
        info[0x15] = len(SECTORS)
        info[0x16] = 0x4E  # GAP3
        info[0x17] = 0xE5  # filler
        for i, r in enumerate(SECTORS):
            info[0x18 + i * 8 : 0x18 + i * 8 + 4] = bytes([track, 0, r, 2])
        out += info + bytes([0xE5]) * (len(SECTORS) * SECTOR_SIZE)
    with open(sys.argv[1], "wb") as fh:
        fh.write(out)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Write the EXTENDED DSK image used by catalog/disk/fdc-commands.

Tracks 0-4: nine 512-byte sectors &C1-&C9 (interleaved), each filled with
a pattern derived from its track and sector number.
Track 5 holds unusual sectors:
  R=1 N=2  normal
  R=2 N=2  ID cylinder 6 instead of 5
  R=3 N=1  256-byte sector
  R=4 N=2  deleted data mark (ST2 bit 6)
  R=5 N=2  data CRC error (ST1 bit 5, ST2 bit 5)
Tracks 6-39: unformatted.

usage: make-fdc-test-dsk.py OUTPUT.dsk
"""

import struct
import sys

TRACKS = 40
SECTORS = [0xC1, 0xC6, 0xC2, 0xC7, 0xC3, 0xC8, 0xC4, 0xC9, 0xC5]


def pattern(track: int, r: int, size: int) -> bytes:
    return bytes(((i * 7) ^ (track * 16) ^ r) & 0xFF for i in range(size))


def track_block(track: int, sectors: list[tuple]) -> bytes:
    info = bytearray(0x100)
    info[0:12] = b"Track-Info\r\n"
    info[0x10] = track
    info[0x14] = 2
    info[0x15] = len(sectors)
    info[0x16] = 0x4E
    info[0x17] = 0xE5
    data = b""
    for i, (c, h, r, n, st1, st2, payload) in enumerate(sectors):
        struct.pack_into("<6BH", info, 0x18 + i * 8, c, h, r, n, st1, st2, len(payload))
        data += payload
    block = bytes(info) + data
    return block + bytes(-len(block) % 256)


def main() -> None:
    blocks = []
    for t in range(6):
        if t < 5:
            secs = [(t, 0, r, 2, 0, 0, pattern(t, r, 512)) for r in SECTORS]
        else:
            secs = [
                (5, 0, 1, 2, 0, 0, pattern(5, 1, 512)),
                (6, 0, 2, 2, 0, 0, pattern(5, 2, 512)),
                (5, 0, 3, 1, 0, 0, pattern(5, 3, 256)),
                (5, 0, 4, 2, 0, 0x40, pattern(5, 4, 512)),
                (5, 0, 5, 2, 0x20, 0x20, pattern(5, 5, 512)),
            ]
        blocks.append(track_block(t, secs))
    header = bytearray(0x100)
    header[0:34] = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
    header[0x22:0x30] = b"cpc-validation"
    header[0x30] = TRACKS
    header[0x31] = 1
    for t, b in enumerate(blocks):
        header[0x34 + t] = len(b) // 256
    with open(sys.argv[1], "wb") as fh:
        fh.write(bytes(header) + b"".join(blocks))


if __name__ == "__main__":
    main()

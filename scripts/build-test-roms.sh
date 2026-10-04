#!/usr/bin/env bash
# Assemble the direct-boot test ROMs under catalog/ with pasmo.
#
# Every catalog/**/src/test.asm becomes ../fixtures/test.rom, padded to the
# 16K lower ROM size. The ROMs are committed so running the catalog needs no
# assembler; rerun this after editing a test source.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v pasmo >/dev/null || { echo "pasmo is required (apt install pasmo)" >&2; exit 1; }

find catalog -path '*/src/test.asm' | sort | while read -r src; do
    dir="$(dirname "$src")"
    out="$dir/../fixtures/test.rom"
    mkdir -p "$(dirname "$out")"
    if [ -f "$dir/gen.py" ]; then
        (cd "$dir" && python3 gen.py >/dev/null)
    fi
    (cd "$dir" && pasmo --bin test.asm test.bin)
    size=$(stat -c %s "$dir/test.bin")
    if [ "$size" -gt 16384 ]; then
        echo "$src: ROM is $size bytes (max 16384)" >&2
        exit 1
    fi
    { cat "$dir/test.bin"; head -c $((16384 - size)) /dev/zero; } > "$out"
    rm "$dir/test.bin"
    echo "built $out ($size bytes)"
done

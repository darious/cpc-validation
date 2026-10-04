# Manifest schema

Every test is described by a `manifest.toml` file inside `catalog/`. The
harness walks the catalog tree and runs each manifest it finds.

```toml
schema = 1
name = "464-boot-banner"
description = "CPC 464 boots to the BASIC 1.0 prompt within 200 frames."

[setup]
model = "Cpc464"           # required: Cpc464 | Cpc664 | Cpc6128
crtc  = "Type1"            # required: Type0 | Type1 | Type2 | Type4
frames = 200               # required: frames after any input script
disks = []                 # optional: list of paths relative to the manifest
rom = "fixtures/zex.rom"   # optional: substitute lower ROM for direct-boot
input = "input.txt"        # optional: input script path relative to manifest
audio_frames = 20          # optional: ask the runner for audio.wav (last N frames)

[[verdict]]
kind = "screen_image"
golden = "goldens/boot.png"
tolerance = 0.0            # 0..=1 fraction of pixels allowed to differ

[[verdict]]
kind = "ram_byte"
address = 0x7FFF
value = 0x01

[[verdict]]
kind = "screen_text_contains"
needle = "ALL TESTS PASSED"

[[verdict]]
kind = "ram_bytes"
address = 0x9000
hex = "dd0560..."          # or length = N, filled in by --bless

[[verdict]]
kind = "ram_hash"
range = [0x4000, 0x8000]
sha256 = "deadbeef..."
```

## Verdict kinds

A manifest may declare any number of verdicts. **All** verdicts must pass for
the test to pass. Verdicts are evaluated independently after the runner has
finished.

| `kind`                   | Reads               | Passes when                                                  |
|--------------------------|---------------------|--------------------------------------------------------------|
| `ram_byte`               | `ram.bin[address]`  | byte equals `value`                                          |
| `ram_hash`               | `ram.bin[range]`    | sha256 equals `sha256`                                       |
| `ram_bytes`              | `ram.bin[address..]`| bytes equal `hex`; failures list the differing addresses     |
| `audio_tone`             | `audio.wav`         | `channel` (left/right/mix) has a tone at `frequency` within `tolerance` (fraction); `measure = "envelope"` measures the amplitude envelope instead; `silent = true` expects silence |
| `screen_image`           | `screen.png`        | pixel diff against `golden` within `tolerance`               |
| `screen_text_contains`   | `ram.bin` + `screen_mode` (via OCR) | OCR'd grid contains `needle`                  |
| `screen_text_regex`      | `ram.bin` + `screen_mode` (via OCR) | OCR'd grid matches `pattern`                  |

Paths inside a manifest are resolved relative to the manifest file.

`ram.bin` holds physical RAM (see the runner protocol), so for a 6128 an
address such as `0x9000` refers to bank 2 offset `0x1000`, which is what the
CPU sees at `&9000` in the default memory configuration.

Avoid RAM checks on memory the test never writes: emulators start with
different power-on RAM contents.

## Bless mode

`cpc-validation run --bless` records the runner's output as the expected
result: `screen_image` goldens are overwritten with `screen.png`, and the
expected values of `ram_bytes`, `ram_hash` and `ram_byte` verdicts are
written back into the manifest. Bless with the reference runner (CPCEC),
then run other emulators against the result.

## Direct-boot test ROMs

Tests under `catalog/hardware/` and `catalog/crtc/` use `rom` to replace the
lower ROM with a small program that runs from reset without firmware. Their
sources are in each test's `src/test.asm` (sharing `catalog/lib/*.asm`);
`scripts/build-test-roms.sh` assembles them with pasmo into
`fixtures/test.rom`.

# Runner protocol

A **runner** is any program that drives a CPC emulator on demand and emits
artefacts the harness can evaluate. Each emulator gets its own runner
adapter. The harness does not depend on any emulator's internals.

## CLI

A runner MUST accept the following flags. Unknown flags MAY be tolerated.

```
<runner> --model {Cpc464|Cpc664|Cpc6128}
         --crtc  {Type0|Type1|Type2|Type4}
         --frames N
         --output-dir DIR
         [--disk-a PATH]
         [--disk-b PATH]
         [--rom PATH]
         [--input PATH]
```

Semantics:

| Flag           | Required | Meaning                                                              |
|----------------|----------|----------------------------------------------------------------------|
| `--model`      | yes      | CPC variant to emulate.                                              |
| `--crtc`       | yes      | CRTC variant. Runners that cannot emulate a given CRTC SHOULD exit non-zero. |
| `--frames`     | yes      | Number of video frames to emulate after any input script completes. A frame ends at the monitor's vertical sync (every 19968 µs on a standard screen). |
| `--output-dir` | yes      | Directory the runner writes artefacts into. Created if missing.      |
| `--disk-a`     | no       | DSK image inserted in drive A before the run.                        |
| `--disk-b`     | no       | DSK image inserted in drive B.                                       |
| `--rom`        | no       | A raw ROM image to substitute for the lower OS ROM. Used for direct-boot ROM tests like zexdoc/zexall. |
| `--input`      | no       | Path to an input script (see below) that runs before the `--frames` count begins. |

## Input script

UTF-8 text. One directive per line. Lines starting with `#` and blank lines
are ignored.

| Directive               | Meaning                                                                 |
|-------------------------|-------------------------------------------------------------------------|
| `sleep N`               | Run N frames with no input.                                             |
| `type_text TEXT`        | Type TEXT. The two characters `\n` type Enter.                          |
| `key_press NAME`        | Hold the named CPC key (see the key table below).                       |
| `key_release NAME`      | Release the named CPC key.                                              |

`type_text` holds each key (with Shift where needed) for 2 frames, then
releases it for 1 frame, so typing N characters takes 3N frames. Letters,
digits, space and `:;,.-/@^[]\` are typed unshifted; `!"#$%&'()` are Shift
with 1-9, `_` is Shift+0, `=` Shift+Minus, `+` Shift+Semicolon, `*`
Shift+Colon, `?` Shift+Slash, `>` Shift+Period, `<` Shift+Comma, `|`
Shift+At and `{` `}` Shift with the brackets.

### Key names

Names and their keyboard matrix positions (line.bit):

| Line | bit 0 | bit 1 | bit 2 | bit 3 | bit 4 | bit 5 | bit 6 | bit 7 |
|------|-------|-------|-------|-------|-------|-------|-------|-------|
| 0 | ArrowUp | ArrowRight | ArrowDown | Numpad9 | Numpad6 | Numpad3 | NumpadEnter | NumpadPeriod |
| 1 | ArrowLeft | Copy | Numpad7 | Numpad8 | Numpad5 | Numpad1 | Numpad2 | Numpad0 |
| 2 | Clear | BracketLeft | Enter | BracketRight | Numpad4 | Shift | Backslash | Control |
| 3 | Caret | Minus | At | P | Semicolon | Colon | Slash | Period |
| 4 | Key0 | Key9 | O | I | L | K | M | Comma |
| 5 | Key8 | Key7 | U | Y | H | J | N | Space |
| 6 | Key6 | Key5 | R | T | G | F | B | V |
| 7 | Key4 | Key3 | E | W | S | D | C | X |
| 8 | Key1 | Key2 | Escape | Q | Tab | A | CapsLock | Z |
| 9 | JoystickUp | JoystickDown | JoystickLeft | JoystickRight | JoystickFire1 | JoystickFire2 | JoystickFire3 | Delete |

## Output artefacts

After the run finishes, the runner MUST have written these files under
`--output-dir`:

### `meta.json`

```json
{
  "model": "Cpc6128",
  "crtc": "Type1",
  "frames_run": 200,
  "exit": "frames_complete",
  "ram_size": 65536,
  "screen_mode": 1,
  "screen": { "width": 768, "height": 560 }
}
```

| Key            | Meaning                                                                                            |
|----------------|----------------------------------------------------------------------------------------------------|
| `model`        | Echo of `--model`.                                                                                 |
| `crtc`         | Echo of `--crtc`.                                                                                  |
| `frames_run`   | Frames actually emulated (input script + `--frames`).                                              |
| `exit`         | `frames_complete`, `trap`, or `error: <reason>`.                                                   |
| `ram_size`     | Length in bytes of `ram.bin`. 65536 for 464/664, 131072 for 6128.                                  |
| `screen_mode`  | Last-known CPC screen mode (0, 1, or 2). Used by OCR verdicts.                                     |
| `screen`       | Pixel dimensions of `screen.png`.                                                                  |

### `screen.png`

The last complete frame, in the canonical screen format so that images from
different emulators can be compared pixel for pixel:

- 768x536 pixels: a window 48 µs wide (16 pixels per µs, i.e. mode 2
  resolution) and 268 scanlines tall, every scanline drawn twice.
- For the firmware's standard screen (R0=63, R1=40, R2=46, R3=&8E, R4=38,
  R6=25, R7=30, R9=7) the 640x400 bitmap starts at x=64, y=76: 4 characters
  of border left and right, 38 scanlines above and 30 below.
- Colours use the conventional levels 0x00, 0x80 and 0xFF per channel for
  the 27 hardware colours; blanking (sync) is black.

The reference runner (CPCEC) defines the window; other runners crop or
offset their own frame to match it.

Runners MAY add keys; the bundled runners add `"emulator"`.

### `ram.bin`

Raw RAM dump. For 64K models the layout is the linear 0x0000..0x10000 RAM as
the CPU would see it under the **default** banking configuration. For the
6128 the file is 0x20000 bytes: the eight physical 16K banks in order
0..7 (NOT what the CPU currently sees through banking — physical layout, so
verdicts are deterministic regardless of which RAM config the program ended
in).

### Exit code

`0` on success. Non-zero on any failure to produce the artefacts. The harness
treats a non-zero exit as a runner-side error distinct from a verdict failure.

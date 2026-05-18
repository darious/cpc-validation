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
| `--frames`     | yes      | Number of 50 Hz frames to emulate after any input script completes.  |
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
| `type_text TEXT`        | Synthesize keypresses to type TEXT. `\n` becomes Enter.                 |
| `key_press NAME`        | Hold the named CPC key. Names come from the runner's key table.         |
| `key_release NAME`      | Release the named CPC key.                                              |

Runners SHOULD interpret `type_text` using their own host-key-to-CPC-key
mapping. The harness does not prescribe a key map.

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

Final framebuffer as PNG. Resolution is emulator-defined and is reported in
`meta.json`.

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

# cpc-validation

Generic accuracy and validation test harness for Amstrad CPC emulators.

The harness itself is emulator-agnostic. It walks a catalog of manifests, spawns
a configured **runner** binary (an adapter that wraps any CPC emulator) as a
subprocess, and evaluates verdicts against the artefacts the runner produces.

```
cpc-validation/
  schema/        Specification of the manifest format and the runner protocol.
  catalog/       Test manifests and fixtures.
  src/           Python harness package (cpc_validation).
  runners/       Per-emulator adapter binaries.
  scripts/       Helpers for fetching external test corpora.
```

## Quickstart

All commands below assume the project root (`cpc-validation/`) as cwd.

```sh
# Build the bundled runners. Parens keep the cd local.
( cd runners/cpcec && make )                 # CPCEC (C, SDL2): the reference
( cd runners/ronald && cargo build --release )  # Ronald (Rust)

# Sync Python deps.
uv sync

# Fetch external test corpora (optional).
./scripts/fetch-amstrad-diag.sh

# Run the catalog.
uv run cpc-validation run \
  --runner ./runners/cpcec/build/cpc-runner-cpcec \
  --catalog catalog/

# Re-bless goldens and RAM expectations from the reference emulator.
uv run cpc-validation run --runner ./runners/cpcec/build/cpc-runner-cpcec \
  --catalog catalog/ --bless

# Rebuild the direct-boot test ROMs after editing their sources (needs pasmo).
./scripts/build-test-roms.sh
```

## Adding a different emulator

Implement a runner binary that satisfies [schema/runner-protocol.md](schema/runner-protocol.md).
The runner can be in any language; the harness only requires the CLI contract
and the three artefact files (`screen.png`, `ram.bin`, `meta.json`). The
existing [`runners/ronald/`](runners/ronald/) adapter is a small Rust binary —
treat it as a template.

For each candidate emulator you can typically wrap an existing CLI mode (or
write a small shim) instead of modifying the emulator's source.

## Adding a test

Create a directory under `catalog/`:

```
catalog/<your-area>/<test-name>/
  manifest.toml
  goldens/         # optional, for screen_image verdicts
  fixtures/        # optional, your DSK/ROM artefacts
```

See [schema/manifest.md](schema/manifest.md) for the manifest format.

## Runners

| Runner | Emulator | Notes |
|--------|----------|-------|
| `runners/cpcec` | [CPCEC](https://github.com/cpcitor/cpcec) | Reference. Built from an unmodified CPCEC checkout next to this repo (`make CPCEC_DIR=...` to override); uses CPCEC's bundled ROMs. Needs SDL2 development files. |
| `runners/ronald` | [Ronald](https://github.com/mdm/ronald) | Depends on `ronald-core` by path (`../../../ronald`). ROMs from `--rom-dir`, `$RONALD_ROM_DIR` or next to the binary. |
| cpcgo | [cpcgo](https://github.com/darious/cpcgo) | `cmd/cpc-runner-cpcgo` in the cpcgo repository. |

All runners produce the canonical 768x536 `screen.png`, so goldens blessed
from the reference runner apply to every emulator.

## Status

| Area                       | State |
|----------------------------|-------|
| Harness CLI                | functional |
| Manifest schema (v1)       | documented |
| Runner protocol            | documented (canonical screen, key names) |
| Verdicts                   | ram_byte, ram_bytes, ram_hash, screen_image, screen_text_* (modes 1 and 2), audio_tone |
| Catalog: boot banners (464/664/6128) | 3 tests |
| Catalog: AmstradDiag boot  | 1 test (disk loading through AMSDOS) |
| Catalog: hardware (direct-boot ROMs) | instruction timing (82 sequences), raster/palette/mode/interrupt timing, interrupt modes, RAM banking, PSG, PPI, keyboard matrix |
| Catalog: CRTC              | overscan, geometry, rupture, R1/R8 changes, short VSYNC, register reads; mid-frame changes of R0, R2, R3, R4, R6, R7, R9, R12, R13 (all on types 0/1/2/4) |
| Catalog: sound             | PSG tones, envelope, noise, BASIC SOUND (audio_tone) |
| Catalog: disk              | FDC command results, CAT, SAVE/LOAD on 464 (DDI-1)/664/6128 |
| Catalog: Arnold acid tests | needs innoextract; not wired |

### Results (reference: CPCEC)

The CPCEC runner passes every test by construction (goldens are blessed
from it). cpcgo passes 87 of 111. The 24 failures are the CRTC
mid-frame probes for HSYNC width (R3), HSYNC position (R2), line length
(R0), R9, R12 and R4 overflow on types 0/1/2/4. Most of the differences
come from the monitor model; see cpcgo's `docs/validation.md`. The Ronald
runner works but Ronald is not tracked against the catalog.

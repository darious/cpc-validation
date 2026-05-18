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

```sh
# Build the bundled Ronald adapter (Rust).
( cd runners/ronald && cargo build --release )

# Sync Python deps.
uv sync

# Run the catalog.
uv run cpc-validation run \
  --runner ./runners/ronald/target/release/cpc-runner-ronald \
  --catalog catalog/

# Bless screen-image goldens after intentional changes.
uv run cpc-validation run --runner ... --catalog catalog/ --bless
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

## Status

| Area                       | State |
|----------------------------|-------|
| Harness CLI                | functional |
| Manifest schema (v1)       | documented |
| Runner protocol            | documented |
| Verdicts: ram_byte, ram_hash, screen_image | implemented |
| Verdicts: screen_text_*    | OCR not yet implemented |
| Ronald adapter             | functional |
| Catalog: boot banners (464/664/6128) | 3 tests, all passing |
| Catalog: Arnold acid tests | manifests pending |
| Catalog: Z80 exercisers    | pending |

The Ronald adapter depends on `ronald-core` via path. Adjust the path in
`runners/ronald/Cargo.toml` if your `ronald` checkout lives elsewhere.

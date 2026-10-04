"""Verdict evaluation against runner artefacts."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from cpc_validation import ocr
from cpc_validation.manifest import Manifest, Verdict
from cpc_validation.runner import RunArtefacts


@dataclass
class VerdictOutcome:
    verdict: Verdict
    passed: bool
    reason: str
    # Replacement for the verdict's expected value when blessing (TOML literal).
    blessed: str | None = None


def evaluate(
    manifest: Manifest,
    artefacts: RunArtefacts,
    bless: bool = False,
) -> list[VerdictOutcome]:
    outcomes = [_evaluate_one(manifest, v, artefacts, bless) for v in manifest.verdicts]
    blessed = [o.blessed for o in outcomes]
    if any(b is not None for b in blessed):
        _rewrite_manifest_values(manifest, blessed)
    return outcomes


# Keys holding expected RAM values that --bless can fill in, per verdict kind.
_BLESSABLE_KEYS = {"ram_hash": "sha256", "ram_bytes": "hex", "ram_byte": "value"}


def _rewrite_manifest_values(manifest: Manifest, blessed: list[str | None]) -> None:
    """Write blessed RAM expectations back into the manifest file.

    Each [[verdict]] table is located in source order; the expected-value line
    of a blessed verdict is replaced in place, keeping the rest of the file.
    """
    lines = manifest.path.read_text().splitlines(keepends=True)
    table_starts = [i for i, line in enumerate(lines) if line.strip() == "[[verdict]]"]
    for index, value in enumerate(blessed):
        if value is None or index >= len(table_starts):
            continue
        verdict = manifest.verdicts[index]
        key = _BLESSABLE_KEYS[verdict.kind]
        start = table_starts[index]
        end = table_starts[index + 1] if index + 1 < len(table_starts) else len(lines)
        pattern = re.compile(rf"^(\s*{key}\s*=\s*).*$")
        for i in range(start + 1, end):
            m = pattern.match(lines[i].rstrip("\n"))
            if m:
                lines[i] = f"{m.group(1)}{value}\n"
                break
        else:
            lines.insert(end, f"{key} = {value}\n")
    manifest.path.write_text("".join(lines))


def _evaluate_one(
    manifest: Manifest,
    verdict: Verdict,
    artefacts: RunArtefacts,
    bless: bool,
) -> VerdictOutcome:
    try:
        match verdict.kind:
            case "ram_byte":
                return _ram_byte(verdict, artefacts, bless)
            case "ram_hash":
                return _ram_hash(verdict, artefacts, bless)
            case "ram_bytes":
                return _ram_bytes(verdict, artefacts, bless)
            case "screen_image":
                return _screen_image(manifest, verdict, artefacts, bless)
            case "screen_text_contains":
                return _screen_text_contains(verdict, artefacts)
            case "screen_text_regex":
                return _screen_text_regex(verdict, artefacts)
            case _:
                return VerdictOutcome(verdict, False, f"unknown verdict kind {verdict.kind!r}")
    except Exception as e:
        return VerdictOutcome(verdict, False, f"verdict raised: {e}")


def _ram_byte(verdict: Verdict, artefacts: RunArtefacts, bless: bool) -> VerdictOutcome:
    address = _require_int(verdict, "address")
    data = artefacts.ram_path.read_bytes()
    if not 0 <= address < len(data):
        return VerdictOutcome(
            verdict, False, f"address 0x{address:X} out of range (ram size {len(data)})"
        )
    actual = data[address]
    if bless:
        return VerdictOutcome(
            verdict, True, f"blessed ram[0x{address:X}] = 0x{actual:02X}", f"0x{actual:02X}"
        )
    expected = _require_int(verdict, "value") & 0xFF
    if actual == expected:
        return VerdictOutcome(verdict, True, f"ram[0x{address:X}] = 0x{actual:02X}")
    return VerdictOutcome(
        verdict, False, f"ram[0x{address:X}] = 0x{actual:02X}, expected 0x{expected:02X}"
    )


def _ram_hash(verdict: Verdict, artefacts: RunArtefacts, bless: bool) -> VerdictOutcome:
    rng = verdict.params.get("range")
    if not isinstance(rng, list) or len(rng) != 2:
        return VerdictOutcome(verdict, False, "ram_hash.range must be [start, end]")
    start, end = int(rng[0]), int(rng[1])

    data = artefacts.ram_path.read_bytes()
    if not 0 <= start < end <= len(data):
        return VerdictOutcome(verdict, False, f"range {start:X}..{end:X} out of bounds")
    actual = hashlib.sha256(data[start:end]).hexdigest()
    if bless:
        return VerdictOutcome(verdict, True, f"blessed sha256 = {actual}", f'"{actual}"')
    expected = verdict.params.get("sha256")
    if not isinstance(expected, str):
        return VerdictOutcome(verdict, False, "ram_hash.sha256 must be a string")
    if actual == expected:
        return VerdictOutcome(verdict, True, f"sha256 = {actual}")
    return VerdictOutcome(verdict, False, f"sha256 {actual} != expected {expected}")


def _ram_bytes(verdict: Verdict, artefacts: RunArtefacts, bless: bool) -> VerdictOutcome:
    address = _require_int(verdict, "address")
    data = artefacts.ram_path.read_bytes()
    expected_hex = verdict.params.get("hex")
    length = verdict.params.get("length")
    if not isinstance(length, int):
        if not isinstance(expected_hex, str):
            return VerdictOutcome(verdict, False, "ram_bytes needs hex or length")
        length = len(bytes.fromhex(expected_hex))
    if not 0 <= address <= address + length <= len(data):
        return VerdictOutcome(verdict, False, f"range 0x{address:X}+{length} out of bounds")
    actual = data[address : address + length]
    if bless:
        return VerdictOutcome(
            verdict, True, f"blessed {length} bytes at 0x{address:X}", f'"{actual.hex()}"'
        )
    if not isinstance(expected_hex, str):
        return VerdictOutcome(verdict, False, "ram_bytes.hex is required (run with --bless)")
    expected = bytes.fromhex(expected_hex)
    if actual == expected:
        return VerdictOutcome(verdict, True, f"{length} bytes at 0x{address:X} match")
    diffs = [i for i in range(length) if actual[i] != expected[i]]
    shown = ", ".join(
        f"0x{address + i:X}: 0x{actual[i]:02X} (want 0x{expected[i]:02X})" for i in diffs[:6]
    )
    more = f" and {len(diffs) - 6} more" if len(diffs) > 6 else ""
    return VerdictOutcome(verdict, False, f"{len(diffs)} bytes differ: {shown}{more}")


def _screen_image(
    manifest: Manifest,
    verdict: Verdict,
    artefacts: RunArtefacts,
    bless: bool,
) -> VerdictOutcome:
    golden_str = verdict.params.get("golden")
    if not isinstance(golden_str, str):
        return VerdictOutcome(verdict, False, "screen_image.golden is required")
    golden_path: Path = manifest.resolve(golden_str)
    tolerance = float(verdict.params.get("tolerance", 0.0))

    if bless or not golden_path.exists():
        golden_path.parent.mkdir(parents=True, exist_ok=True)
        Image.open(artefacts.screen_path).save(golden_path)
        return VerdictOutcome(verdict, True, f"blessed {golden_path} from {artefacts.screen_path}")

    actual = Image.open(artefacts.screen_path).convert("RGBA")
    golden = Image.open(golden_path).convert("RGBA")
    if actual.size != golden.size:
        return VerdictOutcome(verdict, False, f"size {actual.size} != golden {golden.size}")

    a = actual.tobytes()
    g = golden.tobytes()
    # Compare 4 bytes per pixel.
    pixel_count = actual.size[0] * actual.size[1]
    diff = sum(1 for i in range(pixel_count) if a[i * 4 : i * 4 + 4] != g[i * 4 : i * 4 + 4])
    ratio = diff / pixel_count if pixel_count else 0.0
    if ratio <= tolerance:
        return VerdictOutcome(verdict, True, f"diff ratio {ratio:.4f} ≤ {tolerance:.4f}")

    diff_path = artefacts.output_dir / "diff.png"
    _write_diff_png(actual, golden, diff_path)
    return VerdictOutcome(
        verdict,
        False,
        f"diff ratio {ratio:.4f} > {tolerance:.4f}; see {diff_path}",
    )


def _write_diff_png(actual: Image.Image, golden: Image.Image, out_path: Path) -> None:
    w, h = actual.size
    diff_img = Image.new("RGBA", (w, h))
    a_pixels = actual.load()
    g_pixels = golden.load()
    d_pixels = diff_img.load()
    for y in range(h):
        for x in range(w):
            if a_pixels[x, y] == g_pixels[x, y]:
                d_pixels[x, y] = (0, 0, 0, 255)
            else:
                d_pixels[x, y] = (255, 0, 255, 255)
    diff_img.save(out_path)


def _screen_text(verdict: Verdict, artefacts: RunArtefacts) -> str | None:
    mode = int(artefacts.meta.get("screen_mode", -1))
    ram = artefacts.ram_path.read_bytes()
    text = ocr.decode_screen_text(ram, mode)
    if text == "":
        return None
    return text


def _screen_text_contains(verdict: Verdict, artefacts: RunArtefacts) -> VerdictOutcome:
    needle = verdict.params.get("needle")
    if not isinstance(needle, str):
        return VerdictOutcome(verdict, False, "screen_text_contains.needle is required")
    text = _screen_text(verdict, artefacts)
    if text is None:
        return VerdictOutcome(
            verdict, False, f"OCR unavailable for screen_mode {artefacts.meta.get('screen_mode')}"
        )
    if needle in text:
        return VerdictOutcome(verdict, True, f"found {needle!r}")
    preview = " | ".join(line for line in text.splitlines() if line)[:120]
    return VerdictOutcome(verdict, False, f"{needle!r} not on screen (saw: {preview!r})")


def _screen_text_regex(verdict: Verdict, artefacts: RunArtefacts) -> VerdictOutcome:
    pattern = verdict.params.get("pattern")
    if not isinstance(pattern, str):
        return VerdictOutcome(verdict, False, "screen_text_regex.pattern is required")
    text = _screen_text(verdict, artefacts)
    if text is None:
        return VerdictOutcome(
            verdict, False, f"OCR unavailable for screen_mode {artefacts.meta.get('screen_mode')}"
        )
    flags = re.MULTILINE | re.DOTALL
    m = re.search(pattern, text, flags=flags)
    if m:
        return VerdictOutcome(verdict, True, f"matched {m.group(0)!r}")
    preview = " | ".join(line for line in text.splitlines() if line)[:120]
    return VerdictOutcome(verdict, False, f"pattern {pattern!r} not found (saw: {preview!r})")


def _require_int(verdict: Verdict, key: str) -> int:
    v = verdict.params.get(key)
    if isinstance(v, int):
        return v
    raise ValueError(f"verdict {verdict.kind} requires integer {key!r}")

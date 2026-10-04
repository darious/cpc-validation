"""Manifest TOML parsing."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path

SUPPORTED_SCHEMA = 1
MODELS = {"Cpc464", "Cpc664", "Cpc6128"}
CRTCS = {"Type0", "Type1", "Type2", "Type4"}


@dataclass(frozen=True)
class Setup:
    model: str
    crtc: str
    frames: int
    disks: list[Path]
    rom: Path | None
    input_script: Path | None
    audio_frames: int = 0


@dataclass(frozen=True)
class Verdict:
    kind: str
    params: dict


@dataclass(frozen=True)
class Manifest:
    path: Path
    name: str
    description: str
    setup: Setup
    verdicts: list[Verdict]

    @property
    def base_dir(self) -> Path:
        return self.path.parent

    def resolve(self, p: str | Path) -> Path:
        p = Path(p)
        if p.is_absolute():
            return p
        return (self.base_dir / p).resolve()


def load(path: Path) -> Manifest:
    with path.open("rb") as fh:
        data = tomllib.load(fh)

    schema = data.get("schema")
    if schema != SUPPORTED_SCHEMA:
        raise ValueError(f"{path}: unsupported schema {schema!r} (expected {SUPPORTED_SCHEMA})")

    name = _require_str(data, "name", path)
    description = data.get("description", "")
    setup_raw = _require_table(data, "setup", path)
    setup = _parse_setup(setup_raw, path)
    verdicts = _parse_verdicts(data.get("verdict", []), path)
    if not verdicts:
        raise ValueError(f"{path}: at least one [[verdict]] is required")

    return Manifest(
        path=path,
        name=name,
        description=description,
        setup=setup,
        verdicts=verdicts,
    )


def discover(catalog_root: Path) -> list[Manifest]:
    out: list[Manifest] = []
    for manifest_path in sorted(catalog_root.rglob("manifest.toml")):
        out.append(load(manifest_path))
    return out


def _parse_setup(raw: dict, path: Path) -> Setup:
    model = _require_str(raw, "model", path)
    if model not in MODELS:
        raise ValueError(f"{path}: setup.model {model!r} not in {sorted(MODELS)}")
    crtc = _require_str(raw, "crtc", path)
    if crtc not in CRTCS:
        raise ValueError(f"{path}: setup.crtc {crtc!r} not in {sorted(CRTCS)}")
    frames = raw.get("frames")
    if not isinstance(frames, int) or frames < 0:
        raise ValueError(f"{path}: setup.frames must be a non-negative integer")

    disks = [Path(p) for p in raw.get("disks", [])]
    rom = Path(raw["rom"]) if "rom" in raw else None
    input_script = Path(raw["input"]) if "input" in raw else None

    audio_frames = raw.get("audio_frames", 0)
    if not isinstance(audio_frames, int) or audio_frames < 0:
        raise ValueError(f"{path}: setup.audio_frames must be a non-negative integer")

    return Setup(
        model=model,
        crtc=crtc,
        frames=frames,
        disks=disks,
        rom=rom,
        input_script=input_script,
        audio_frames=audio_frames,
    )


def _parse_verdicts(raw_list: list, path: Path) -> list[Verdict]:
    out: list[Verdict] = []
    for i, raw in enumerate(raw_list):
        if not isinstance(raw, dict):
            raise ValueError(f"{path}: verdict #{i} is not a table")
        kind = raw.get("kind")
        if not isinstance(kind, str):
            raise ValueError(f"{path}: verdict #{i} missing string 'kind'")
        params = {k: v for k, v in raw.items() if k != "kind"}
        out.append(Verdict(kind=kind, params=params))
    return out


def _require_str(d: dict, key: str, path: Path) -> str:
    v = d.get(key)
    if not isinstance(v, str) or not v:
        raise ValueError(f"{path}: missing or empty string {key!r}")
    return v


def _require_table(d: dict, key: str, path: Path) -> dict:
    v = d.get(key)
    if not isinstance(v, dict):
        raise ValueError(f"{path}: missing table {key!r}")
    return v

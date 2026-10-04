"""Subprocess invocation of a runner adapter and ingestion of its artefacts."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path

from cpc_validation.manifest import Manifest


@dataclass(frozen=True)
class RunArtefacts:
    output_dir: Path
    meta: dict
    ram_path: Path
    screen_path: Path


class RunnerError(RuntimeError):
    pass


def invoke(runner: Path, manifest: Manifest, output_dir: Path) -> RunArtefacts:
    output_dir.mkdir(parents=True, exist_ok=True)
    args: list[str] = [
        str(runner),
        "--model",
        manifest.setup.model,
        "--crtc",
        manifest.setup.crtc,
        "--frames",
        str(manifest.setup.frames),
        "--output-dir",
        str(output_dir),
    ]
    disks = manifest.setup.disks
    if len(disks) >= 1:
        args += ["--disk-a", str(manifest.resolve(disks[0]))]
    if len(disks) >= 2:
        args += ["--disk-b", str(manifest.resolve(disks[1]))]
    if manifest.setup.rom is not None:
        args += ["--rom", str(manifest.resolve(manifest.setup.rom))]
    if manifest.setup.input_script is not None:
        args += ["--input", str(manifest.resolve(manifest.setup.input_script))]
    if manifest.setup.audio_frames:
        args += ["--audio-frames", str(manifest.setup.audio_frames)]

    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RunnerError(
            f"runner {runner} exited {proc.returncode}\n"
            f"stderr:\n{proc.stderr}\nstdout:\n{proc.stdout}"
        )

    meta_path = output_dir / "meta.json"
    ram_path = output_dir / "ram.bin"
    screen_path = output_dir / "screen.png"
    for required in (meta_path, ram_path, screen_path):
        if not required.exists():
            raise RunnerError(f"runner did not produce {required.name} in {output_dir}")

    meta = json.loads(meta_path.read_text())
    return RunArtefacts(
        output_dir=output_dir,
        meta=meta,
        ram_path=ram_path,
        screen_path=screen_path,
    )

#!/usr/bin/env python3
"""Generate compact RGBA16F tone-mapping textures from the archived OCIO LUTs."""

from __future__ import annotations

import argparse
import pathlib
import struct


FILMIC_LOOKS = (
    "filmic_to_0-35_1-30.spi1d",
    "filmic_to_0-48_1-09.spi1d",
    "filmic_to_0-60_1-04.spi1d",
    "filmic_to_0-70_1-03.spi1d",
    "filmic_to_0-85_1-011.spi1d",
    "filmic_to_0.99_1-0075.spi1d",
    "filmic_to_1.20_1-00.spi1d",
)


def cube_values(path: pathlib.Path) -> tuple[int, list[tuple[float, float, float, float]]]:
    size = 0
    values: list[tuple[float, float, float, float]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if fields[0] == "LUT_3D_SIZE":
            size = int(fields[1])
        elif fields[0] not in {"TITLE", "DOMAIN_MIN", "DOMAIN_MAX"}:
            red, green, blue = map(float, fields[:3])
            values.append((red, green, blue, 1.0))
    expected = size**3
    if size == 0 or len(values) != expected:
        raise ValueError(f"{path}: expected {expected} values, found {len(values)}")
    return size, values


def spi1d_values(path: pathlib.Path) -> list[tuple[float, float, float, float]]:
    size = 0
    values: list[tuple[float, float, float, float]] = []
    in_values = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "{":
            in_values = True
        elif line == "}":
            break
        elif in_values:
            value = float(line.split()[0])
            values.append((value, value, value, 1.0))
        elif line.startswith("Length "):
            size = int(line.split()[1])
    if size == 0 or len(values) != size:
        raise ValueError(f"{path}: expected {size} values, found {len(values)}")
    return values


def write_rgba16f(path: pathlib.Path, values: list[tuple[float, float, float, float]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as output:
        for value in values:
            output.write(struct.pack("<4e", *value))


def main() -> None:
    package = pathlib.Path(__file__).resolve().parents[1]
    workspace = package.parents[1]
    default_source = (
        workspace
        / ".archives/NKFramework/Archives/NKEngineV1/Framework/Resources/Color"
    )
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=pathlib.Path, default=default_source)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=package / "Assets/ToneMapping",
    )
    arguments = parser.parse_args()

    for source_name, output_name, expected_size in (
        ("AgX_Base_sRGB.cube", "AgXBase.rgba16f", 57),
        ("pbrNeutral.cube", "PBRNeutral.rgba16f", 57),
        ("Filmic/filmic_desat_33.cube", "FilmicDesaturation.rgba16f", 33),
    ):
        size, values = cube_values(arguments.source / source_name)
        if size != expected_size:
            raise ValueError(f"{source_name}: expected LUT size {expected_size}, found {size}")
        write_rgba16f(arguments.output / output_name, values)

    filmic_values: list[tuple[float, float, float, float]] = []
    for name in FILMIC_LOOKS:
        values = spi1d_values(arguments.source / "Filmic" / name)
        if len(values) != 4096:
            raise ValueError(f"{name}: expected 4096 values, found {len(values)}")
        filmic_values.extend(values)
    write_rgba16f(arguments.output / "FilmicLooks.rgba16f", filmic_values)


if __name__ == "__main__":
    main()

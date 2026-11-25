#!/usr/bin/env python3
"""Prüft die Icon-Entwürfe Ende zu Ende mit Apples Werkzeugen (actool, ictool aus Icon Composer).

Aufruf: python3 design/icon/pruefe.py
Rot, solange nicht mindestens vier vollständige Entwürfe mit Tafeln vorliegen.
"""
import itertools
import json
import re
import struct
import subprocess
import sys
import tempfile
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent
XCODE = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip()).parent
ICTOOL = XCODE / "Applications/Icon Composer.app/Contents/Executables/ictool"
APPEARANCES = ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]
# Punktgrößen bei @3x: Homescreen 60, Spotlight 40, Einstellungen 29, Mitteilung 20.
SMALL = [60, 40, 29, 20]
MIN_CONTRAST = {"Default": 0.30, "Dark": 0.30, "TintedDark": 0.25}
errors = []


def check(ok, message):
    if not ok:
        errors.append(message)
    return ok


def read_png(path):
    """Minimaler PNG-Leser (8/16 Bit, RGB/RGBA). Liefert Breite, Höhe, Pixel als (r, g, b, a) in 0..1."""
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"kein PNG: {path}"
    pos, idat, head = 8, b"", None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length
    width, height, depth, color, _, _, interlace = head
    assert depth in (8, 16) and color in (2, 6) and interlace == 0, f"PNG-Format {depth}/{color} in {path}"
    channels, size = (4 if color == 6 else 3), depth // 8
    bpp = channels * size
    stride = width * bpp
    raw = zlib.decompress(idat)
    previous, rows = bytearray(stride), []
    for y in range(height):
        start = y * (stride + 1)
        mode, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = previous[i]
            c = previous[i - bpp] if i >= bpp else 0
            if mode == 1:
                line[i] = (line[i] + a) & 255
            elif mode == 2:
                line[i] = (line[i] + b) & 255
            elif mode == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif mode == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        previous = line
        rows.append(line)
    pixels = []
    for line in rows:
        for x in range(width):
            values = [line[x * bpp + c * size] / 255 for c in range(channels)]  # höchstwertiges Byte genügt
            pixels.append(tuple(values) if channels == 4 else (*values, 1.0))
    return width, height, pixels


def luminances(pixels):
    return [0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b, a in pixels if a > 0.98]


def render(icon, appearance, points, scale, out):
    command = [str(ICTOOL), str(icon), "--export-image", "--output-file", str(out), "--platform", "iOS",
               "--rendition", appearance, "--width", str(points), "--height", str(points), "--scale", str(scale),
               "--design-generation", "27"]
    if appearance.startswith("Tinted"):
        command += ["--tint-color", "0.55", "--tint-strength", "0.75"]
    result = subprocess.run(command, capture_output=True, text=True)
    return check(result.returncode == 0 and out.is_file(), f"ictool {icon.name} {appearance} {points}pt: {result.stderr[:200]}")


def check_sources(design, icon):
    spec = json.loads((icon / "icon.json").read_text())
    check("fill" in spec, f"{design.name}: Hintergrund fehlt")
    appearances = {s.get("appearance") for s in spec.get("fill-specializations", [])}
    check({"dark", "tinted"} <= appearances, f"{design.name}: Hintergrund ohne dunkel/getönt")
    groups = spec.get("groups", [])
    check(1 <= len(groups) <= 4, f"{design.name}: {len(groups)} Gruppen (erlaubt 1–4)")
    layers = [layer for group in groups for layer in group.get("layers", [])]
    check(len(layers) >= 2, f"{design.name}: weniger als 2 Ebenen")
    for layer in layers:
        path = icon / "Assets" / layer.get("image-name", "?")
        if not check(path.suffix == ".svg" and path.is_file(), f"{design.name}: SVG-Ebene fehlt: {path.name}"):
            continue
        text = path.read_text()
        tree = ET.fromstring(text)
        check(tree.get("viewBox") == "0 0 1024 1024", f"{design.name}/{path.name}: viewBox nicht 1024")
        tags = {element.tag.split("}")[-1] for element in tree.iter()}
        forbidden = tags & {"text", "image", "filter", "mask", "style", "foreignObject", "feGaussianBlur"}
        check(not forbidden, f"{design.name}/{path.name}: verboten {sorted(forbidden)}")
        check(not re.search(r'href=|url\(', text), f"{design.name}/{path.name}: Verweis nach außen")
        check(not re.search(r'<rect[^>]*width="1024"[^>]*height="1024"', text),
              f"{design.name}/{path.name}: Ebene füllt die ganze Fläche (Hintergrund gehört in icon.json)")


def check_compiler(design, icon, work):
    out = work / f"actool-{design.name}"
    out.mkdir()
    result = subprocess.run(
        ["xcrun", "actool", str(icon), "--compile", str(out), "--platform", "iphoneos",
         "--minimum-deployment-target", "26.0", "--app-icon", icon.stem,
         "--output-partial-info-plist", str(out / "partial.plist"), "--errors", "--warnings"],
        capture_output=True, text=True)
    check(result.returncode == 0 and (out / "Assets.car").is_file() and ".errors" not in result.stdout,
          f"{design.name}: actool lehnt das Icon ab: {(result.stdout + result.stderr)[:400]}")


def main():
    designs = sorted(p for p in ROOT.glob("[1-9]-*") if p.is_dir())
    check(len(designs) >= 4, f"nur {len(designs)} Entwürfe (mindestens 4)")
    readme = ROOT / "README.md"
    text = readme.read_text() if readme.is_file() else ""
    check("Empfehlung" in text, "README.md ohne Empfehlung")
    fingerprints = {}
    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        for design in designs:
            icons = list(design.glob("*.icon"))
            if not check(len(icons) == 1 and (icons[0] / "icon.json").is_file(), f"{design.name}: kein .icon"):
                continue
            icon = icons[0]
            check(design.name in text, f"README.md nennt {design.name} nicht")
            check_sources(design, icon)
            check_compiler(design, icon, work)
            for appearance in APPEARANCES:
                out = work / f"{design.name}-{appearance}.png"
                if render(icon, appearance, 1024, 1, out):
                    width, height = struct.unpack(">II", out.read_bytes()[16:24])
                    check((width, height) == (1024, 1024), f"{design.name} {appearance}: {width}x{height}")
            for appearance, points in itertools.product(MIN_CONTRAST, SMALL):
                out = work / f"{design.name}-{appearance}-{points}.png"
                if not render(icon, appearance, points, 3, out):
                    continue
                width, height, pixels = read_png(out)
                check((width, height) == (points * 3, points * 3), f"{design.name} {points}pt: {width}x{height}")
                if points == 20:
                    values = sorted(luminances(pixels))
                    spread = values[int(len(values) * 0.95)] - values[int(len(values) * 0.05)]
                    print(f"{design.name:16} {appearance:11} Kontrast bei 20 pt: {spread:.2f}")
                    check(spread >= MIN_CONTRAST[appearance],
                          f"{design.name} {appearance}: Kontrast bei 20 pt nur {spread:.2f}")
                    if appearance == "Default":
                        fingerprints[design.name] = luminances(pixels)
            board = design / "tafel.png"
            if check(board.is_file(), f"{design.name}: tafel.png fehlt"):
                width = struct.unpack(">I", board.read_bytes()[16:20])[0]
                check(width >= 2000, f"{design.name}: Tafel nur {width} px breit")
        for (a, x), (b, y) in itertools.combinations(fingerprints.items(), 2):
            n = min(len(x), len(y))
            difference = sum(abs(i - j) for i, j in zip(x[:n], y[:n])) / n
            check(difference >= 0.08, f"{a} und {b} sehen sich zu ähnlich ({difference:.2f})")
    check((ROOT / "uebersicht.png").is_file(), "uebersicht.png fehlt")
    for message in errors:
        print("ROT:", message)
    print(f"{len(designs)} Entwürfe, {len(errors)} Fehler → {'ROT' if errors else 'GRÜN'}")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()

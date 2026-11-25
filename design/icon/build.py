#!/usr/bin/env python3
"""Erzeugt die Icon-Entwürfe: SVG-Ebenen und icon.json (Icon Composer), danach die Vorschau-Tafeln.

Aufruf: python3 design/icon/build.py   (braucht Xcode mit Icon Composer; keine weiteren Pakete)
Die Geometrie steht nur hier. Renderings landen in render/ (nicht eingecheckt).
"""
import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def rgb(hex_color):
    return "srgb:" + ",".join(f"{int(hex_color[i:i + 2], 16) / 255:.5f}" for i in (0, 2, 4)) + ",1.00000"


def gradient(top, bottom):
    return {"linear-gradient": [rgb(top), rgb(bottom)],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def solid(color):
    return {"solid": rgb(color)}


def layer(name, shapes, light, dark, tinted, glass=True):
    """shapes: SVG-Fragmente ohne Farbe; die Farbe je Darstellung steht in icon.json."""
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024" '
           f'fill="#{light}">\n' + "\n".join(shapes) + "\n</svg>\n")
    return {"name": name, "svg": svg,
            "json": {"name": name, "image-name": f"{name}.svg", "glass": glass,
                     "fill-specializations": [{"value": solid(light)}, {"appearance": "dark", "value": solid(dark)},
                                              {"appearance": "tinted", "value": solid(tinted)}]}}


def path(d, transform=None, rule=None):
    extra = (f' transform="{transform}"' if transform else "") + (f' fill-rule="{rule}"' if rule else "")
    return f'<path d="{d}"{extra}/>'


def rect(x, y, w, h, r=0, transform=None):
    extra = f' transform="{transform}"' if transform else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"{extra}/>'


def circle(x, y, r, transform=None):
    extra = f' transform="{transform}"' if transform else ""
    return f'<circle cx="{x}" cy="{y}" r="{r}"{extra}/>'


# ---------------------------------------------------------------- 1 Profil: Sohle von unten, Ferse abgelaufen
def profil():
    turn = "rotate(28 512 512)"
    sole = ("M512 104 C650 104 732 214 718 352 C708 462 656 512 656 594 C656 660 694 704 688 778 "
            "C680 878 604 920 512 920 C420 920 344 878 336 778 C330 704 372 660 370 594 "
            "C366 512 316 462 306 352 C292 214 374 104 512 104 Z")

    def chevron(y, half, depth=62, thick=52):
        l, r = 512 - half, 512 + half
        return path(f"M{l} {y} L512 {y + depth} L{r} {y} L{r} {y + thick} L512 {y + depth + thick} L{l} {y + thick} Z", turn)

    tread = [chevron(204, 118), chevron(320, 156), chevron(436, 118)]
    # Ferse: die Stollen werden zur Außenkante hin dünner = abgelaufen.
    wear = [path(f"M{x0} {y} L{x1} {y} L{x1} {y + thin} L{x0} {y + thick} Z", turn)
            for x0, x1, y, thick, thin in [(392, 632, 668, 54, 26), (382, 642, 750, 48, 16), (418, 606, 828, 40, 8)]]
    return {
        "dir": "1-profil", "name": "Profil", "icon": "Profil",
        "idea": "Laufsohle von unten: volles Profil vorn, abgelaufene Ferse in Gelb. Verschleiß auf einen Blick.",
        "fill": (gradient("0F8577", "033C37"), gradient("0E2E2B", "04100F"), gradient("2A2A2A", "0C0C0C")),
        "groups": [[layer("verschleiss", wear, "FFC53D", "FFC53D", "8A8A8A", glass=False),
                    layer("profil", tread, "0C5F57", "12403B", "262626", glass=False)],
                   [layer("sohle", [path(sole, turn)], "FFFFFF", "7FE3D2", "FFFFFF")]],
    }


# ---------------------------------------------------------------- 2 Laufschuh: neutrale Silhouette, Stollen hinten abgenutzt
def laufschuh():
    move = "rotate(-12 512 540)"
    upper = ("M150 392 C186 350 240 338 282 356 C320 374 318 430 384 436 C446 442 470 372 530 336 "
             "C556 320 590 330 604 356 C650 440 724 482 810 506 C880 526 914 572 906 626 L150 626 "
             "C134 556 130 462 150 392 Z")
    midsole = "M138 648 L912 648 C920 704 878 742 822 742 L214 742 C164 742 134 706 138 648 Z"
    lugs = [rect(x, 756, 80, h, 16, move) for x, h in [(188, 18), (290, 28), (392, 40), (494, 50), (596, 56), (698, 56)]]
    laces = [rect(x, y, 30, 82, 15, f"{move} rotate(-36 {x + 15} {y + 41})") for x, y in [(528, 382), (624, 436), (720, 476)]]
    return {
        "dir": "2-laufschuh", "name": "Laufschuh", "icon": "Laufschuh",
        "idea": "Neutraler Laufschuh in Bewegung; die Stollen werden zur Ferse hin flacher. Direkt verständlich.",
        "fill": (gradient("FF8A4C", "D8432B"), gradient("3A1710", "150705"), gradient("2A2A2A", "0C0C0C")),
        "groups": [[layer("schnuerung", laces, "E4562F", "7A2414", "333333", glass=False)],
                   [layer("obermaterial", [path(upper, move)], "FFFFFF", "FF8A5C", "FFFFFF")],
                   [layer("sohle", [path(midsole, move)], "FFE3C2", "FFD2A8", "C4C4C4"),
                    layer("stollen", lugs, "4A1A12", "FF6A3D", "FFFFFF", glass=False)]],
    }


# ---------------------------------------------------------------- 3 Zählwerk: Kilometerzähler mit laufender letzter Walze
def zaehlwerk():
    def zero(x):
        return path(f"M{x + 82} 396 C{x + 134} 396 {x + 150} 444 {x + 150} 512 C{x + 150} 580 {x + 134} 628 {x + 82} 628 "
                    f"C{x + 30} 628 {x + 14} 580 {x + 14} 512 C{x + 14} 444 {x + 30} 396 {x + 82} 396 Z "
                    f"M{x + 82} 444 C{x + 66} 444 {x + 62} 470 {x + 62} 512 C{x + 62} 554 {x + 66} 580 {x + 82} 580 "
                    f"C{x + 98} 580 {x + 102} 554 {x + 102} 512 C{x + 102} 470 {x + 98} 444 {x + 82} 444 Z", rule="evenodd")

    def four(x):
        return path(f"M{x + 84} 396 L{x + 134} 396 L{x + 134} 534 L{x + 156} 534 L{x + 156} 580 L{x + 134} 580 L{x + 134} 628 "
                    f"L{x + 84} 628 L{x + 84} 580 L{x + 8} 580 L{x + 8} 538 Z M{x + 84} 472 L{x + 50} 534 L{x + 84} 534 Z",
                    rule="evenodd")

    def two(x, y):
        return path(f"M{x + 18} {y + 76} C{x + 18} {y + 28} {x + 46} {y} {x + 84} {y} C{x + 124} {y} {x + 148} {y + 26} {x + 148} {y + 68} "
                    f"C{x + 148} {y + 102} {x + 130} {y + 126} {x + 92} {y + 158} L{x + 78} {y + 184} L{x + 150} {y + 184} "
                    f"L{x + 150} {y + 232} L{x + 16} {y + 232} L{x + 16} {y + 190} C{x + 82} {y + 128} {x + 98} {y + 104} {x + 98} {y + 76} "
                    f"C{x + 98} {y + 58} {x + 92} {y + 48} {x + 82} {y + 48} C{x + 72} {y + 48} {x + 66} {y + 58} {x + 66} {y + 78} Z")

    xs = [124, 424, 724]
    drums = [rect(x, 282, 176, 460, 52) for x in xs[:2]]
    rolling = [rect(xs[2], 282, 176, 460, 52)]
    # Letzte Walze rollt gerade weiter: Ziffer 2 steht tiefer, von der Ziffer davor ist noch der Fuß zu sehen.
    digits = [zero(xs[0] + 6), four(xs[1] + 6)]
    moving = [two(xs[2] + 5, 456), path(f"M{xs[2] + 66} 282 L{xs[2] + 114} 282 L{xs[2] + 114} 346 L{xs[2] + 146} 346 "
                                     f"L{xs[2] + 146} 392 L{xs[2] + 34} 392 L{xs[2] + 34} 346 L{xs[2] + 66} 346 Z")]
    track = [rect(124, 806, 776, 46, 23)]
    done = [rect(124, 806, 560, 46, 23)]
    return {
        "dir": "3-zaehlwerk", "name": "Zählwerk", "icon": "Zaehlwerk",
        "idea": "Kilometerzähler: die letzte Walze läuft weiter, darunter der Weg bis zur nächsten Wartung.",
        "fill": (gradient("2E3440", "12151B"), gradient("14171D", "040506"), gradient("262626", "0A0A0A")),
        "groups": [[layer("ziffern", digits, "171B22", "F2F4F8", "151515", glass=False),
                    layer("ziffern-laufend", moving, "2A1A00", "1C1200", "151515", glass=False),
                    layer("weg", done, "FFB020", "FFB020", "FFFFFF", glass=False)],
                   [layer("walzen", drums, "F4F6FA", "333A47", "E4E4E4"),
                    layer("walze-laufend", rolling, "FFB020", "FFB020", "FFFFFF"),
                    layer("strecke", track, "5A6272", "3A404C", "555555", glass=False)]],
    }


# ---------------------------------------------------------------- 4 Kettenglied: Verschleiß misst man an der Kette
def kettenglied():
    turn = "rotate(-36 512 512)"

    def plate(x1, x2, r=150, waist=96, y=512):
        dx, dy = r * math.cos(math.radians(48)), r * math.sin(math.radians(48))
        mid = (x1 + x2) / 2
        return (f"M{x1 + dx:.1f} {y - dy:.1f} Q{mid} {y - waist * 0.55:.1f} {x2 - dx:.1f} {y - dy:.1f} "
                f"A{r} {r} 0 1 1 {x2 - dx:.1f} {y + dy:.1f} Q{mid} {y + waist * 0.55:.1f} {x1 + dx:.1f} {y + dy:.1f} "
                f"A{r} {r} 0 1 1 {x1 + dx:.1f} {y - dy:.1f} Z")

    front = [path(plate(236, 548), turn)]
    back = [path(plate(548, 818, r=128, waist=80), turn)]
    pins = [circle(236, 512, 62, turn), circle(818, 512, 52, turn)]
    shared = [circle(548, 512, 66, turn)]
    return {
        "dir": "4-kettenglied", "name": "Kettenglied", "icon": "Kettenglied",
        "idea": "Zwei Kettenglieder, der verschlissene Bolzen leuchtet. Für Rad und Bauteile, sehr klar in klein.",
        "fill": (gradient("3F6BF0", "1B2C8F"), gradient("141B45", "060820"), gradient("2A2A2A", "0C0C0C")),
        "groups": [[layer("bolzen-verschlissen", shared, "FFC53D", "FFC53D", "7A7A7A", glass=False),
                    layer("bolzen", pins, "1F349E", "0B1030", "222222", glass=False)],
                   [layer("lasche-vorn", front, "FFFFFF", "7D9BFF", "FFFFFF")],
                   [layer("lasche-hinten", back, "A9C0FF", "3E55B8", "B0B0B0")]],
    }


# ---------------------------------------------------------------- 5 Bahn-E: E aus Laufbahn, Punkt = aktueller Stand
def bahn():
    outer = ("M786 148 L496 148 A364 364 0 0 0 496 876 L786 876 A72 72 0 0 0 786 732 L496 732 "
             "A220 220 0 0 1 496 292 L786 292 A72 72 0 0 0 786 148 Z")
    lane = ("M786 213 L496 213 A299 299 0 0 0 496 811 L786 811 L786 795 L496 795 "
            "A283 283 0 0 1 496 229 L786 229 Z")
    middle = "M420 440 L626 440 A72 72 0 0 1 626 584 L420 584 A72 72 0 0 1 420 440 Z"
    runner = [circle(786, 512, 78)]
    return {
        "dir": "5-bahn", "name": "Bahn-E", "icon": "Bahn",
        "idea": "Das E von Eingelaufen als Laufbahn, der Punkt ist der aktuelle Stand. Eigenständige Wortmarke ohne Text.",
        "fill": (gradient("FFF6E8", "F2E2C6"), gradient("231A14", "0B0806"), gradient("262626", "0A0A0A")),
        "groups": [[layer("stand", runner, "0F6B61", "4CCBB8", "B4B4B4"),
                    layer("spur", [path(lane)], "FFF1DC", "2A140D", "333333", glass=False)],
                   [layer("bahn", [path(outer), path(middle)], "D4502C", "F0704A", "FFFFFF")]],
    }


def write_design(design):
    folder = ROOT / design["dir"]
    assets = folder / f"{design['icon']}.icon" / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    for old in assets.glob("*.svg"):
        old.unlink()
    light, dark, tinted = design["fill"]
    groups = []
    for members in design["groups"]:
        for item in members:
            (assets / f"{item['name']}.svg").write_text(item["svg"])
        glass = any(item["json"]["glass"] for item in members)
        groups.append({"layers": [item["json"] for item in members], "specular": glass,
                       "shadow": {"kind": "neutral", "opacity": 0.4 if glass else 0.0},
                       "translucency": {"enabled": False, "value": 0.5}})
    # Kein zusätzliches "fill": es würde die Werte je Darstellung überdecken (pruefe.py achtet darauf).
    spec = {"fill-specializations": [{"value": light}, {"appearance": "dark", "value": dark},
                                     {"appearance": "tinted", "value": tinted}],
            "groups": groups, "supported-platforms": {"squares": "shared"}}
    (assets.parent / "icon.json").write_text(json.dumps(spec, indent=2) + "\n")
    (folder / "idee.txt").write_text(f"{design['name']}\n{design['idea']}\n")


if __name__ == "__main__":
    for make in (profil, laufschuh, zaehlwerk, kettenglied, bahn):
        write_design(make())
    subprocess.run(["swift", str(ROOT / "tafeln.swift"), str(ROOT)], check=True)

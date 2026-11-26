# App-Icon: Entwürfe

Stand 26.11.2026. **A „Profil“ ist das App-Icon** (Linos Wahl vom 25.11.): `App/Resources/AppIcon.icon`.
Übersicht aller Entwürfe: [`uebersicht.png`](uebersicht.png) (Stand der Auswahl, unten das damalige Icon).

| Ordner | Idee | Stärke | Schwäche (aus den Kleingrößen) |
|---|---|---|---|
| [`1-profil`](1-profil/tafel.png) | Laufsohle von unten, abgelaufene Ferse in Gelb | zeigt „Verschleiß“ selbst; Farbwelt der App | bei 20 pt verschwimmen die Fersenstollen; getönt ohne Gelb weniger deutlich |
| [`2-laufschuh`](2-laufschuh/tafel.png) | neutraler Laufschuh, Stollen hinten flacher | sofort verständlich | wirkt wie eine Lauf-App, Rad und anderes Gerät kommen nicht vor; Schnürung bei 20 pt weg |
| [`3-zaehlwerk`](3-zaehlwerk/tafel.png) | Kilometerzähler mit laufender Walze und Wartungsstrecke | zeigt „Kilometer“ | Ziffern bei 20 pt kaum lesbar; Apple rät von Text im Icon ab |
| [`4-kettenglied`](4-kettenglied/tafel.png) | zwei Kettenglieder, ein Bolzen leuchtet | am klarsten in klein | nur Fahrrad; kann als „Verknüpfung“ gelesen werden; getönt verliert der Bolzen das Gelb |
| [`5-bahn`](5-bahn/tafel.png) | E als Laufbahn, Punkt = Stand | eigenständige Marke | kann an ein Eurozeichen erinnern; Verschleiß steckt nicht darin |

## Empfehlung
**1 · Profil.** Es ist der einzige Entwurf, der den Kern der App (einlaufen, Verschleiß) ohne Erklärung zeigt, bleibt beim
Türkis der App und ist bis 29 pt klar. Wer maximale Lesbarkeit in klein will, nimmt **4 · Kettenglied**.

## Was je Entwurf geprüft ist
- Darstellungen nach Apple (HIG „App icons“, Stand 28.10.2026): hell, dunkel, klar hell, klar dunkel, getönt hell, getönt dunkel.
- Kleingrößen in echten Pixeln bei @3x: 60 pt (Homescreen), 40 pt (Spotlight), 29 pt (Einstellungen), 20 pt (Mitteilung).
- Homescreen-Mockup hell und dunkel mit neutralen Platzhalter-Apps.
- Rendering mit `ictool` aus Icon Composer (Xcode 27.2), Material von iOS 27; die Übersicht zeigt zusätzlich iOS 26.
- Getönt ist mit einer türkisen Beispieltönung gerendert; die echte Farbe wählt jede Person selbst.
- Nur eigene Formen, keine Marken, Logos, Apple-Geräte oder Schriften; keine eingebackenen Schatten oder Masken.

## Aufbau und Befehle
- `build.py`: einzige Quelle der Geometrie; schreibt je Entwurf `<Name>.icon` (SVG-Ebenen 1024 × 1024 + `icon.json`) und ruft `tafeln.swift` auf.
- `python3 design/icon/build.py` erzeugt alles neu (Zwischenbilder in `render/`, nicht eingecheckt).
- `python3 design/icon/pruefe.py` prüft: mindestens vier Entwürfe, saubere SVG-Ebenen, `actool` übersetzt jedes `.icon`,
  `ictool` rendert alle Darstellungen und Größen, Mindestkontrast bei 20 pt, Entwürfe unterscheiden sich, Tafeln vorhanden.

## Übernahme (26.11.2026)
- `App/Resources/AppIcon.icon` ist eine unveränderte Kopie von `1-profil/Profil.icon`; `pruefe.py` wird rot, wenn beide
  auseinanderlaufen. Änderungen also in `build.py`, dann neu erzeugen und kopieren.
- `ASSETCATALOG_COMPILER_APPICON_NAME` bleibt `AppIcon`; `AppIcon.appiconset` und `scripts/make-icon.swift` sind entfernt.
  Das Deployment Target ist iOS 26, ein Ersatzbild für ältere Systeme ist nicht nötig.
- Prüfbilder aus dem Simulator (Homescreen hell und dunkel, Kleingrößen): `../../docs/screenshots/icon/`.

# App-Icon: Entwürfe

Stand 25.11.2026. **Noch nichts übernommen:** Die App nutzt weiter `App/Resources/Assets.xcassets/AppIcon`.
Übersicht aller Entwürfe neben dem aktuellen Icon: [`uebersicht.png`](uebersicht.png).

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

## Übernahme (erst nach Linos Wahl)
`<Name>.icon` als `App/Resources/AppIcon.icon` ins Projekt, `AppIcon.appiconset` entfernen, `ASSETCATALOG_COMPILER_APPICON_NAME`
bleibt `AppIcon`; danach Build, `actool`-Ausgabe und Homescreen im Simulator prüfen. Das Deployment Target ist iOS 26, ein
Ersatzbild für ältere Systeme ist nicht nötig. `scripts/make-icon.swift` entfällt dann.

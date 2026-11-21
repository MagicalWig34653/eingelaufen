# Namensrecherche (E-01)

**Stand:** 21.11.2026, 19:13 UTC · nur Recherche, **nichts registriert, reserviert oder veröffentlicht** · **keine Verfügbarkeitsgarantie** (siehe „Grenzen“).
Entscheidung trifft Lino (Karte E-01). Die Bundle-ID unten ist ein Vorschlag, nicht festgelegt.

## Ergebnis

Geprüft wurden 14 Kandidaten (Vorauswahl), 5 davon vertieft, 4 zur Wahl gestellt. Reihenfolge nach Kollisionsfreiheit, danach Passung. Passung: Die App deckt alle Sportarten ab, nicht jede liefert Distanz (Spec 5.2), der Name soll deshalb nicht nur auf Kilometer zielen.

| Rang | Name | App Store (DE, AT, CH, US) | GitHub exakt | Domains laut RDAP | Passung |
|---|---|---|---|---|---|
| 1 | **Rüstkiste** | kein Treffer | kein Repo, kein Konto (auch ohne Umlaut `rustkiste`) | .de und .com frei | Kiste mit Ausrüstung, sportartneutral. Empfehlung. |
| 2 | **Kilomeister** | kein Treffer | kein Repo; Konto `kilomeister` existiert (1 Treffer) | .de und .com frei | einprägsam, zielt aber auf Distanz. |
| 3 | **Ausrüstbuch** | kein Treffer | kein Repo, kein Konto | .de und .com frei | beschreibend und sportartneutral, markenrechtlich eher schwach schutzfähig. |
| 4 | **Spurwerk** | kein Treffer | 8 Repos, Konten `SpurWerk` und `Spurwerk-AI` | .de und .com **registriert** | neutral; Domain und GitHub-Name belegt. |
| – | Kettenwerk | kein Treffer | Konto `Kettenwerk` | .de und .com **registriert** | zielt auf Fahrradketten, nicht zur Wahl gestellt. |

Bereits belegt (App-Store-Namenstreffer in der Vorauswahl, daher verworfen): Gearlog (u. a. „GearLog“ von Kit Kline), Gearwise („Gearwise“ von LIMAK SOLUTIONS PTY LTD), Kitlog („Kitlog: Organizer für Kreative“), Rigbook („RigBook: RV Care Log“), Kitwise („Kitwise“ von NYASB LLC), Rigwise. Weitere ohne Namenstreffer, aber nicht weiterverfolgt: Wearkit (endet auf „Kit“, Verwechslung mit Apple-Frameworks), Verschleißbuch (negativer Ton), Werkstück (allgemeines Wort), Rüstkiste-Varianten.

Vorschlag Bundle-ID (nur wenn Lino wählt, nicht registriert): `de.linolaske.ruestkiste`, `de.linolaske.kilomeister`, `de.linolaske.ausruestbuch`, `de.linolaske.spurwerk`.

## Quellen und Methode (reproduzierbar, 21.11.2026)

1. **App Store:** iTunes Search API, `https://itunes.apple.com/search?term=<Name>&entity=software&country=<de|at|ch|us>&limit=50`. Treffer = Name der App enthält den normalisierten Suchbegriff (ohne Umlaute/Sonderzeichen verglichen). Ergebnis: für alle vier Namen und fünf Kandidaten 0 Namenstreffer in allen vier Storefronts.
2. **GitHub:** `gh api search/repositories -f q="<name> in:name"` und `search/users -f q="<name> in:login"` (Zahlen oben).
3. **Domains:** RDAP, `https://rdap.denic.de/domain/<name>.de` (404 = frei, 200 = registriert) und `https://rdap.verisign.com/com/v1/domain/<name>.com`. `.app` (`https://rdap.nic.google/domain/<name>.app`) war nicht erreichbar, **nicht geprüft**.
4. **Web:** Websuche mit `"<Name>" App OR Marke OR Firma` für alle fünf; kein Treffer, der den Begriff als App, Marke oder Firma nutzt. Nebenbefunde ohne Bezug: Kettinger-App (Bäckerei), FB Ketten GmbH, KETTENWULF (US-Markenanmeldung), Kupferwerk (App-Agentur).
5. Rohdaten der Läufe liegen nicht im Repo (nur diese Zusammenfassung).

## Grenzen (bitte vor der Wahl lesen)

- **Markenregister nicht geprüft.** DPMA, EUIPO und WIPO bieten keine abfragbare Schnittstelle ohne Konto; Lino oder eine Fachperson prüft vor der Wahl: DPMAregister `https://register.dpma.de/DPMAregister/marke/basis`, TMview `https://www.tmdn.org/tmview/`, WIPO Global Brand Database `https://branddb.wipo.int/`. Gesucht werden Klassen 9 und 42, auch Schreibweisen und ähnlich klingende Namen.
- Die iTunes-Suche zeigt nur **derzeit gelistete** Apps in diesen Storefronts. Entfernte, unveröffentlichte oder in App Store Connect reservierte Namen sind öffentlich nicht sichtbar. Die endgültige Verfügbarkeit zeigt erst App Store Connect, und das legt Lino an.
- Eine Websuche kann das Fehlen einer Nutzung nicht beweisen, nur nichts finden.
- Domainstatus ist eine Momentaufnahme; Registrierung macht nur Lino.
- Kein Rechtsrat.

---

# Runde 2 (21.11.2026, Abend): „Keines der Vier“

Lino hat alle vier Namen der Runde 1 abgelehnt. Die Runde 1 bestand aus deutschen Komposita (-kiste, -meister, -buch, -werk). Runde 2 geht bewusst in andere Richtungen: Redewendungen und Bilder aus dem Gebrauch von Ausrüstung statt Bezeichnungen für „Behälter“ oder „Zähler“. **Nichts registriert, reserviert oder veröffentlicht. Keine Verfügbarkeitsgarantie, Markenregister weiterhin nicht abgefragt.**

Geprüft: 38 Kandidaten per iTunes-API. Kurze Alltagswörter (Patina, Spind, Zeug, Quiver, Tread, Cairn, Tally, Odo, Standzeit, Haltbar, Mileo, Tero, Kintsugi, Wearly, Seasoned, Ruvo) fielen durch: App-Store-Namenstreffer, bei Tread/Cairn/Odo sogar im Thema Reifen, Wandern, Kilometer. Hardwear fiel durch (Mountain Hardwear, Outdoor-Marke von Columbia, klingt gleich); Usus (450 GitHub-Repos, .de/.com belegt) auch.

| Name | Idee | App Store DE/AT/CH/US (Namenstreffer) | GitHub (Repos / Konten) | .de / .com (RDAP) | Web |
|---|---|---|---|---|---|
| **Altgedient** | „altgedient“ = lange treu im Dienst; passt zu Schuhen, Kette, Helm gleichermaßen | 0 | 0 / 0 | frei / frei | kein Treffer als App, Marke oder Firma |
| **Eingelaufen** | Schuhe, Reifen, Sattel sind „eingelaufen“ (eingefahren); auch „Training eingelaufen“ | 0 | 0 / 0 | frei / frei | kein Treffer |
| **Gefährte** | Ausrüstung als Begleiter über viele Einheiten; Bundle ASCII `gefaehrte` | 0 | 4 / 1 (`gefaehrte`) | belegt / frei | kein Treffer im Sportkontext |
| **Wellworn** | englisch „well-worn“, gut getragen; gleiche Idee wie Altgedient, international | 0 | 18 / 80 | belegt / belegt | kein Treffer; nahe Verwandte im Thema: WearLog, WearTracker, GearTracking (andere Namen) |
| *Reserve:* Zeughaus | Arsenal/Lager für Ausrüstung | 0 | 7 / 3 | belegt / belegt | kein Sporttreffer; bekannter Begriff (Museen, Kinos), Verwechslung wahrscheinlich |

Bundle-ID-Vorschläge (nur falls gewählt, nicht registriert): `de.linolaske.altgedient`, `de.linolaske.eingelaufen`, `de.linolaske.gefaehrte`, `de.linolaske.wellworn`.

**Methode:** wie Runde 1 (iTunes Search API je Storefront, Treffer = Name beginnt mit dem Begriff vor „ - “ oder „:“; GitHub-Suche `in:name` / `in:login`; RDAP für .de und .com; `.app` nicht erreichbar, nicht geprüft). Zusätzlich je Name eine Websuche; sie liefert nur „nichts gefunden“, kein Beweis der Freiheit. **Grenzen:** wie oben (Markenregister DPMA/TMview/WIPO prüft Lino, Klassen 9 und 42, auch ähnlich klingende Schreibweisen; nicht gelistete oder reservierte App-Namen sind unsichtbar; Kein Rechtsrat). Besonders prüfen: „Altgedient“/„Eingelaufen“ sind gebräuchliche deutsche Wörter, daher ist Schutzfähigkeit als Marke eher schwach, dafür Kollision gering.

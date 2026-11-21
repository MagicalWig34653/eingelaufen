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

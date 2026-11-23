# Status und Übergabe

**Stand:** 23.11.2026 · Quelle der Wahrheit für den Arbeitsstand, bei jeder Änderung mitpflegen.
**Arbeitstitel GearFlow – Name vorläufig.** Keine Bundle-ID, kein App-Store-Connect-Eintrag, keine Signierung mit Team, bis Lino E-01 entschieden hat.

## Entscheidungen von Lino (21.11.2026)
- **E-02:** Deployment Target **iOS 26+** (Swift 6, aktuelle SwiftData/ActivityKit).
- **E-03:** GitHub **privat**, bis der Name steht. Repo: `MagicalWig34653/sportausruestung` (privat, vor dem Push mit gitleaks auf Geheimnisse geprüft). Kein öffentliches Repo, keine Lizenz bis zur Namensentscheidung.
- **E-01:** Agent recherchiert 3–5 Namensvorschläge mit Kollisionsprüfung, Lino wählt. Ergebnis: `docs/NAMENSRECHERCHE.md` (4 Vorschläge, Quellen, Grenzen; ohne Verfügbarkeitsgarantie, Markenregister nicht abgefragt). **Wartet auf Linos Wahl.**

## Was steht
| Bereich | Stand |
|---|---|
| Spec | `docs/SPEC.md` v1.0 (Kopie von Linos Datei, SHA-256 `1ed20b01…ab81b4`), unverändert |
| Architektur | `docs/ARCHITEKTUR.md` |
| Plan, Meilensteine M0–M9, Testmatrix, Annahmen, Entscheidungen | `docs/PLAN.md` |
| Apple-Vorgaben geprüft (HealthKit, Hintergrund, Notifications, Live Activities, SwiftData, Privacy) | `docs/PLATTFORM.md` |
| Code | Nur `Packages/GearCore` (namensunabhängig, `Packages/GearCore/test.sh` oder `swift test`): **M1 vollständig im Kern**: M1a (Katalog, HealthKit-Mapping, Vorlagen), M1b (InstallationGraph, LedgerBuilder, UsageQuery, LedgerProjection), M1c (AssignmentEngine, Inbox-Reducer, Korrektur/Regel-Lernen, ImportReconciler, Backup v1 mit Validator, Vorschau und Wiederherstellen). **164 Tests in 10 Suites grün, Zeilenabdeckung 96,9 %** (Ziel ≥ 90 %). T-01…T-14 haben je einen benannten Test. Kein Xcode-Projekt, keine Bundle-ID. |
| Board | Todolino-Unterprojekt `1F2204B9-850F-4A39-8A56-7232BE9C754F`, Repo-Schlüssel `local/sportausruestung` |

## Nächste Schritte
1. **M1 `GearCore`**: Kern fertig, Abnahme durch Lino steht aus (Board M1/M1a/M1c). Bekannte Grenzen: der Reconciler übernimmt bei Ersatz (P-05) noch keine Segmente (kommt mit M3); Annahme P-09 (ein einziger verfügbarer Kandidat wird automatisch zugeordnet) ist von der Spec nicht gedeckt (6.2/17: automatisch nur explizite Regeln und Presets): `EnginePolicy.autoAssignSoleCandidate` steht seit dem Gegenreview auf **`false`**, der einzige Kandidat wird nur vorgeschlagen; die Option bleibt und wird nur auf Linos ausdrückliche Entscheidung eingeschaltet; Backup enthält kein Ledger (wird nach dem Wiederherstellen neu gebaut), `ImportCursor`/`AppSettings` gehören zur App.
2. Nach E-01/E-02: M2 App-Fundament (XcodeGen, SchemaV1 vollständig, PersistenceActor).
3. Danach M3 (mit Gerätespike S-1) und M5 parallel.

## Wartet auf Lino
- **E-01** Wahl aus den vier Vorschlägen in `docs/NAMENSRECHERCHE.md`, dann Bundle-ID (blockiert M2).
- **E-03 (Rest)** nach der Namenswahl: öffentlich + Lizenz oder privat lassen.
- **E-04** Gerätetests S-1 (nach M3) und S-2 (nach M7).

## Hinweise
- Mac-Platte war am 21.11. rot (22,5 GB frei): Xcode-/Simulator-Arbeit erst bei Platte ≥ Gelb; DerivedData nach `build/`.

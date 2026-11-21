# Status und Übergabe

**Stand:** 21.11.2026 · Quelle der Wahrheit für den Arbeitsstand, bei jeder Änderung mitpflegen.
**Arbeitstitel GearFlow – Name vorläufig.** Keine Bundle-ID, kein App-Store-Connect-Eintrag, keine Signierung mit Team, bis Lino E-01 entschieden hat.

## Was steht
| Bereich | Stand |
|---|---|
| Spec | `docs/SPEC.md` v1.0 (Kopie von Linos Datei, SHA-256 `1ed20b01…ab81b4`), unverändert |
| Architektur | `docs/ARCHITEKTUR.md` |
| Plan, Meilensteine M0–M9, Testmatrix, Annahmen, Entscheidungen | `docs/PLAN.md` |
| Apple-Vorgaben geprüft (HealthKit, Hintergrund, Notifications, Live Activities, SwiftData, Privacy) | `docs/PLATTFORM.md` |
| Code | **keiner** (bewusst, Name offen) |
| Board | Todolino-Unterprojekt `1F2204B9-850F-4A39-8A56-7232BE9C754F`, Repo-Schlüssel `local/sportausruestung` |

## Nächste Schritte
1. **M1 `GearCore`** kann sofort starten (namensunabhängig, nur `swift test`, kein Simulator). Reihenfolge: M1b Montage/Ledger/Usage → M1a Katalog/Mapping und M1c Engine/Inbox/Reconciler/Backup parallel.
2. Nach E-01/E-02: M2 App-Fundament (XcodeGen, SchemaV1 vollständig, PersistenceActor).
3. Danach M3 (mit Gerätespike S-1) und M5 parallel.

## Wartet auf Lino
- **E-01** Produktname + Bundle-ID (blockiert M2).
- **E-02** Deployment Target (Empfehlung iOS 26+).
- **E-03** Repo-Sichtbarkeit/Lizenz (blockiert nur Push).
- **E-04** Gerätetests S-1 (nach M3) und S-2 (nach M7).

## Hinweise
- Mac-Platte war am 21.11. rot (22,5 GB frei): Xcode-/Simulator-Arbeit erst bei Platte ≥ Gelb; DerivedData nach `build/`.

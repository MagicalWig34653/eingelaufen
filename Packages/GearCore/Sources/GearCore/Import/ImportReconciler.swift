import Foundation

// Import-Abgleich (SPEC 5.2, 6.1, 6.2, 12; ARCHITEKTUR 5). Rein und deterministisch: nimmt den Datenstand und einen
// Batch aus der Quelle (HealthKit-Anchored-Query: Änderungen + ausdrücklich gemeldete Löschungen) und liefert den
// neuen Stand samt Ledger-Änderungen. Der PersistenceActor schreibt Ergebnis und HealthKit-Anker in einem Commit (A-05).
//
// Harte Regeln:
// - I-07: je Quell-ID genau ein `ActivityRecord`; wiederholter Import ändert nichts (T-05).
// - Löschung nur auf ausdrückliche Meldung (`deletedSourceIDs`); ein leerer oder fehlender Batch löscht nie (SPEC 11).
// - Engine und Regeln laufen nur für *neu angelegte* Aktivitäten; abgeschlossene bleiben unberührt (SPEC 6.3).
// - Zusammenführen wird höchstens vorgeschlagen, nie ausgeführt; Zeitüberschneidung allein genügt nie (SPEC 5.2).

/// Ein Training aus der Quelle, bereits in Basiseinheiten normalisiert. Distanz `nil` = nicht geliefert, nie `0`.
public struct IncomingWorkout: Hashable, Sendable {
    public var sourceID: String
    public var sportType: SportType
    public var startAt: Date
    public var endAt: Date
    public var distanceMeters: Double?
    public var durationSeconds: Double
    public var isIndoor: Bool?
    /// Herkunft laut Quelle (Bundle-ID und Anzeigename der schreibenden App/des Geräts).
    public var sourceBundleID: String?
    public var sourceName: String?
    /// Nur bei Multisport (siehe `multisportSegments`); sonst leer.
    public var segments: [IncomingSegment]

    public init(sourceID: String, sportType: SportType, startAt: Date, endAt: Date,
                distanceMeters: Double? = nil, durationSeconds: Double, isIndoor: Bool? = nil,
                sourceBundleID: String? = nil, sourceName: String? = nil, segments: [IncomingSegment] = []) {
        self.sourceID = sourceID
        self.sportType = sportType
        self.startAt = startAt
        self.endAt = endAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.isIndoor = isIndoor
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.segments = segments
    }

    /// Segmente gibt es nur, wenn die Abschnitte verschiedene Sportarten haben (SPEC 5.2); Intervalle einer Sportart
    /// bleiben eine Aktivität. Sortiert nach Beginn.
    public static func multisportSegments(_ parts: [IncomingSegment]) -> [IncomingSegment] {
        guard Set(parts.map(\.sportType)).count > 1 else { return [] }
        return parts.sorted { ($0.startAt, $0.sportType.rawValue) < ($1.startAt, $1.sportType.rawValue) }
    }
}

/// Abschnitt eines Trainings aus der Quelle. Distanz nur, wenn die Quelle sie für diesen Abschnitt liefert (T-08).
public struct IncomingSegment: Hashable, Sendable {
    public var sportType: SportType
    public var startAt: Date
    public var endAt: Date
    public var distanceMeters: Double?

    public init(sportType: SportType, startAt: Date, endAt: Date, distanceMeters: Double? = nil) {
        self.sportType = sportType
        self.startAt = startAt
        self.endAt = endAt
        self.distanceMeters = distanceMeters
    }
}

public struct ImportBatch: Hashable, Sendable {
    public var upserts: [IncomingWorkout]
    public var deletedSourceIDs: [String]
    public init(upserts: [IncomingWorkout] = [], deletedSourceIDs: [String] = []) {
        self.upserts = upserts
        self.deletedSourceIDs = deletedSourceIDs
    }
}

public struct Replacement: Hashable, Sendable {
    public var old: UUID
    public var new: UUID
    public init(old: UUID, new: UUID) { self.old = old; self.new = new }
}

public enum MergeReason: String, Hashable, Sendable {
    case manualMatchesImported
    case sameSpanDifferentSources
}

/// Vorschlag, zwei Einträge zusammenzuführen. Wird dem Nutzer angeboten, nie automatisch ausgeführt.
public struct MergeSuggestion: Hashable, Sendable {
    public var keptID: UUID
    public var otherID: UUID
    public var reason: MergeReason
}

public struct ReconcileOutput: Equatable, Sendable {
    public var dataset: GearDataset
    /// Reihenfolge-unabhängig anwendbar auf eine `LedgerProjection`; Ergebnis == Neuaufbau (I-10).
    public var ledgerChanges: [LedgerChange] = []
    public var inserted: [UUID] = []
    public var updated: [UUID] = []
    public var tombstoned: [UUID] = []
    public var replaced: [Replacement] = []
    /// Aktivitäten, die die Engine ohne Nachfrage zugeordnet hat.
    public var autoAssigned: [UUID] = []
    public var pendingCreated: [UUID] = []
    public var mergeSuggestions: [MergeSuggestion] = []
    /// `true`, wenn der Datenstand bitgleich geblieben ist (wiederholter Import).
    public var isUnchanged = false
}

public enum ImportReconciler {
    /// P-05: Zeitfenster für „sehr starke, eindeutige Übereinstimmung“ bei Ersatz (Löschen + Neuanlage).
    public static let replacementTolerance: TimeInterval = 60
    /// Manuell vs. importiert: Start auf 5 Minuten genau, Dauer auf max(60 s, 5 %).
    public static let manualMatchStartTolerance: TimeInterval = 300

    public static func reconcile(_ dataset: GearDataset, _ batch: ImportBatch, now: Date,
                                 calendar: Calendar = Calendar(identifier: .gregorian),
                                 policy: EnginePolicy = EnginePolicy(),
                                 makeID: @escaping () -> UUID = UUID.init) -> ReconcileOutput {
        var run = Run(dataset: dataset, now: now, makeID: makeID,
                      context: AssignmentContext(dataset: dataset, history: AssignmentHistory.confirmed(from: dataset),
                                                 calendar: calendar, policy: policy))
        run.process(batch)
        return run.finish(comparedTo: dataset)
    }

    /// Manuelle Aktivität (SPEC 6.4) durchläuft dieselbe Zuordnungs- und Wartungslogik wie ein Import.
    public static func addManual(_ activity: ActivityRecord, to dataset: GearDataset, now: Date,
                                 calendar: Calendar = Calendar(identifier: .gregorian),
                                 policy: EnginePolicy = EnginePolicy(),
                                 makeID: @escaping () -> UUID = UUID.init) -> ReconcileOutput {
        var run = Run(dataset: dataset, now: now, makeID: makeID,
                      context: AssignmentContext(dataset: dataset, history: AssignmentHistory.confirmed(from: dataset),
                                                 calendar: calendar, policy: policy))
        guard !run.dataset.activities.contains(where: { $0.id == activity.id }) else { return run.finish(comparedTo: dataset) }
        run.dataset.activities.append(activity)
        run.out.inserted.append(activity.id)
        run.out.ledgerChanges.append(.upsertActivity(activity))
        run.decide(for: activity, forced: nil)
        run.changedForMerge.append(activity.id)
        return run.finish(comparedTo: dataset)
    }

    // MARK: Ablauf

    private struct Run {
        var dataset: GearDataset
        let now: Date
        let makeID: () -> UUID
        let context: AssignmentContext
        var out: ReconcileOutput
        var changedForMerge: [UUID] = []

        init(dataset: GearDataset, now: Date, makeID: @escaping () -> UUID, context: AssignmentContext) {
            self.dataset = dataset
            self.now = now
            self.makeID = makeID
            self.context = context
            self.out = ReconcileOutput(dataset: dataset)
        }

        func index(ofSource sourceID: String) -> Int? {
            dataset.activities.firstIndex { $0.source == .healthKit && $0.sourceID == sourceID }
        }

        mutating func process(_ batch: ImportBatch) {
            // 1. Mehrfach gelieferte Quell-ID: letzter Stand gewinnt; feste Reihenfolge (Start, Quell-ID).
            var latest: [String: IncomingWorkout] = [:]
            for w in batch.upserts { latest[w.sourceID] = w }
            let incoming = latest.values.sorted { ($0.startAt, $0.sourceID) < ($1.startAt, $1.sourceID) }
            // Upsert und Löschung derselben Quell-ID im selben Batch: der Upsert gilt.
            let deletions = Set(batch.deletedSourceIDs).subtracting(latest.keys)

            // 2. Bekannte Quell-IDs: aktualisieren bzw. wiederbeleben, nie neu entscheiden.
            var fresh: [IncomingWorkout] = []
            var revived: [ActivityRecord] = []
            for w in incoming {
                guard let i = index(ofSource: w.sourceID) else { fresh.append(w); continue }
                // Vom Nutzer gelöscht (M8): die Quelle darf ihn weder ändern noch wiederbeleben.
                if dataset.activities[i].removedByUser == true { continue }
                if let record = update(at: i, with: w) {
                    if record.deletedAt == nil, wasTombstoned(record.id) { revived.append(record) }
                }
            }

            // 3. Ersatz-Erkennung (P-05): Löschung + Neuanlage nur bei eindeutiger gegenseitiger Übereinstimmung.
            let deletable = dataset.activities.filter {
                $0.source == .healthKit && $0.deletedAt == nil && $0.sourceID.map(deletions.contains) == true
            }.sorted { ($0.startAt, $0.sourceID ?? "") < ($1.startAt, $1.sourceID ?? "") }

            var matchesOfNew: [String: [ActivityRecord]] = [:]
            var matchesOfOld: [UUID: [String]] = [:]
            for n in fresh {
                for o in deletable where similar(n, o) {
                    matchesOfNew[n.sourceID, default: []].append(o)
                    matchesOfOld[o.id, default: []].append(n.sourceID)
                }
            }
            var pairs: [String: ActivityRecord] = [:]       // neue Quell-ID → ersetzte Aktivität
            var ambiguous: [String: [ActivityRecord]] = [:]  // neue Quell-ID → mögliche Vorgänger
            for n in fresh {
                guard let olds = matchesOfNew[n.sourceID] else { continue }
                if olds.count == 1, matchesOfOld[olds[0].id]?.count == 1 { pairs[n.sourceID] = olds[0] } else { ambiguous[n.sourceID] = olds }
            }

            // 4. Neue Aktivitäten in fester Reihenfolge anlegen.
            for w in fresh {
                let record = makeRecord(w)
                dataset.activities.append(record)
                out.inserted.append(record.id)
                out.ledgerChanges.append(.upsertActivity(record))
                changedForMerge.append(record.id)
                _ = updateSegments(of: record.id, with: w.segments)
                if let old = pairs[w.sourceID] {
                    carryOver(from: old, to: record)
                    out.replaced.append(Replacement(old: old.id, new: record.id))
                } else if let olds = ambiguous[w.sourceID] {
                    decide(for: record, forced: olds)
                } else {
                    decide(for: record, forced: nil)
                }
            }

            // 5. Wiederbelebte Einträge ohne Zuordnung und ohne offenen Eintrag bekommen eine Entscheidung.
            for r in revived {
                let hasAssignment = dataset.assignments.contains { $0.activityID == r.id }
                let hasOpen = dataset.pendings.contains { $0.activityID == r.id && !$0.state.isFinal }
                if !hasAssignment && !hasOpen { decide(for: r, forced: nil) }
            }

            // 6. Löschungen (auch die ersetzten Vorgänger): Aktivität tombstonen, offene Einträge schließen.
            for o in deletable { tombstone(o.id) }
        }

        // MARK: Update / Tombstone

        /// Gibt den aktualisierten Datensatz zurück, `nil` wenn sich nichts geändert hat.
        mutating func update(at i: Int, with w: IncomingWorkout) -> ActivityRecord? {
            var a = dataset.activities[i]
            let wasDeleted = a.deletedAt != nil
            let same = a.sportType == w.sportType && a.startAt == w.startAt && a.endAt == w.endAt
                && a.distanceMeters == w.distanceMeters && a.durationSeconds == w.durationSeconds && a.isIndoor == w.isIndoor
                && a.sourceBundleID == w.sourceBundleID && a.sourceName == w.sourceName
            let segmentsChanged = updateSegments(of: a.id, with: w.segments)
            if same && !segmentsChanged && !wasDeleted { return nil }
            a.sportType = w.sportType
            a.startAt = w.startAt
            a.endAt = w.endAt
            a.distanceMeters = w.distanceMeters      // nil bleibt nil
            a.durationSeconds = w.durationSeconds
            a.isIndoor = w.isIndoor
            a.sourceBundleID = w.sourceBundleID
            a.sourceName = w.sourceName
            a.deletedAt = nil
            a.revision += 1
            dataset.activities[i] = a
            out.updated.append(a.id)
            out.ledgerChanges.append(.upsertActivity(a))
            changedForMerge.append(a.id)
            if wasDeleted { revivedIDs.insert(a.id) }
            return a
        }

        // MARK: Segmente

        /// Zuordnung alt → neu: gleiche Sportart und Beginn innerhalb der Ersatz-Toleranz, jedes Ziel nur einmal.
        func matchSegments(_ old: [ActivitySegment], to new: [IncomingSegment]) -> [Int: ActivitySegment] {
            var result: [Int: ActivitySegment] = [:]
            for o in old.sorted(by: { ($0.startAt, $0.id.uuidString) < ($1.startAt, $1.id.uuidString) }) {
                let hit = new.indices.filter {
                    result[$0] == nil && new[$0].sportType == o.sportType
                        && abs(new[$0].startAt.timeIntervalSince(o.startAt)) <= ImportReconciler.replacementTolerance
                }.min { abs(new[$0].startAt.timeIntervalSince(o.startAt)) < abs(new[$1].startAt.timeIntervalSince(o.startAt)) }
                if let hit { result[hit] = o }
            }
            return result
        }

        /// Bringt die Segmente auf den Stand der Quelle. Passende behalten ihre ID (und damit die Zuordnung);
        /// weggefallene verschwinden samt ihrer Zuordnung. Liefert, ob sich etwas geändert hat.
        mutating func updateSegments(of activityID: UUID, with incoming: [IncomingSegment]) -> Bool {
            let old = dataset.segments.filter { $0.activityID == activityID }
            let matches = matchSegments(old, to: incoming)
            var changed = false
            for (i, s) in incoming.enumerated() {
                let segment = ActivitySegment(id: matches[i]?.id ?? makeID(), activityID: activityID, sportType: s.sportType,
                                              startAt: s.startAt, endAt: s.endAt, distanceMeters: s.distanceMeters)
                if let j = dataset.segments.firstIndex(where: { $0.id == segment.id }) {
                    guard dataset.segments[j] != segment else { continue }
                    dataset.segments[j] = segment
                } else {
                    dataset.segments.append(segment)
                }
                out.ledgerChanges.append(.upsertSegment(segment))
                changed = true
            }
            let kept = Set(matches.values.map(\.id))
            for gone in old where !kept.contains(gone.id) {
                for a in dataset.assignments where a.segmentID == gone.id { out.ledgerChanges.append(.removeAssignment(a.id)) }
                dataset.assignments.removeAll { $0.segmentID == gone.id }
                dataset.segments.removeAll { $0.id == gone.id }
                out.ledgerChanges.append(.removeSegment(gone.id))
                changed = true
            }
            return changed
        }

        var revivedIDs = Set<UUID>()
        func wasTombstoned(_ id: UUID) -> Bool { revivedIDs.contains(id) }

        mutating func tombstone(_ id: UUID) {
            guard let i = dataset.activities.firstIndex(where: { $0.id == id }), dataset.activities[i].deletedAt == nil else { return }
            dataset.activities[i].deletedAt = now
            dataset.activities[i].revision += 1
            out.tombstoned.append(id)
            out.ledgerChanges.append(.upsertActivity(dataset.activities[i]))
            for p in dataset.pendings.indices where dataset.pendings[p].activityID == id {
                dataset.pendings[p] = InboxReducer.reduce(dataset.pendings[p], .markObsolete, now: now, makeID: makeID).pending
            }
        }

        // MARK: Ersatz

        /// Übernimmt Zuordnungen und einen offenen Eintrag der ersetzten Aktivität (Ursprung und Zeitstempel bleiben).
        mutating func carryOver(from old: ActivityRecord, to new: ActivityRecord) {
            // Segmentzuordnungen wandern nur zu einem passenden neuen Segment (gleiche Sportart, gleicher Beginn).
            let oldSegments = dataset.segments.filter { $0.activityID == old.id }
            let newSegments = dataset.segments.filter { $0.activityID == new.id }
            let matches = matchSegments(oldSegments, to: newSegments.map {
                IncomingSegment(sportType: $0.sportType, startAt: $0.startAt, endAt: $0.endAt, distanceMeters: $0.distanceMeters)
            })
            let target = Dictionary(uniqueKeysWithValues: matches.map { ($0.value.id, newSegments[$0.key].id) })
            for a in dataset.assignments.filter({ $0.activityID == old.id }) {
                let segmentID = a.segmentID.flatMap { target[$0] }
                if a.segmentID != nil && segmentID == nil { continue }
                let copy = ActivityGearAssignment(id: makeID(), activityID: new.id, segmentID: segmentID, gearID: a.gearID,
                                                  origin: a.origin, createdAt: a.createdAt)
                dataset.assignments.append(copy)
                out.ledgerChanges.append(.upsertAssignment(copy))
            }
            for p in dataset.pendings where p.activityID == old.id && !p.state.isFinal {
                var moved = p
                moved.id = makeID()
                moved.activityID = new.id
                moved.proposalRevision = 1
                moved.createdAt = now
                moved.lastPromptAt = nil
                dataset.pendings.append(moved)
                out.pendingCreated.append(moved.id)
            }
        }

        // MARK: Entscheidung für neue Aktivitäten

        mutating func decide(for activity: ActivityRecord, forced predecessors: [ActivityRecord]?) {
            if let predecessors {
                // P-05: mehrdeutiger Ersatz → Posteingang, nie stille Übernahme.
                let sets = predecessors.map { old in
                    dataset.assignments.filter { $0.activityID == old.id && $0.segmentID == nil }.map(\.gearID).sorted { $0.uuidString < $1.uuidString }
                }
                let common = sets.first.flatMap { first in sets.allSatisfy { $0 == first } ? first : nil } ?? []
                let union = Array(Set(sets.flatMap { $0 })).sorted { $0.uuidString < $1.uuidString }
                var p = PendingAssignment(id: makeID(), activityID: activity.id, reason: .replacementAmbiguous, confidence: .low, createdAt: now)
                if !common.isEmpty {
                    p.state = .suggested
                    p.proposedGearIDs = common
                } else {
                    p.candidateGearIDs = union
                }
                addPending(p)
                return
            }
            switch AssignmentEngine.decide(for: activity, context: context) {
            case let .autoAssign(gear, reason, _):
                let origin = Self.origin(for: reason)
                for g in gear {
                    let a = ActivityGearAssignment(id: makeID(), activityID: activity.id, gearID: g, origin: origin, createdAt: now)
                    dataset.assignments.append(a)
                    out.ledgerChanges.append(.upsertAssignment(a))
                }
                out.autoAssigned.append(activity.id)
            case let .propose(primary, alternatives, reason, confidence):
                addPending(PendingAssignment(id: makeID(), activityID: activity.id, state: .suggested, proposedGearIDs: primary,
                                             alternatives: alternatives, reason: reason, confidence: confidence, createdAt: now))
            case let .choose(candidates, reason):
                addPending(PendingAssignment(id: makeID(), activityID: activity.id, state: .unresolved,
                                             candidateGearIDs: candidates, reason: reason, confidence: .none, createdAt: now))
            case .noGear:
                break   // „Ohne Ausrüstung“: importiert, aber kein Posteingang und keine Benachrichtigung (SPEC 6.2)
            }
        }

        mutating func addPending(_ p: PendingAssignment) {
            dataset.pendings.append(p)
            out.pendingCreated.append(p.id)
        }

        static func origin(for reason: AssignmentReason) -> AssignmentOrigin {
            switch reason {
            case .defaultPreset, .preset: .preset
            case .soleCandidate: .soleCandidate
            default: .rule
            }
        }

        // MARK: Ähnlichkeit und Zusammenführungs-Vorschläge

        func similar(_ n: IncomingWorkout, _ o: ActivityRecord) -> Bool {
            n.sportType == o.sportType && n.sourceBundleID == o.sourceBundleID
                && abs(n.startAt.timeIntervalSince(o.startAt)) <= ImportReconciler.replacementTolerance
                && abs(n.endAt.timeIntervalSince(o.endAt)) <= ImportReconciler.replacementTolerance
        }

        func makeRecord(_ w: IncomingWorkout) -> ActivityRecord {
            ActivityRecord(id: makeID(), source: .healthKit, sourceID: w.sourceID, sportType: w.sportType,
                           startAt: w.startAt, endAt: w.endAt, distanceMeters: w.distanceMeters,
                           durationSeconds: w.durationSeconds, isIndoor: w.isIndoor,
                           sourceBundleID: w.sourceBundleID, sourceName: w.sourceName)
        }

        static func strongMatch(_ a: ActivityRecord, _ b: ActivityRecord) -> MergeReason? {
            guard a.sportType == b.sportType, a.id != b.id else { return nil }
            let dStart = abs(a.startAt.timeIntervalSince(b.startAt))
            switch (a.source, b.source) {
            case (.manual, .healthKit), (.healthKit, .manual):
                let tol = max(60, 0.05 * max(a.durationSeconds, b.durationSeconds))
                return dStart <= ImportReconciler.manualMatchStartTolerance && abs(a.durationSeconds - b.durationSeconds) <= tol
                    ? .manualMatchesImported : nil
            case (.healthKit, .healthKit):
                guard a.sourceID != b.sourceID else { return nil }
                return dStart <= ImportReconciler.replacementTolerance
                    && abs(a.endAt.timeIntervalSince(b.endAt)) <= ImportReconciler.replacementTolerance
                    ? .sameSpanDifferentSources : nil
            default:
                return nil
            }
        }

        func suggestions() -> [MergeSuggestion] {
            let live = dataset.activities.filter { $0.deletedAt == nil }
            func partners(of a: ActivityRecord) -> [(ActivityRecord, MergeReason)] {
                live.compactMap { b in Self.strongMatch(a, b).map { (b, $0) } }
            }
            var seen = Set<[UUID]>()
            var result: [MergeSuggestion] = []
            for id in changedForMerge {
                guard let a = live.first(where: { $0.id == id }) else { continue }
                let ps = partners(of: a)
                guard ps.count == 1, let (b, reason) = ps.first, partners(of: b).count == 1 else { continue }   // nur eindeutig
                let key = [a.id, b.id].sorted { $0.uuidString < $1.uuidString }
                guard seen.insert(key).inserted else { continue }
                let kept: ActivityRecord, other: ActivityRecord
                if reason == .manualMatchesImported {
                    (kept, other) = a.source == .manual ? (a, b) : (b, a)
                } else {
                    (kept, other) = ((a.startAt, a.sourceID ?? "", a.id.uuidString) <= (b.startAt, b.sourceID ?? "", b.id.uuidString)) ? (a, b) : (b, a)
                }
                result.append(MergeSuggestion(keptID: kept.id, otherID: other.id, reason: reason))
            }
            return result
        }

        mutating func finish(comparedTo original: GearDataset) -> ReconcileOutput {
            out.dataset = dataset
            out.mergeSuggestions = suggestions()
            out.isUnchanged = dataset == original
            return out
        }
    }
}

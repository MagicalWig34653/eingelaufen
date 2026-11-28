import GearCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Einstellungen › Daten (SPEC 11, S08, M8): Backup exportieren (mit Hinweis), importieren (Vorschau), alles löschen.
struct DataSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<GearEntity> { $0.imagePath != nil }) private var gearWithPhotos: [GearEntity]
    @State private var includePhotos = true
    @State private var confirmExport = false
    @State private var exportFile: BackupFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var candidate: PreviewItem?
    @State private var confirmDeleteAll = false

    var body: some View {
        Section {
            if !gearWithPhotos.isEmpty {
                Toggle("Fotos einschließen", isOn: $includePhotos).accessibilityIdentifier("exportPhotos")
            }
            Button("Backup exportieren", systemImage: "square.and.arrow.up") { confirmExport = true }
                .accessibilityIdentifier("exportBackup")
                .confirmationDialog("Backup exportieren?", isPresented: $confirmExport, titleVisibility: .visible) {
                    Button("Exportieren") {
                        Task {
                            if let data = await model.exportBackup(includePhotos: includePhotos && !gearWithPhotos.isEmpty) {
                                exportFile = BackupFile(data: data)
                                showExporter = true
                            }
                        }
                    }
                    .accessibilityIdentifier("exportConfirm")
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Die Datei ist nicht verschlüsselt und enthält deine Ausrüstung und Trainingsdaten. Bewahre sie sicher auf und teile sie nur mit Bedacht.")
                }
                .fileExporter(isPresented: $showExporter, document: exportFile, contentType: .json,
                              defaultFilename: Self.fileName(for: Date())) { _ in
                    exportFile = nil
                }
            Button("Backup importieren", systemImage: "square.and.arrow.down") { showImporter = true }
                .accessibilityIdentifier("importBackup")
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                    guard case let .success(url) = result else { return }
                    Task { if let c = await model.previewBackup(at: url) { candidate = PreviewItem(candidate: c) } }
                }
                .sheet(item: $candidate) { ImportPreviewView(candidate: $0.candidate) }
            Button("Alle App-Daten löschen", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                .accessibilityIdentifier("deleteAllData")
                .confirmationDialog("Alle App-Daten löschen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                    Button("Alles löschen", role: .destructive) { Task { await model.deleteAllData() } }
                        .accessibilityIdentifier("confirmDeleteAll")
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Ausrüstung, Aktivitäten, Wartungen, Regeln, Fotos und Einstellungen werden endgültig von diesem Gerät gelöscht. In Apple Health bleibt alles erhalten. Exportiere vorher ein Backup, wenn du die Daten behalten willst.")
                }
        } header: {
            Text("Daten")
        } footer: {
            Text("Ein Backup ist eine unverschlüsselte Datei mit allen Daten der App. Du kannst es auf einem anderen Gerät wiederherstellen.")
        }
    }
}

extension DataSettingsSection {
    /// „Eingelaufen-Backup-2026-11-27-201530“: mit Uhrzeit, damit ein zweites Backup am selben Tag nichts überschreibt.
    static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Eingelaufen-Backup-" + f.string(from: date)
    }
}

struct PreviewItem: Identifiable {
    let id = UUID()
    let candidate: ImportCandidate
}

/// JSON-Datei für `fileExporter`.
struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Vorschau vor dem Import (SPEC 11, ARCHITEKTUR 7): Anzahl je Typ mit neu/Konflikt, Hinweise, Modus, ein Commit.
struct ImportPreviewView: View {
    let candidate: ImportCandidate
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choice = Choice.replace
    /// Karte F33E735D: Ersetzen verwirft den vorhandenen Bestand, vorher fragt die App nach.
    @State private var confirmReplace = false

    enum Choice: Hashable {
        case replace, mergeBackup, mergeExisting
        var mode: RestoreMode {
            switch self {
            case .replace: .replace
            case .mergeBackup: .merge(prefer: .backup)
            case .mergeExisting: .merge(prefer: .existing)
            }
        }
    }

    private var preview: BackupPreview { candidate.preview }
    private var errors: [BackupIssue] { preview.issues.filter { !$0.isWarning } }
    private var hints: [String] {
        var seen = Set<String>()
        return preview.issues.filter(\.isWarning).map(BackupTexts.hint(for:)).filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Erstellt am", value: candidate.document.exportedAt.formatted(date: .long, time: .shortened))
                }
                Section("Inhalt") {
                    ForEach(BackupEntity.allCases.filter { preview.summary[$0] != nil }, id: \.self) { entity in
                        let change = preview.summary[entity]!
                        LabeledContent {
                            Text(change.total, format: .number)
                        } label: {
                            Text(BackupTexts.name(for: entity))
                            Text(BackupTexts.detail(change))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("previewCount.\(entity.rawValue)")
                    }
                }
                if !errors.isEmpty {
                    Section("Nicht übernehmbar") {
                        Label("Das Backup enthält widersprüchliche Daten (\(errors.count)). Dein Bestand bleibt unverändert.",
                              systemImage: "exclamationmark.octagon")
                            .accessibilityIdentifier("previewErrors")
                    }
                }
                if !hints.isEmpty {
                    Section("Hinweise") {
                        ForEach(hints, id: \.self) { Label($0, systemImage: "info.circle") }
                    }
                }
                if errors.isEmpty {
                    Section {
                        Picker("Übernehmen", selection: $choice) {
                            Text("Bestand ersetzen").tag(Choice.replace)
                            Text("Zusammenführen, Backup gewinnt").tag(Choice.mergeBackup)
                            Text("Zusammenführen, Bestand gewinnt").tag(Choice.mergeExisting)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .accessibilityIdentifier("restoreMode")
                    } header: {
                        Text("Übernehmen")
                    } footer: {
                        Text(footer)
                    }
                }
            }
            .navigationTitle("Vorschau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }.accessibilityIdentifier("previewCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") {
                        if choice == .replace && preview.replaceDiscardsExisting { confirmReplace = true } else { restore() }
                    }
                    .disabled(!errors.isEmpty)
                    .accessibilityIdentifier("restoreConfirm")
                }
            }
            .confirmationDialog("Bestand ersetzen?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Bestand ersetzen", role: .destructive) { restore() }
                    .accessibilityIdentifier("restoreReplaceConfirm")
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Dein aktueller Bestand wird gelöscht und durch das Backup ersetzt. Das lässt sich nicht rückgängig machen. Exportiere vorher ein Backup, wenn du ihn behalten willst.")
            }
        }
    }

    private func restore() {
        Task { if await model.restore(candidate, mode: choice.mode) { dismiss() } }
    }

    private var footer: String {
        let conflicts = preview.conflicts.count
        let base = choice == .replace
            ? String(localized: "Ersetzen löscht deinen aktuellen Bestand und übernimmt genau das Backup.")
            : String(localized: "Zusammenführen ergänzt neue Einträge; bei gleichen Einträgen entscheidet die gewählte Seite.")
        guard conflicts > 0 else { return base }
        let differing = conflicts == 1
            ? String(localized: "1 Eintrag weicht von deinem Bestand ab.")
            : String(localized: "\(conflicts) Einträge weichen von deinem Bestand ab.")
        return base + " " + differing
    }
}

enum BackupTexts {
    static func name(for entity: BackupEntity) -> String {
        switch entity {
        case .gear: String(localized: "Ausrüstung")
        case .statusChange: String(localized: "Statuswechsel")
        case .installation: String(localized: "Montagen")
        case .preset: String(localized: "Sets")
        case .sportProfile: String(localized: "Sportarten")
        case .activity: String(localized: "Aktivitäten")
        case .segment: String(localized: "Abschnitte")
        case .assignment: String(localized: "Zuordnungen")
        case .maintenanceEvent: String(localized: "Wartungen")
        case .maintenanceRule: String(localized: "Wartungsregeln")
        case .assignmentRule: String(localized: "Zuordnungsregeln")
        case .pending: String(localized: "Posteingang")
        }
    }

    /// „2 neu · 1 Konflikt“; nur Teile, die vorkommen.
    static func detail(_ change: BackupEntityChange) -> String {
        var parts: [String] = []
        if change.new > 0 { parts.append(String(localized: "\(change.new) neu")) }
        if change.unchanged > 0 { parts.append(String(localized: "\(change.unchanged) unverändert")) }
        if change.conflicting > 0 { parts.append(String(localized: "\(change.conflicting) abweichend")) }
        return parts.joined(separator: " · ")
    }

    static func hint(for issue: BackupIssue) -> String {
        switch issue {
        case .missingMedia: String(localized: "Fotos sind in diesem Backup nicht enthalten.")
        case .unreferencedMedia: String(localized: "Fotos ohne zugehörige Ausrüstung werden übersprungen.")
        default: String(localized: "Eine Montage liegt vor dem Kaufdatum.")
        }
    }
}

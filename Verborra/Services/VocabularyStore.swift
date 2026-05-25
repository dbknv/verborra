import Foundation

// MARK: - VocabularyStore (012-vocabularies)

/// Хранение и управление записями словаря (CRUD + JSON-персистенция).
/// Паттерн аналогичен PromptsStore.
@Observable
final class VocabularyStore {
    private(set) var entries: [VocabularyEntry] = []
    private let fileURL: URL
    private let log = DiagnosticLogger.logger(for: .vocabulary)

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Verborra", isDirectory: true)
        self.fileURL = appDir.appendingPathComponent("vocabularies.json")

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        load()
    }

    /// For testing
    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - CRUD

    func addEntry(_ entry: VocabularyEntry) {
        let sanitized = entry.sanitized
        guard sanitized.isValid else {
            log.debug("Add entry rejected: invalid", metadata: ["targetWord": entry.targetWord])
            return
        }
        guard !entries.contains(where: { $0.targetWord == sanitized.targetWord }) else {
            log.debug("Add entry rejected: duplicate targetWord", metadata: ["targetWord": sanitized.targetWord])
            return
        }
        entries.append(sanitized)
        save()
        log.info("Vocabulary entry created", metadata: ["targetWord": sanitized.targetWord, "alternativesCount": "\(sanitized.alternatives.count)"])
        log.debug("Vocabulary entry details", metadata: ["targetWord": sanitized.targetWord, "alternatives": sanitized.alternatives.joined(separator: ", ")])
    }

    func updateEntry(_ entry: VocabularyEntry) {
        let sanitized = entry.sanitized
        guard sanitized.isValid else {
            log.debug("Update entry rejected: invalid", metadata: ["targetWord": entry.targetWord])
            return
        }
        guard let index = entries.firstIndex(where: { $0.id == sanitized.id }) else { return }

        // Check uniqueness excluding self
        let isDuplicate = entries.contains(where: { $0.id != sanitized.id && $0.targetWord == sanitized.targetWord })
        guard !isDuplicate else {
            log.debug("Update entry rejected: duplicate targetWord", metadata: ["targetWord": sanitized.targetWord])
            return
        }

        entries[index] = sanitized
        save()
        log.info("Vocabulary entry updated", metadata: ["targetWord": sanitized.targetWord])
        log.debug("Vocabulary entry updated details", metadata: ["targetWord": sanitized.targetWord, "alternatives": sanitized.alternatives.joined(separator: ", ")])
    }

    func deleteEntry(_ id: UUID) {
        let targetWord = entries.first(where: { $0.id == id })?.targetWord ?? "unknown"
        entries.removeAll(where: { $0.id == id })
        save()
        log.info("Vocabulary entry deleted", metadata: ["targetWord": targetWord])
    }

    // MARK: - Validation helpers

    /// Проверяет, не дублируется ли targetWord (excluding given id).
    func isTargetWordUnique(_ targetWord: String, excludingId: UUID? = nil) -> Bool {
        let trimmed = targetWord.trimmingCharacters(in: .whitespacesAndNewlines)
        return !entries.contains(where: { $0.id != excludingId && $0.targetWord == trimmed })
    }

    /// Проверяет, не используется ли альтернатива уже в другой записи.
    func conflictingEntry(for alternative: String, excludingId: UUID? = nil) -> VocabularyEntry? {
        let trimmed = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first(where: { $0.id != excludingId && $0.alternatives.contains(trimmed) })
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([VocabularyEntry].self, from: data)
            entries.sort(by: { $0.createdAt < $1.createdAt })
            log.info("Vocabulary loaded", metadata: ["entriesCount": "\(entries.count)"])
        } catch {
            entries = []
            log.debug("Vocabulary load failed or empty", metadata: ["error": error.localizedDescription])
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent failure — consistent with PromptsStore pattern
        }
    }
}

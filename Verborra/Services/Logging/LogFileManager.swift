import Foundation

// MARK: - LogFileManager (T012)

/// Управление файлами логов: директория, ротация, cleanup (FR-005, FR-006, FR-015).
final class LogFileManager: @unchecked Sendable {
    static let shared = LogFileManager()

    private let fileManager = FileManager.default

    private init() {}

    /// URL директории логов: ~/Library/Application Support/Verborra/Logs/
    func logsDirectoryURL() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Verborra/Logs", isDirectory: true)
    }

    /// URL текущего лог-файла на основе текущего часа: verborra-yyyy-MM-ddTHH.jsonl
    func currentLogFileURL() -> URL {
        let dir = logsDirectoryURL()
        let name = "verborra-\(Self.hourFormatter.string(from: Date())).jsonl"
        return dir.appendingPathComponent(name)
    }

    /// Создаёт директорию логов если не существует.
    func ensureLogsDirectory() {
        let dir = logsDirectoryURL()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Проверяет, нужна ли ротация: смена часа ИЛИ размер > 50 МБ.
    func rotateIfNeeded(currentFileURL: URL) -> URL? {
        let expectedURL = currentLogFileURL()

        // Ротация по времени: изменился час
        if currentFileURL.lastPathComponent != expectedURL.lastPathComponent {
            return expectedURL
        }

        // Ротация по размеру: > 50 МБ
        if let attrs = try? fileManager.attributesOfItem(atPath: currentFileURL.path),
           let size = attrs[.size] as? UInt64,
           size >= 50 * 1024 * 1024 {
            // Добавляем суффикс _N для файлов, ротированных по размеру в пределах одного часа
            let base = currentFileURL.deletingPathExtension().lastPathComponent
            for i in 1...99 {
                let name = "\(base)_\(i).jsonl"
                let url = logsDirectoryURL().appendingPathComponent(name)
                if !fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }

    /// Удаляет файлы логов старше указанного количества часов (FR-006).
    func cleanupOldLogs(retentionHours: Int) {
        let dir = logsDirectoryURL()
        guard let files = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Double(retentionHours) * 3600)

        for file in files where file.pathExtension == "jsonl" {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = attrs.creationDate,
               creationDate < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - Private

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

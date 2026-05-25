import Foundation

// MARK: - JSONLFileWriter (T011)

/// Асинхронная запись LogEntry в JSONL-файл через serial queue (FR-004, FR-019, FR-021, FR-022).
final class JSONLFileWriter: @unchecked Sendable {
    static let shared = JSONLFileWriter()

    private let queue = DispatchQueue(label: "dev.apeek.verborra.jsonl-writer", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentFileURL: URL?
    private var flushTimer: DispatchSourceTimer?
    private var isDisabled = false
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private init() {}

    /// Запускает writer: создаёт файл и периодический flush (каждые 5 сек).
    func start() {
        queue.async { [weak self] in
            self?.openCurrentFile()
            self?.startPeriodicFlush()
        }
    }

    /// Записывает entry в JSONL-файл. Не блокирует вызывающий поток.
    /// При ERROR — немедленный flush (FR-021).
    func write(entry: LogEntry) {
        queue.async { [weak self] in
            guard let self, !isDisabled else { return }
            self.rotateIfNeeded()
            self.writeEntry(entry)
            if entry.level == LogLevel.error.displayName {
                self.flushInternal()
            }
        }
    }

    /// Принудительный flush буфера. Вызывается при завершении приложения.
    func flush() {
        queue.async { [weak self] in
            self?.flushInternal()
        }
    }

    /// Синхронный flush для завершения приложения.
    func flushSync() {
        queue.sync { [weak self] in
            self?.flushInternal()
        }
    }

    /// Останавливает writer и закрывает файл.
    func stop() {
        queue.async { [weak self] in
            self?.flushTimer?.cancel()
            self?.flushTimer = nil
            self?.flushInternal()
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
        }
    }

    // MARK: - Private

    private func openCurrentFile() {
        let manager = LogFileManager.shared
        manager.ensureLogsDirectory()
        let url = manager.currentLogFileURL()
        currentFileURL = url

        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
    }

    private func writeEntry(_ entry: LogEntry) {
        guard let data = try? encoder.encode(entry),
              let newline = "\n".data(using: .utf8) else { return }

        do {
            try fileHandle?.write(contentsOf: data)
            try fileHandle?.write(contentsOf: newline)
        } catch {
            // Disk full — переключиться на os_log only (T053)
            handleDiskError()
        }
    }

    private func flushInternal() {
        try? fileHandle?.synchronize()
    }

    private func rotateIfNeeded() {
        guard let currentURL = currentFileURL else {
            openCurrentFile()
            return
        }

        if let newURL = LogFileManager.shared.rotateIfNeeded(currentFileURL: currentURL) {
            flushInternal()
            fileHandle?.closeFile()
            currentFileURL = newURL

            let fm = FileManager.default
            if !fm.fileExists(atPath: newURL.path) {
                fm.createFile(atPath: newURL.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: newURL)
            fileHandle?.seekToEndOfFile()
        }
    }

    private func startPeriodicFlush() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.flushInternal()
        }
        timer.resume()
        flushTimer = timer
    }

    /// T053: Обработка ошибки записи (disk full). Отключает файловый вывод и пытается cleanup.
    private func handleDiskError() {
        isDisabled = true
        fileHandle?.closeFile()
        fileHandle = nil
        // Попытка освободить место
        LogFileManager.shared.cleanupOldLogs(retentionHours: 1)
        // Попытка возобновить
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.isDisabled = false
            self?.openCurrentFile()
        }
    }
}

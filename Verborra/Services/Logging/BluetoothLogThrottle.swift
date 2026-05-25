import Foundation

// MARK: - BluetoothLogThrottle (T065)

/// Throttling Bluetooth-событий: 100 мс per-device.
/// Каждое устройство throttle-ится независимо.
final class BluetoothLogThrottle: @unchecked Sendable {
    static let shared = BluetoothLogThrottle()

    private var lastEventTimes: [String: DispatchTime] = [:]
    private let lock = NSLock()
    private let intervalNanos: UInt64 = 100_000_000 // 100 ms

    private init() {}

    /// Проверяет, можно ли логировать событие для устройства.
    /// Возвращает `true` если прошло >= 100 мс с последнего события для этого deviceID.
    func shouldLog(deviceID: String) -> Bool {
        let now = DispatchTime.now()
        lock.lock()
        defer { lock.unlock() }

        if let last = lastEventTimes[deviceID] {
            let elapsed = now.uptimeNanoseconds - last.uptimeNanoseconds
            guard elapsed >= intervalNanos else { return false }
        }
        lastEventTimes[deviceID] = now
        return true
    }

    /// Сбрасывает состояние (для тестирования).
    func reset() {
        lock.lock()
        lastEventTimes.removeAll()
        lock.unlock()
    }
}

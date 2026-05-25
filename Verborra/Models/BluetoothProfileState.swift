import Foundation

// MARK: - Bluetooth Profile State (FR-035)

/// Определённый профиль Bluetooth-устройства.
/// Выводится через составной анализ трёх свойств CoreAudio:
/// sample rate + input channels + output channels.
enum BluetoothProfileState: Sendable, Equatable {
    /// A2DP: высококачественное воспроизведение (≥44.1 кГц, 0 input channels, stereo output)
    case a2dp(sampleRate: Float64)
    /// HFP: Hands-Free Profile для записи (≤24 кГц, input channels > 0, mono output)
    case hfp(sampleRate: Float64)
    /// Не удалось определить профиль (промежуточное состояние или не-Bluetooth устройство)
    case unknown

    var isHFP: Bool {
        if case .hfp = self { return true }
        return false
    }

    var isA2DP: Bool {
        if case .a2dp = self { return true }
        return false
    }

    var sampleRate: Float64? {
        switch self {
        case .a2dp(let rate), .hfp(let rate): return rate
        case .unknown: return nil
        }
    }

    var profileName: String {
        switch self {
        case .a2dp: return "A2DP"
        case .hfp: return "HFP"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Bluetooth Preparation Context (FR-034)

/// Контекст вызова унифицированного метода подготовки BT-устройства.
enum BluetoothPreparationContext: String, Sendable {
    /// Первый старт записи на BT-устройстве
    case firstStart = "first_start"
    /// Переключение с другого устройства на BT
    case deviceSwitch = "device_switch"
    /// Повторное подключение после отключения
    case reconnect = "reconnect"
}

// MARK: - Bluetooth Preparation Result (FR-032)

/// Результат работы унифицированного метода подготовки.
enum BluetoothPreparationResult: Sendable {
    /// Переключение выполнено, устройство готово к записи
    case ready(sampleRate: Float64)
    /// Устройство уже в HFP, переключение не требовалось
    case alreadyHFP(sampleRate: Float64)
    /// Переключение не завершилось за 5 секунд (FR-014)
    case timeout
    /// Ошибка при подготовке
    case error(Error)
    /// Устройство в A2DP, нужен switch — engine start триггерит переключение
    case needsSwitch(currentSampleRate: Float64)
    /// Устройство отключилось во время подготовки
    case deviceDisconnected

    var isSuccess: Bool {
        switch self {
        case .ready, .alreadyHFP, .needsSwitch: return true
        case .timeout, .error, .deviceDisconnected: return false
        }
    }

    /// True if engine start should await BT format stabilization before recording
    var requiresStabilization: Bool {
        if case .needsSwitch = self { return true }
        return false
    }

    var sampleRate: Float64? {
        switch self {
        case .ready(let rate), .alreadyHFP(let rate): return rate
        case .needsSwitch(let rate): return rate
        default: return nil
        }
    }

    var statusName: String {
        switch self {
        case .ready: return "success"
        case .alreadyHFP: return "already_hfp"
        case .needsSwitch: return "needs_switch"
        case .timeout: return "timeout"
        case .error: return "error"
        case .deviceDisconnected: return "device_disconnected"
        }
    }
}

// Equatable conformance for BluetoothPreparationResult (excluding Error associated value)
extension BluetoothPreparationResult: Equatable {
    static func == (lhs: BluetoothPreparationResult, rhs: BluetoothPreparationResult) -> Bool {
        switch (lhs, rhs) {
        case (.ready(let a), .ready(let b)): return a == b
        case (.alreadyHFP(let a), .alreadyHFP(let b)): return a == b
        case (.needsSwitch(let a), .needsSwitch(let b)): return a == b
        case (.timeout, .timeout): return true
        case (.deviceDisconnected, .deviceDisconnected): return true
        case (.error, .error): return true
        default: return false
        }
    }
}

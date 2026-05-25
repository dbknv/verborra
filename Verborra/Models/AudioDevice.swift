import CoreAudio
import Foundation

// MARK: - AudioDeviceTransportType

enum AudioDeviceTransportType: Sendable, Equatable, Hashable {
    case builtIn
    case usb
    case bluetooth
    case bluetoothLE
    case virtual
    case unknown

    var isBluetooth: Bool {
        self == .bluetooth || self == .bluetoothLE
    }

    init(coreAudioTransportType: UInt32) {
        switch coreAudioTransportType {
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeUSB:
            self = .usb
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        case kAudioDeviceTransportTypeVirtual:
            self = .virtual
        default:
            self = .unknown
        }
    }
}

// MARK: - AudioDevice

struct AudioDevice: Identifiable, Equatable, Hashable, Sendable {
    /// Stable device UID from `kAudioDevicePropertyDeviceUID`.
    /// Empty string `""` for System Default.
    let uid: String

    /// Human-readable device name.
    let name: String

    /// CoreAudio numeric ID (unstable across reboots, internal use only).
    let audioDeviceID: AudioDeviceID

    /// Connection type (built-in, USB, Bluetooth, virtual).
    let transportType: AudioDeviceTransportType

    /// Whether this device is the current system default input.
    let isSystemDefault: Bool

    var id: String {
        uid.isEmpty ? "system-default" : uid
    }

    /// Convenience: true when this entry represents "System Default".
    var isSystemDefaultEntry: Bool {
        uid.isEmpty
    }
}

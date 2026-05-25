import SwiftUI

// MARK: - MicrophoneSelectorButton

struct MicrophoneSelectorButton: View {
    @Bindable var viewModel: RecordingViewModel
    var audioDeviceManager: AudioDeviceManager

    private var isLocked: Bool {
        viewModel.windowPhase == .postProcessing
    }

    private var selectedDeviceName: String {
        audioDeviceManager.selectedDevice?.name ?? "System Default"
    }

    var body: some View {
        Menu {
            // System Default first
            if let systemDefault = audioDeviceManager.devices.first(where: { $0.isSystemDefaultEntry }) {
                Button {
                    viewModel.switchAudioDevice(to: systemDefault.uid)
                } label: {
                    HStack {
                        Text(systemDefault.name)
                        if audioDeviceManager.selectedDevice?.isSystemDefaultEntry == true {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()
            }

            // Real devices (alphabetical, already sorted by AudioDeviceManager)
            ForEach(audioDeviceManager.devices.filter { !$0.isSystemDefaultEntry }) { device in
                Button {
                    viewModel.switchAudioDevice(to: device.uid)
                } label: {
                    HStack {
                        Text(device.name)
                        if device.uid == audioDeviceManager.selectedDevice?.uid {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            ControlBarButtonLabel(
                title: selectedDeviceName,
                sfSymbol: "mic",
                hotkeyLabel: "1",
                isEnabled: !isLocked
            )
        }
        .id(audioDeviceManager.deviceListVersion) // FR-010: close menu on hot-plug
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isLocked)
    }
}

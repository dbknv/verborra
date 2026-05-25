import SwiftUI
import KeyboardShortcuts

// MARK: - ControlButton

struct ControlButton: Identifiable {
    let id: String
    let title: String
    let sfSymbol: String
    let hotkeyLabel: String
    let isEnabled: Bool
    let action: () -> Void
    var hasDropdown: Bool = false
}

// MARK: - ControlBarView

struct ControlBarView: View {
    @Bindable var viewModel: RecordingViewModel
    let hasAccessibility: Bool

    private var windowPhase: WindowPhase { viewModel.windowPhase }
    private var recordingState: RecordingState { viewModel.state }
    private var inputRecordingState: InputRecordingState { viewModel.inputRecordingState }

    private var isProcessing: Bool {
        switch recordingState {
        case .transcribing, .formatting:
            return true
        default:
            return false
        }
    }

    private var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch windowPhase {
                case .preProcessing:
                    preProcessingButtons
                case .postProcessing:
                    postProcessingButtons
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))

            Spacer()

            // Start/Stop button
            if windowPhase == .preProcessing || !isProcessing {
                controlBarButton(
                    title: LocalizationManager.shared.string(isRecording ? "controlbar.stop" : "controlbar.start"),
                    sfSymbol: isRecording ? "stop.fill" : "play.fill",
                    hotkeyLabel: formattedShortcutLabel,
                    isEnabled: windowPhase == .preProcessing ? (!isProcessing && viewModel.settings.hasApiKey && !viewModel.audioDeviceManager.isBluetoothSwitching) : true,
                    action: {
                        if isRecording {
                            viewModel.stopRecording()
                        } else if windowPhase == .preProcessing {
                            viewModel.startRecording()
                        }
                    }
                )
            }

            // Exit button
            controlBarButton(
                title: "Exit",
                sfSymbol: "rectangle.portrait.and.arrow.right.fill",
                hotkeyLabel: "Esc",
                isEnabled: true,
                action: { viewModel.dismissOverlay() }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: 0xF4F4F4))
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 16,
            topTrailingRadius: 0
        ))
    }

    // MARK: - Pre-Processing Buttons (State 1)

    @ViewBuilder
    private var preProcessingButtons: some View {
        // Bluetooth switching indicator
        if viewModel.audioDeviceManager.isBluetoothSwitching {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text(LocalizationManager.shared.string("controlbar.switching"))
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x666666))
            }
            .padding(.horizontal, 8)
        }

        // Microphone (hotkey 1)
        controlBarMenu(
            title: microphoneTitle,
            sfSymbol: "mic.fill",
            hotkeyLabel: "1",
            isEnabled: !isProcessing && !viewModel.audioDeviceManager.isBluetoothSwitching
        ) {
            let manager = viewModel.audioDeviceManager
            // System Default first
            if let systemDefault = manager.devices.first(where: { $0.isSystemDefaultEntry }) {
                Button {
                    viewModel.switchAudioDevice(to: systemDefault.uid)
                } label: {
                    HStack {
                        Text(systemDefault.name)
                        if manager.selectedDevice?.isSystemDefaultEntry == true {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()
            }

            // Real devices (alphabetical)
            ForEach(manager.devices.filter { !$0.isSystemDefaultEntry }) { device in
                Button {
                    viewModel.switchAudioDevice(to: device.uid)
                } label: {
                    HStack {
                        Text(device.name)
                        if device.uid == manager.selectedDevice?.uid {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .id(viewModel.audioDeviceManager.deviceListVersion) // FR-010: close on hot-plug

        // Text language (hotkey 2)
        controlBarMenu(
            title: viewModel.selectedTextLanguage.localizedDisplayName(for: LocalizationManager.shared.currentLanguage),
            sfSymbol: "text.bubble.fill",
            hotkeyLabel: "2",
            isEnabled: !isProcessing
        ) {
            ForEach(SupportedLanguage.allCases, id: \.self) { language in
                Button {
                    viewModel.changeTextLanguage(language)
                } label: {
                    HStack {
                        Text(language.localizedDisplayName(for: LocalizationManager.shared.currentLanguage))
                        if language == viewModel.selectedTextLanguage {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private var microphoneTitle: String {
        viewModel.audioDeviceManager.selectedDevice?.name ?? "System Default"
    }

    /// Formats the current global shortcut as modifier symbols separated by spaces (e.g. "⌥ Space", "⌘ ⇧ R").
    @MainActor
    private var formattedShortcutLabel: String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .toggleOverlay) else {
            return ""
        }

        // shortcut.description returns e.g. "⌥Space", "⌘⇧R" — modifiers concatenated with key, no separators.
        // We need to insert spaces between each modifier symbol and the key.
        let desc = shortcut.description
        let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

        var parts: [String] = []
        var keyPart = ""

        for char in desc {
            if modifierSymbols.contains(char) {
                parts.append(String(char))
            } else {
                keyPart.append(char)
            }
        }

        if !keyPart.isEmpty {
            parts.append(keyPart)
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Post-Processing Buttons (State 2)

    @ViewBuilder
    private var postProcessingButtons: some View {
        let isInputRecording = inputRecordingState != .idle

        // Copy Markdown (⌥C)
        controlBarButton(
            title: "Copy",
            sfSymbol: "doc.on.doc.fill",
            hotkeyLabel: "⌥C",
            isEnabled: !isInputRecording,
            action: { viewModel.copyMarkdown() }
        )

        // Paste Markdown (⌥V)
        controlBarButton(
            title: "Paste",
            sfSymbol: "doc.on.clipboard.fill",
            hotkeyLabel: "⌥V",
            isEnabled: !isInputRecording && hasAccessibility,
            action: { viewModel.pasteMarkdown() }
        )
    }

    // MARK: - Menu Component (same visual as buttons)

    private func controlBarMenu<Content: View>(
        title: String,
        sfSymbol: String,
        hotkeyLabel: String,
        isEnabled: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            ControlBarButtonLabel(
                title: title,
                sfSymbol: sfSymbol,
                hotkeyLabel: hotkeyLabel,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: - Button Component

    private func controlBarButton(
        title: String,
        sfSymbol: String,
        hotkeyLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ControlBarButtonLabel(
                title: title,
                sfSymbol: sfSymbol,
                hotkeyLabel: hotkeyLabel,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Shared Button Label (used by ControlBarView, MicrophoneSelectorButton, LanguageSelectorView)

struct ControlBarButtonLabel: View {
    let title: String
    let sfSymbol: String
    let hotkeyLabel: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sfSymbol)
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 12, weight: .medium))

            Text(hotkeyLabel)
                .font(.system(size: 10, weight: .regular))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(hex: 0xF4F4F4))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isEnabled ? Color(hex: 0xDCDCDC) : Color(hex: 0xEBEBEB))
        .foregroundColor(isEnabled ? Color(hex: 0x2C2C2C) : Color(hex: 0xACACAC))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

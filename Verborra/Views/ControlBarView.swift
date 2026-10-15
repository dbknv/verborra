import SwiftUI

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

    private var isStarting: Bool {
        if case .starting = recordingState { return true }
        return false
    }

    var body: some View {
        HStack(spacing: Self.buttonGap) {
            Group {
                switch windowPhase {
                case .preProcessing:
                    preProcessingButtons
                case .postProcessing:
                    postProcessingButtons
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))

            // Never closer to the right-hand buttons than the normal button gap (FR-063)
            Spacer(minLength: Self.buttonGap)

            HStack(spacing: Self.buttonGap) {
                rightButtons
            }
            .fixedSize()
            .layoutPriority(3)
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

    /// Spacing between bar buttons; also the minimum gap before the right-hand group.
    private static let buttonGap: CGFloat = 8

    /// Start/Stop/Cancel and Exit.
    @ViewBuilder
    private var rightButtons: some View {
        // Start/Stop button; "Cancel" while the microphone is starting (spec 015, FR-013a)
        if windowPhase == .preProcessing && isStarting {
            controlBarButton(
                title: LocalizationManager.shared.string("controlbar.cancel"),
                sfSymbol: "xmark",
                hotkeyLabel: formattedShortcutLabel,
                isEnabled: true,
                action: { viewModel.cancelStart(trigger: "button") }
            )
        } else if windowPhase == .preProcessing || !isProcessing {
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

        // spec 015 (R29): 1 microphone, 2 output language, 3 prompt; each menu starts with a title.
        // Width (R34, FR-063, FR-064): each button follows its title, no fixed cap. When the row is too
        // narrow the microphone title shrinks first (priority 0), then the prompt (1), then the language (2);
        // the right-hand buttons never shrink.

        // Microphone (hotkey 1)
        controlBarMenu(
            title: microphoneTitle,
            sfSymbol: "mic.fill",
            hotkeyLabel: "1",
            isEnabled: !isProcessing && !isStarting && !viewModel.audioDeviceManager.isBluetoothSwitching,
            truncatesTitle: true
        ) {
            let manager = viewModel.audioDeviceManager
            let realDevices = manager.devices.filter { !$0.isSystemDefaultEntry }
            Section(LocalizationManager.shared.string("controlbar.menu.inputDevice")) {
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

                    // No trailing separator when System Default is the only entry
                    if !realDevices.isEmpty {
                        Divider()
                    }
                }

                // Real devices (alphabetical)
                ForEach(realDevices) { device in
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
        }
        .id(viewModel.audioDeviceManager.deviceListVersion) // FR-010: close on hot-plug
        .layoutPriority(0)

        // Output language (hotkey 2)
        controlBarMenu(
            title: viewModel.selectedTextLanguage.localizedDisplayName(for: LocalizationManager.shared.currentLanguage),
            sfSymbol: "text.bubble.fill",
            hotkeyLabel: "2",
            isEnabled: !isProcessing && !isStarting,
            truncatesTitle: true
        ) {
            Section(LocalizationManager.shared.string("controlbar.menu.outputLanguage")) {
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
        .layoutPriority(2)

        // Prompt (hotkey 3) — moved here from the window header (spec 015, FR-023);
        // width follows the name up to the room left before the right-hand buttons (FR-063)
        controlBarMenu(
            title: PromptNameRule.display(viewModel.selectedPrompt.name),
            sfSymbol: "text.quote",
            hotkeyLabel: "3",
            isEnabled: !isProcessing && !isStarting,
            truncatesTitle: true
        ) {
            Section(LocalizationManager.shared.string("controlbar.menu.prompt")) {
                ForEach(viewModel.promptsStore.prompts) { prompt in
                    Button {
                        viewModel.changePrompt(prompt, source: .menu)
                    } label: {
                        HStack {
                            Text(prompt.name)
                            if prompt.id == viewModel.selectedPrompt.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
        .layoutPriority(1)
    }

    private var microphoneTitle: String {
        viewModel.audioDeviceManager.selectedDevice?.name ?? "System Default"
    }

    /// The global shortcut as symbols separated by spaces, including 🌐︎ (e.g. "⌥ Space", "🌐︎ ⌘ R") — FR-028.
    private var formattedShortcutLabel: String {
        ShortcutFormatter.string(GlobalShortcutStore.shared.current)
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
        truncatesTitle: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            ControlBarButtonLabel(
                title: title,
                sfSymbol: sfSymbol,
                hotkeyLabel: hotkeyLabel,
                isEnabled: isEnabled,
                truncatesTitle: truncatesTitle
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

// MARK: - Shared Button Label (used by ControlBarView)

struct ControlBarButtonLabel: View {
    let title: String
    let sfSymbol: String
    let hotkeyLabel: String
    let isEnabled: Bool
    /// The title may shrink (tail-truncated) when the bar runs out of room; otherwise it keeps its full width.
    var truncatesTitle = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sfSymbol)
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: !truncatesTitle, vertical: false)

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

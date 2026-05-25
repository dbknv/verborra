import SwiftUI

// MARK: - LanguageSelectorView

struct LanguageSelectorView: View {
    @Bindable var viewModel: RecordingViewModel

    private var isLocked: Bool {
        viewModel.windowPhase == .postProcessing
    }

    var body: some View {
        HStack(spacing: 8) {
            // Voice language (hotkey 2)
            Menu {
                ForEach(SupportedLanguage.allCases, id: \.self) { language in
                    Button {
                        viewModel.changeVoiceLanguage(language)
                    } label: {
                        HStack {
                            Text(language.displayName)
                            if language == viewModel.selectedVoiceLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                ControlBarButtonLabel(
                    title: viewModel.selectedVoiceLanguage.displayName,
                    sfSymbol: "waveform",
                    hotkeyLabel: "2",
                    isEnabled: !isLocked
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isLocked)

            // Text language (hotkey 3)
            Menu {
                ForEach(SupportedLanguage.allCases, id: \.self) { language in
                    Button {
                        viewModel.changeTextLanguage(language)
                    } label: {
                        HStack {
                            Text(language.displayName)
                            if language == viewModel.selectedTextLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                ControlBarButtonLabel(
                    title: viewModel.selectedTextLanguage.displayName,
                    sfSymbol: "text.bubble",
                    hotkeyLabel: "3",
                    isEnabled: !isLocked
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isLocked)
        }
    }
}

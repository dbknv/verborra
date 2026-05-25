import SwiftUI

// MARK: - PersonalPreferencesSettingsTab (012-vocabularies)

/// Вкладка Personal Preferences: заголовок, описание, авто-растущее текстовое поле
/// с placeholder, debounce-сохранение 0.5с + сохранение при onDisappear.
struct PersonalPreferencesSettingsTab: View {
    let viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n

    @State private var text: String = ""
    @State private var saveTask: Task<Void, Never>?
    private let log = DiagnosticLogger.logger(for: .vocabulary)

    private var settings: AppSettings { viewModel.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text(l10n.string("settings.preferences.title"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(l10n.string("settings.preferences.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Text editor with auto-grow
                ZStack(alignment: .topLeading) {
                    // Placeholder
                    if text.isEmpty {
                        Text(l10n.string("settings.preferences.placeholder"))
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(
                            minHeight: 200,
                            maxHeight: 600
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .padding(20)
        }
        .onAppear {
            text = settings.personalPreferencesText
        }
        .onDisappear {
            saveTask?.cancel()
            settings.personalPreferencesText = text
        }
        .onChange(of: text) {
            debounceSave()
        }
    }

    private func debounceSave() {
        saveTask?.cancel()
        log.debug("Personal Preferences debounce timer reset")
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            settings.personalPreferencesText = text
            log.info("Personal Preferences saved", metadata: ["textLength": "\(text.count) chars"])
            log.debug("Personal Preferences content", metadata: ["text": String(text.prefix(500))])
        }
    }
}

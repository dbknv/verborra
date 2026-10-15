import AppKit
import SwiftUI

struct AdvancedSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n
    @Environment(AppSettings.self) private var appSettings
    @State private var showRestartNotice = false
    @State private var resolvedFolderPath: String?
    private let log = DiagnosticLogger.logger(for: .settings)

    var body: some View {
        @Bindable var settings = appSettings

        Form {
            // MARK: - Audio Save Section (T031)
            Section(l10n.string("settings.advanced.audioSave")) {
                Toggle(l10n.string("settings.advanced.audioSave.enable"),
                       isOn: $settings.isAudioSaveEnabled)
                    .disabled(appSettings.audioSaveFolderBookmark == nil)

                HStack {
                    Button(l10n.string("settings.advanced.audioSave.chooseFolder")) {
                        chooseAudioSaveFolder()
                    }

                    Text(resolvedFolderPath ?? l10n.string("settings.advanced.audioSave.notSelected"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .onAppear {
                resolvedFolderPath = appSettings.resolveAudioFolderBookmark()?.path
                // Disable toggle if folder bookmark was lost
                if appSettings.audioSaveFolderBookmark == nil && appSettings.isAudioSaveEnabled {
                    appSettings.isAudioSaveEnabled = false
                }
            }

            // MARK: - Logging Section (T049)
            Section(l10n.string("settings.advanced.logging")) {
                Picker(l10n.string("settings.advanced.logLevel"), selection: $settings.logLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .onChange(of: appSettings.logLevel) { oldValue, newValue in
                    // T050: Логирование смены уровня
                    log.info("Log level changed", metadata: [
                        "from": oldValue.displayName,
                        "to": newValue.displayName
                    ])
                }

                Stepper(
                    "\(l10n.string("settings.advanced.logRetention")): \(appSettings.logRetentionHours) \(l10n.string("settings.advanced.hours"))",
                    value: $settings.logRetentionHours,
                    in: 1...168
                )

                Button(l10n.string("settings.advanced.showLogs")) {
                    let url = LogFileManager.shared.logsDirectoryURL()
                    LogFileManager.shared.ensureLogsDirectory()
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
            }

            // MARK: - Onboarding Section
            Section(l10n.string("settings.advanced.onboarding")) {
                HStack {
                    Button(l10n.string("settings.advanced.resetOnboarding")) {
                        viewModel.resetOnboarding()
                        showRestartNotice = true
                    }

                    if showRestartNotice {
                        Label(l10n.string("settings.advanced.restartNotice"),
                              systemImage: "arrow.clockwise")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }

            #if DEBUG
            // MARK: - Developer Section (spec 015, FR-045; Debug builds only)
            Section(l10n.string("settings.advanced.developer")) {
                VStack(alignment: .leading, spacing: 4) {
                    // Quickstart 2.6: the watchdog must log a WARN for this stall
                    Button(l10n.string("settings.advanced.simulateStall")) {
                        Thread.sleep(forTimeInterval: 3)
                    }
                    Text(l10n.string("settings.advanced.simulateStallHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
        .formStyle(.grouped)
    }

    private func chooseAudioSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appSettings.saveAudioFolderBookmark(for: url)
        resolvedFolderPath = url.path
        log.info("Audio save folder selected", metadata: ["path": url.path])
    }
}

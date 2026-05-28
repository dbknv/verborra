import SwiftUI

// MARK: - SettingsView (T038, V014: Sidebar style)

enum SettingsTab: String, CaseIterable {
    case general
    case prompts
    case hotkeys
    case llm
    case vocabularies
    case personalPreferences
    case about
    case advanced

    var title: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .general: return l10n.string("settings.tab.general")
        case .prompts: return l10n.string("settings.tab.prompts")
        case .hotkeys: return l10n.string("settings.tab.hotkeys")
        case .llm: return l10n.string("settings.tab.llm")
        case .vocabularies: return l10n.string("settings.tab.vocabularies")
        case .personalPreferences: return l10n.string("settings.tab.personalPreferences")
        case .about: return l10n.string("settings.tab.about")
        case .advanced: return l10n.string("settings.tab.advanced")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .prompts: return "text.bubble"
        case .hotkeys: return "keyboard"
        case .llm: return "brain"
        case .vocabularies: return "character.book.closed"
        case .personalPreferences: return "person.text.rectangle"
        case .about: return "info.circle"
        case .advanced: return "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(PromptsStore.self) private var promptsStore
    @Environment(VocabularyStore.self) private var vocabularyStore
    @Environment(AudioDeviceManager.self) private var audioDeviceManager: AudioDeviceManager?
    @State private var viewModel: SettingsViewModel?
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        Group {
            if let viewModel {
                NavigationSplitView {
                    List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
                    .toolbar(removing: .sidebarToggle)
                } detail: {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsTab(viewModel: viewModel)
                    case .prompts:
                        PromptsSettingsTab(viewModel: viewModel)
                    case .hotkeys:
                        HotkeysSettingsTab(viewModel: viewModel)
                    case .llm:
                        LLMSettingsTab(viewModel: viewModel)
                    case .vocabularies:
                        VocabulariesSettingsTab(viewModel: viewModel)
                    case .personalPreferences:
                        PersonalPreferencesSettingsTab(viewModel: viewModel)
                    case .about:
                        AboutSettingsTab()
                    case .advanced:
                        AdvancedSettingsTab(viewModel: viewModel)
                    }
                }
                .navigationSplitViewStyle(.prominentDetail)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            let deviceManager = audioDeviceManager ?? AudioDeviceManager(
                provider: CoreAudioDeviceProvider(), settings: appSettings
            )
            viewModel = SettingsViewModel(
                settings: appSettings,
                promptsStore: promptsStore,
                vocabularyStore: vocabularyStore,
                audioDeviceManager: deviceManager
            )
        }
    }
}

// MARK: - GeneralSettingsTab (T039, V012: Permission buttons)

struct GeneralSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n

    private let permissionManager = PermissionManager.shared

    var body: some View {
        Form {
            Section(l10n.string("settings.general.language")) {
                Picker(l10n.string("settings.general.interfaceLanguage"), selection: Binding(
                    get: { viewModel.settings.uiLanguage },
                    set: { viewModel.settings.uiLanguage = $0 }
                )) {
                    Text("English").tag(SupportedLanguage.en)
                    Text("Русский").tag(SupportedLanguage.ru)
                }
            }

            Section(l10n.string("settings.general.recording")) {
                Picker(l10n.string("settings.general.audioDevice"), selection: Binding(
                    get: { viewModel.settings.selectedAudioDeviceUID },
                    set: { viewModel.audioDeviceManager.selectDevice(uid: $0) }
                )) {
                    Text(l10n.string("settings.general.systemDefault")).tag("")
                    ForEach(viewModel.audioDevices, id: \.uid) { device in
                        Text(device.name).tag(device.uid)
                    }
                }

                Picker(l10n.string("settings.general.maxDuration"), selection: $viewModel.settings.maxRecordingDuration) {
                    ForEach(MaxRecordingDuration.allCases, id: \.self) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }

                Toggle(l10n.string("settings.general.autoRecord"), isOn: $viewModel.settings.autoRecord)
            }

            // T013 [US2] + T023 [US3]: Permission status via PermissionStatusView
            Section(l10n.string("settings.general.permissions")) {
                PermissionStatusView(permissionType: .accessibility)
                PermissionStatusView(permissionType: .microphone)
            }

            Section(l10n.string("settings.general.system")) {
                Toggle(l10n.string("settings.general.launchAtLogin"), isOn: Binding(
                    get: { viewModel.settings.launchAtLogin },
                    set: { viewModel.updateLaunchAtLogin($0) }
                ))

                if let error = viewModel.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // T013: Start monitoring via PermissionManager (FR-006)
            permissionManager.startMonitoring()
        }
        .onDisappear {
            permissionManager.stopMonitoring()
        }
        // T016 [US2]: Activate window on permission status change (FR-014)
        .onChange(of: permissionManager.microphoneStatus) { _, _ in
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: permissionManager.accessibilityStatus) { _, _ in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - PromptsSettingsTab (T047, T048, T049)

struct PromptsSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        HSplitView {
            promptsList
                .frame(minWidth: 160, maxWidth: 200)

            promptEditor
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptsList: some View {
        VStack(spacing: 0) {
            List(viewModel.promptsStore.prompts, selection: $viewModel.selectedPromptID) { prompt in
                HStack {
                    Text(prompt.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // T047: Lock icon for system prompts
                    if prompt.isSystem {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if prompt.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                .tag(prompt.id)
            }
            .onChange(of: viewModel.selectedPromptID) { _, newID in
                if let newID, let prompt = viewModel.promptsStore.prompts.first(where: { $0.id == newID }) {
                    viewModel.selectPrompt(prompt)
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button(action: { viewModel.addPrompt() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button(action: {
                    if let id = viewModel.selectedPromptID {
                        viewModel.deletePrompt(id)
                    }
                }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                // FR-009b: read-only prompts (currently simple-voice-to-text) cannot be deleted.
                .disabled(viewModel.selectedPromptID == nil
                    || viewModel.promptsStore.prompts.count <= 1
                    || viewModel.selectedPrompt?.isReadOnly == true)

                Spacer()

                Button(l10n.string("settings.prompts.default")) {
                    if let id = viewModel.selectedPromptID {
                        viewModel.setDefaultPrompt(id)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.selectedPrompt?.isDefault == true)
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var promptEditor: some View {
        if viewModel.selectedPromptID != nil {
            // FR-009b: editing/saving/deletion are gated by `isReadOnly`,
            // which currently matches `simple-voice-to-text` only.
            let isReadOnly = viewModel.selectedPrompt?.isReadOnly == true
            VStack(alignment: .leading, spacing: 12) {
                TextField(l10n.string("settings.prompts.name"), text: $viewModel.editingPromptName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isReadOnly)

                Text(l10n.string("settings.prompts.systemPrompt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $viewModel.editingPromptContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                    .border(Color.secondary.opacity(0.3))
                    .disabled(isReadOnly)

                // 013 (FR-002): per-prompt toggle for first-voice-turn answering.
                answerInFirstMessageRow(isReadOnly: isReadOnly)

                if !isReadOnly {
                    HStack {
                        Spacer()
                        Button(l10n.string("settings.prompts.save")) {
                            viewModel.saveCurrentPrompt()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(l10n.string("settings.prompts.selectPrompt"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @State private var showAnswerInFirstMessageHelp = false

    @ViewBuilder
    private func answerInFirstMessageRow(isReadOnly: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Toggle(
                l10n.string("settings.prompts.answerInFirstMessage.label"),
                isOn: $viewModel.editingAnswerInFirstMessage
            )
            .toggleStyle(.checkbox)
            .disabled(isReadOnly)

            Button {
                showAnswerInFirstMessageHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showAnswerInFirstMessageHelp, arrowEdge: .top) {
                Text(l10n.string("settings.prompts.answerInFirstMessage.help"))
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: 360, alignment: .leading)
            }

            Spacer()
        }
    }
}

// MARK: - AboutSettingsTab (T041, V015: License and links)

struct AboutSettingsTab: View {
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Verborra")
                .font(.title)
                .fontWeight(.bold)

            Text(l10n.string("settings.about.version", args: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(l10n.string("settings.about.description"))
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            Text(l10n.string("settings.about.license"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link(l10n.string("settings.about.documentation"), destination: URL(string: "https://github.com/apeek/speech-to-text")!)
                    .font(.caption)
                Link(l10n.string("settings.about.support"), destination: URL(string: "https://github.com/apeek/speech-to-text/issues")!)
                    .font(.caption)
            }

            Divider()
                .frame(width: 200)

            Text("© 2024 Apeek")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

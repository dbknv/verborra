import SwiftUI

struct LLMSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n
    @State private var showSTTInfo = false
    @State private var showLLMInfo = false
    @State private var showVoiceLanguageHint = false
    @State private var showTextLanguageHint = false

    var body: some View {
        Form {
            Section("OpenAI API") {
                SecureField(l10n.string("settings.llm.apiKey"), text: $viewModel.apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(l10n.string("settings.llm.saveAndVerify")) {
                        viewModel.validateAndSaveApiKey()
                    }
                    .disabled(!viewModel.validateApiKey() || viewModel.isValidating)

                    if viewModel.isValidating {
                        ProgressView()
                            .controlSize(.small)
                    } else if let result = viewModel.validationResult {
                        Label(
                            result ? l10n.string("settings.llm.keyValid") : l10n.string("settings.llm.keyInvalid"),
                            systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(result ? .green : .red)
                    } else if viewModel.isApiKeySaved {
                        Label(l10n.string("settings.llm.saved"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            Section {
                HStack(spacing: 4) {
                    Picker(l10n.string("settings.llm.sttModel"), selection: $viewModel.settings.selectedSTTModel) {
                        ForEach(STTModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    Button {
                        showSTTInfo.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showSTTInfo) {
                        modelInfoPopover(models: STTModel.allCases.map { ($0.displayName, $0.infoDescription) })
                    }
                }
            } header: {
                Text(l10n.string("settings.llm.sttSection"))
            }

            Section {
                HStack(spacing: 4) {
                    Picker(l10n.string("settings.llm.llmModel"), selection: $viewModel.settings.selectedLLMModel) {
                        ForEach(LLMModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    Button {
                        showLLMInfo.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showLLMInfo) {
                        modelInfoPopover(models: LLMModel.allCases.map { ($0.displayName, $0.infoDescription) })
                    }
                }
            } header: {
                Text(l10n.string("settings.llm.llmSection"))
            }
            // T051: Global voice/text language section
            Section {
                HStack(spacing: 4) {
                    Picker(l10n.string("settings.llm.voiceLanguage"), selection: Binding(
                        get: { viewModel.settings.globalVoiceLanguage },
                        set: { viewModel.settings.globalVoiceLanguage = $0 }
                    )) {
                        ForEach(SupportedLanguage.allCases, id: \.self) { lang in
                            Text(lang.localizedDisplayName(for: l10n.currentLanguage)).tag(lang)
                        }
                    }

                    Button {
                        showVoiceLanguageHint.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showVoiceLanguageHint) {
                        Text(l10n.string("settings.llm.voiceLanguageHint"))
                            .font(.caption)
                            .padding(12)
                            .frame(width: 280)
                    }
                }

                HStack(spacing: 4) {
                    Picker(l10n.string("settings.llm.textLanguage"), selection: Binding(
                        get: { viewModel.settings.globalTextLanguage },
                        set: { viewModel.settings.globalTextLanguage = $0 }
                    )) {
                        ForEach(SupportedLanguage.allCases, id: \.self) { lang in
                            Text(lang.localizedDisplayName(for: l10n.currentLanguage)).tag(lang)
                        }
                    }

                    Button {
                        showTextLanguageHint.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showTextLanguageHint) {
                        Text(l10n.string("settings.llm.textLanguageHint"))
                            .font(.caption)
                            .padding(12)
                            .frame(width: 280)
                    }
                }
            } header: {
                Text(l10n.string("settings.llm.languageSection"))
            }
        }
        .formStyle(.grouped)
    }

    private func modelInfoPopover(models: [(name: String, description: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(models, id: \.name) { model in
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.headline)
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

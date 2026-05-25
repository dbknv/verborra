import SwiftUI

// MARK: - VocabularyEditorDrawer (012-vocabularies)

/// Боковой drawer для создания/редактирования записи словаря.
/// - Режим создания: пустые поля, кнопка Add
/// - Режим редактирования: предзаполненные поля, кнопки «Применить» и «Удалить»
struct VocabularyEditorDrawer: View {
    let vocabularyStore: VocabularyStore
    let existingEntry: VocabularyEntry?
    let onDismiss: () -> Void
    @Environment(LocalizationManager.self) private var l10n

    @State private var targetWord: String
    @State private var alternatives: [String]

    private var isEditMode: Bool { existingEntry != nil }

    private var isFormValid: Bool {
        let trimmed = targetWord.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !alternatives.isEmpty
    }

    init(vocabularyStore: VocabularyStore, existingEntry: VocabularyEntry? = nil, onDismiss: @escaping () -> Void) {
        self.vocabularyStore = vocabularyStore
        self.existingEntry = existingEntry
        self.onDismiss = onDismiss
        _targetWord = State(initialValue: existingEntry?.targetWord ?? "")
        _alternatives = State(initialValue: existingEntry?.alternatives ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            HStack {
                Text(isEditMode
                    ? l10n.string("settings.vocabularies.editTitle")
                    : l10n.string("settings.vocabularies.addTitle"))
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Target Word
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.string("settings.vocabularies.targetWord"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(l10n.string("settings.vocabularies.targetWordPlaceholder"), text: $targetWord)
                    .textFieldStyle(.roundedBorder)
            }

            // Alternatives
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.string("settings.vocabularies.alternatives"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TagInputField(tags: $alternatives, placeholder: l10n.string("settings.vocabularies.alternativesPlaceholder"))
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .frame(minHeight: 80)
            }

            Spacer()

            Divider()

            // Actions
            if isEditMode {
                HStack {
                    Button(l10n.string("settings.vocabularies.delete"), role: .destructive) {
                        if let entry = existingEntry {
                            vocabularyStore.deleteEntry(entry.id)
                        }
                        onDismiss()
                    }

                    Spacer()

                    Button(l10n.string("settings.vocabularies.cancel")) { onDismiss() }

                    Button(l10n.string("settings.vocabularies.apply")) {
                        if let entry = existingEntry {
                            let updated = VocabularyEntry(
                                id: entry.id,
                                targetWord: targetWord,
                                alternatives: alternatives,
                                createdAt: entry.createdAt
                            )
                            vocabularyStore.updateEntry(updated)
                        }
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                }
            } else {
                HStack {
                    Spacer()

                    Button(l10n.string("settings.vocabularies.cancel")) { onDismiss() }

                    Button(l10n.string("settings.vocabularies.addButton")) {
                        let entry = VocabularyEntry(
                            targetWord: targetWord,
                            alternatives: alternatives
                        )
                        vocabularyStore.addEntry(entry)
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
    }
}

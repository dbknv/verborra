import SwiftUI

// MARK: - VocabulariesSettingsTab (012-vocabularies)

/// Вкладка Vocabularies в настройках: заголовок, описание, кнопка Add Replacement,
/// список карточек записей (read-only, хронологический порядок).
/// Создание и редактирование — через боковой drawer (inspector).
struct VocabulariesSettingsTab: View {
    let viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n

    @State private var showingDrawer = false
    @State private var editingEntry: VocabularyEntry?

    private var vocabularyStore: VocabularyStore { viewModel.vocabularyStore }

    var body: some View {
        HStack(spacing: 0) {
            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    Text(l10n.string("settings.vocabularies.title"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(l10n.string("settings.vocabularies.description"))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    // Add button
                    Button {
                        editingEntry = nil
                        showingDrawer = true
                    } label: {
                        Label(l10n.string("settings.vocabularies.addButton"), systemImage: "plus")
                    }

                    Divider()

                    // Cards list
                    if vocabularyStore.entries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "character.book.closed")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text(l10n.string("settings.vocabularies.emptyTitle"))
                                .foregroundStyle(.secondary)
                            Text(l10n.string("settings.vocabularies.emptyDescription"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(vocabularyStore.entries) { entry in
                                VocabularyCardView(entry: entry)
                                    .onTapGesture {
                                        editingEntry = entry
                                        showingDrawer = true
                                    }
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)

            // Drawer (side panel)
            if showingDrawer {
                Divider()

                VocabularyEditorDrawer(
                    vocabularyStore: vocabularyStore,
                    existingEntry: editingEntry,
                    onDismiss: {
                        showingDrawer = false
                        editingEntry = nil
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingDrawer)
    }
}

// MARK: - VocabularyCardView

/// Карточка записи словаря (read-only):
/// Серая подложка, серая подсказка «Target Word» сверху, целевое слово крупным жирным,
/// разделитель, серая подсказка «Alternatives», теги-чипсы.
private struct VocabularyCardView: View {
    let entry: VocabularyEntry
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Target Word
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.string("settings.vocabularies.targetWord"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.targetWord)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(2)
            }

            Divider()

            // Alternatives
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.string("settings.vocabularies.alternatives"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 4) {
                    ForEach(entry.alternatives, id: \.self) { alt in
                        Text(alt)
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

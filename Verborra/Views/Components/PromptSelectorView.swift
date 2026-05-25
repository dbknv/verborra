import SwiftUI

// MARK: - PromptSelectorView

struct PromptSelectorView: View {
    @Bindable var viewModel: RecordingViewModel

    private var isLocked: Bool {
        viewModel.windowPhase == .postProcessing
    }

    var body: some View {
        Menu {
            ForEach(viewModel.promptsStore.prompts) { prompt in
                Button {
                    viewModel.changePrompt(prompt)
                } label: {
                    HStack {
                        Text(prompt.name)
                        if prompt.id == viewModel.selectedPrompt.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(viewModel.selectedPrompt.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isLocked ? Color(hex: 0xACACAC) : Color(hex: 0x2C2C2C))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.borderlessButton)
        .disabled(isLocked)
    }
}

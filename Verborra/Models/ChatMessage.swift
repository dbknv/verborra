import Foundation

// MARK: - ChatMessageRole

enum ChatMessageRole: String, Codable {
    case system
    case transcription
    case user
    case assistant
}

// MARK: - ChatMessage

@Observable
final class ChatMessage: Identifiable {
    let id: UUID
    let role: ChatMessageRole
    var content: String
    let timestamp: Date
    var isCollapsed: Bool
    var isEditing: Bool
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        content: String,
        timestamp: Date = Date(),
        isCollapsed: Bool? = nil,
        isEditing: Bool = false,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isCollapsed = isCollapsed ?? (role == .system || role == .transcription)
        self.isEditing = isEditing
        self.isStreaming = isStreaming
    }
}

import Foundation
import JARVISCore

/// Handles "remember" and "createNote" intents by delegating to MemorySystem.
/// The actual storage call happens through a callback since ExecutionEngine
/// doesn't directly depend on MemorySystem.
public actor NoteExecutor {
    public typealias StoreNote = @Sendable (String, [String]) async throws -> Void

    private let storeNote: StoreNote

    public init(storeNote: @escaping StoreNote) {
        self.storeNote = storeNote
    }

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        let content: String

        switch intent.action {
        case .remember:
            content = intent.parameters["content"] ?? intent.target ?? ""
        case .createNote:
            content = intent.parameters["content"] ?? intent.target ?? ""
        default:
            return .failure(error: "NoteExecutor does not handle \(intent.action.rawValue)")
        }

        guard !content.isEmpty else {
            return .failure(error: "No content to save")
        }

        let tags = intent.parameters["tags"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []

        try await storeNote(content, tags)
        return .success(message: "Noted: \(content)")
    }
}

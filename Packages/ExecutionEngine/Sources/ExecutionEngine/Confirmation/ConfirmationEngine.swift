import Foundation
import JARVISCore

public actor ConfirmationEngine {
    public struct PendingConfirmation: Sendable {
        public let id: UUID
        public let intent: JARVISIntent
        public let prompt: String
        public let createdAt: Date
        public let expiresAt: Date

        public var isExpired: Bool { Date() > expiresAt }
    }

    private var pending: PendingConfirmation?
    private let ttl: TimeInterval

    public init(ttl: TimeInterval = 120) {
        self.ttl = ttl
    }

    /// Check if an intent needs confirmation before execution.
    public func check(intent: JARVISIntent) -> ExecutionResult? {
        guard intent.requiresConfirmation else { return nil }

        let prompt = formatConfirmationPrompt(intent: intent)
        let confirmation = PendingConfirmation(
            id: UUID(),
            intent: intent,
            prompt: prompt,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(ttl)
        )
        self.pending = confirmation

        return .confirmationRequired(prompt: prompt, pendingAction: intent)
    }

    /// Handle a yes/no confirmation response.
    public func handleConfirmation(confirmed: Bool) -> JARVISIntent? {
        guard let pending, !pending.isExpired else {
            self.pending = nil
            return nil
        }

        defer { self.pending = nil }
        return confirmed ? pending.intent : nil
    }

    /// Get current pending confirmation if any.
    public func currentPending() -> PendingConfirmation? {
        guard let pending, !pending.isExpired else {
            self.pending = nil
            return nil
        }
        return pending
    }

    /// Clear any pending confirmation.
    public func clear() {
        self.pending = nil
    }

    private func formatConfirmationPrompt(intent: JARVISIntent) -> String {
        switch intent.action {
        case .unlockDoor:
            return "Unlock \(intent.target ?? "the door")? Reply yes to confirm."
        case .sendMessage:
            let to = intent.parameters["to"] ?? "someone"
            return "Send message to \(to)? Reply yes to confirm."
        case .makeCall:
            let to = intent.parameters["to"] ?? "someone"
            return "Call \(to)? Reply yes to confirm."
        case .createCalendarEvent:
            let title = intent.parameters["title"] ?? intent.target ?? "event"
            return "Create calendar event '\(title)'? Reply yes to confirm."
        default:
            return "Execute '\(intent.humanReadable)'? Reply yes to confirm."
        }
    }
}

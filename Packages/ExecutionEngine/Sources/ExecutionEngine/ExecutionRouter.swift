import Foundation
import JARVISCore

public actor ExecutionRouter: CommandExecuting {
    private let homeKit: HomeKitExecutor
    private let shortcuts: ShortcutExecutor
    private let reminders: ReminderExecutor
    private let calendar: CalendarExecutor
    private let navigation: NavigationExecutor
    private let notes: NoteExecutor
    public let confirmation: ConfirmationEngine

    public init(storeNote: @escaping NoteExecutor.StoreNote) {
        self.homeKit = HomeKitExecutor()
        self.shortcuts = ShortcutExecutor()
        self.reminders = ReminderExecutor()
        self.calendar = CalendarExecutor()
        self.navigation = NavigationExecutor()
        self.notes = NoteExecutor(storeNote: storeNote)
        self.confirmation = ConfirmationEngine()
    }

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        // Handle confirmations first
        if intent.action == .confirmYes {
            if let confirmedIntent = await confirmation.handleConfirmation(confirmed: true) {
                return try await executeAction(confirmedIntent)
            }
            return .failure(error: "No pending action to confirm")
        }

        if intent.action == .confirmNo {
            _ = await confirmation.handleConfirmation(confirmed: false)
            return .success(message: "Action cancelled")
        }

        // Check if confirmation is needed
        if let confirmResult = await confirmation.check(intent: intent) {
            return confirmResult
        }

        return try await executeAction(intent)
    }

    private func executeAction(_ intent: JARVISIntent) async throws -> ExecutionResult {
        switch intent.action {
        // HomeKit
        case .turnOn, .turnOff, .setBrightness, .setTemperature,
             .lockDoor, .unlockDoor, .setThermostat, .setScene:
            return try await homeKit.execute(intent: intent)

        // Shortcuts
        case .runShortcut:
            return try await shortcuts.execute(intent: intent)

        // Reminders
        case .createReminder, .createTask:
            return try await reminders.execute(intent: intent)

        // Calendar
        case .createCalendarEvent:
            return try await calendar.execute(intent: intent)

        // Navigation
        case .getDirections:
            return try await navigation.execute(intent: intent)

        // Notes / Memory
        case .createNote, .remember:
            return try await notes.execute(intent: intent)

        // Recall handled by pipeline (queries MemorySystem directly)
        case .recall:
            return .failure(error: "Recall should be handled by pipeline")

        // Communication
        case .sendMessage:
            let to = intent.parameters["to"] ?? "unknown"
            let body = intent.parameters["body"] ?? intent.target ?? ""
            return .success(message: "Message to \(to): \(body) [sent via relay]")

        case .makeCall:
            let to = intent.parameters["to"] ?? "unknown"
            return .success(message: "Calling \(to) [not yet implemented]")

        // Health
        case .queryHealth:
            return .success(message: "Health queries not yet implemented")

        // Unknown
        case .unknown:
            return .failure(error: "I didn't understand that command")

        // Should not reach here
        case .confirmYes, .confirmNo:
            return .failure(error: "Unexpected confirmation action")
        }
    }
}

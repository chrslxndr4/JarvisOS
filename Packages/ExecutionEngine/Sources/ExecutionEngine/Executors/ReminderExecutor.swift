import Foundation
import JARVISCore

#if canImport(EventKit)
import EventKit
#endif

public actor ReminderExecutor {
    #if canImport(EventKit)
    private let eventStore = EKEventStore()
    #endif

    public init() {}

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        #if canImport(EventKit)
        return try await executeWithEventKit(intent: intent)
        #else
        return .failure(error: "EventKit not available")
        #endif
    }

    #if canImport(EventKit)
    private func executeWithEventKit(intent: JARVISIntent) async throws -> ExecutionResult {
        // Request access
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else {
            return .failure(error: "Reminders access denied")
        }

        let title = intent.parameters["title"] ?? intent.target ?? "Reminder"

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        // Parse due date if provided
        if let dueDateStr = intent.parameters["dueDate"] {
            reminder.dueDateComponents = parseDateComponents(from: dueDateStr)
        }

        if let notes = intent.parameters["notes"] {
            reminder.notes = notes
        }

        try eventStore.save(reminder, commit: true)
        return .success(message: "Reminder created: \(title)")
    }

    private func parseDateComponents(from string: String) -> DateComponents? {
        let lower = string.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lower == "tomorrow" {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrow)
        }
        if lower.contains("hour") {
            if let hours = Int(lower.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                let future = calendar.date(byAdding: .hour, value: hours, to: now)!
                return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: future)
            }
        }
        if lower.contains("minute") {
            if let mins = Int(lower.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                let future = calendar.date(byAdding: .minute, value: mins, to: now)!
                return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: future)
            }
        }

        // Try ISO date parsing
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) {
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }

        return nil
    }
    #endif
}

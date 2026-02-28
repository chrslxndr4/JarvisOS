import Foundation
import JARVISCore

#if canImport(EventKit)
import EventKit
#endif

public actor CalendarExecutor {
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
        let granted = try await eventStore.requestFullAccessToEvents()
        guard granted else {
            return .failure(error: "Calendar access denied")
        }

        let title = intent.parameters["title"] ?? intent.target ?? "Event"

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Parse start/end times
        let now = Date()
        if let startStr = intent.parameters["startTime"],
           let start = parseDate(from: startStr) {
            event.startDate = start
        } else {
            event.startDate = now.addingTimeInterval(3600) // default: 1h from now
        }

        if let endStr = intent.parameters["endTime"],
           let end = parseDate(from: endStr) {
            event.endDate = end
        } else {
            event.endDate = event.startDate.addingTimeInterval(3600) // 1h duration
        }

        if let location = intent.parameters["location"] {
            event.location = location
        }
        if let notes = intent.parameters["notes"] {
            event.notes = notes
        }

        event.isAllDay = intent.parameters["allDay"] == "true"

        try eventStore.save(event, span: .thisEvent)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return .success(message: "Event '\(title)' created for \(formatter.string(from: event.startDate))")
    }

    private func parseDate(from string: String) -> Date? {
        let lower = string.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lower == "tomorrow" {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }

        let iso = ISO8601DateFormatter()
        return iso.date(from: string)
    }
    #endif
}

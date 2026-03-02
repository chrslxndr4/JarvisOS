import AppIntents
import JARVISCore

// MARK: - Run JARVIS Command

struct RunJARVISCommand: AppIntent {
    static var title: LocalizedStringResource = "Run JARVIS Command"
    static var description = IntentDescription("Send a text command to JARVIS for processing.")
    static var openAppWhenRun = false

    @Parameter(title: "Command")
    var command: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Free-form text goes through full LLM pipeline with 10s timeout
        let result = await withTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    return try await PipelineAccessor.shared.processCommand(command)
                } catch {
                    return "Error: \(error.localizedDescription)"
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return "JARVIS is still thinking. The command is being processed — check the app for results."
            }
            // Return whichever finishes first
            let first = await group.next()!
            group.cancelAll()
            return first
        }
        return .result(value: result)
    }
}

// MARK: - Control Device

struct ControlDeviceIntent: AppIntent {
    static var title: LocalizedStringResource = "Control Smart Home Device"
    static var description = IntentDescription("Turn on/off a smart home device via JARVIS.")
    static var openAppWhenRun = false

    @Parameter(title: "Device Name")
    var deviceName: String

    @Parameter(title: "Action")
    var action: DeviceActionType

    enum DeviceActionType: String, AppEnum {
        case turnOn
        case turnOff

        static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device Action")
        static var caseDisplayRepresentations: [DeviceActionType: DisplayRepresentation] = [
            .turnOn: "Turn On",
            .turnOff: "Turn Off",
        ]
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Typed intent — bypass LLM, construct intent directly
        let intentAction: IntentAction = action == .turnOn ? .turnOn : .turnOff
        let intent = JARVISIntent(
            action: intentAction,
            target: deviceName,
            confidence: 1.0,
            humanReadable: "\(action == .turnOn ? "Turn on" : "Turn off") \(deviceName)"
        )

        do {
            let result = try await PipelineAccessor.shared.environment?.executeIntent(intent)
                ?? "JARVIS is not running. Please open the app."
            return .result(value: result)
        } catch {
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Create Reminder via JARVIS

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "JARVIS Reminder"
    static var description = IntentDescription("Create a reminder via JARVIS.")
    static var openAppWhenRun = false

    @Parameter(title: "Reminder Text")
    var reminderText: String

    @Parameter(title: "Due", default: nil)
    var dueDate: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Typed intent — bypass LLM
        var params: [String: String] = [:]
        if let dueDate {
            params["due"] = ISO8601DateFormatter().string(from: dueDate)
        }

        let intent = JARVISIntent(
            action: .createReminder,
            target: reminderText,
            parameters: params,
            confidence: 1.0,
            humanReadable: "Create reminder: \(reminderText)"
        )

        do {
            let result = try await PipelineAccessor.shared.environment?.executeIntent(intent)
                ?? "JARVIS is not running. Please open the app."
            return .result(value: result)
        } catch {
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Remember Something

struct RememberIntent: AppIntent {
    static var title: LocalizedStringResource = "JARVIS Remember"
    static var description = IntentDescription("Ask JARVIS to remember something.")
    static var openAppWhenRun = false

    @Parameter(title: "What to Remember")
    var content: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Typed intent — bypass LLM
        let intent = JARVISIntent(
            action: .remember,
            target: content,
            confidence: 1.0,
            humanReadable: "Remember: \(content)"
        )

        do {
            let result = try await PipelineAccessor.shared.environment?.executeIntent(intent)
                ?? "JARVIS is not running. Please open the app."
            return .result(value: result)
        } catch {
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Recall

struct RecallIntent: AppIntent {
    static var title: LocalizedStringResource = "JARVIS Recall"
    static var description = IntentDescription("Ask JARVIS to recall information.")
    static var openAppWhenRun = false

    @Parameter(title: "Query")
    var query: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Typed intent — bypass LLM
        let intent = JARVISIntent(
            action: .recall,
            target: query,
            parameters: ["query": query],
            confidence: 1.0,
            humanReadable: "Recall: \(query)"
        )

        do {
            let result = try await PipelineAccessor.shared.environment?.executeIntent(intent)
                ?? "JARVIS is not running. Please open the app."
            return .result(value: result)
        } catch {
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Shortcuts Provider

struct JARVISShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunJARVISCommand(),
            phrases: [
                "Ask \(.applicationName) to \(\.$command)",
                "Tell \(.applicationName) \(\.$command)",
                "\(.applicationName) \(\.$command)",
            ],
            shortTitle: "JARVIS Command",
            systemImageName: "brain"
        )

        AppShortcut(
            intent: ControlDeviceIntent(),
            phrases: [
                "\(.applicationName) \(\.$action) \(\.$deviceName)",
            ],
            shortTitle: "Control Device",
            systemImageName: "lightbulb"
        )

        AppShortcut(
            intent: RememberIntent(),
            phrases: [
                "\(.applicationName) remember \(\.$content)",
            ],
            shortTitle: "Remember",
            systemImageName: "brain.head.profile"
        )

        AppShortcut(
            intent: RecallIntent(),
            phrases: [
                "Ask \(.applicationName) about \(\.$query)",
            ],
            shortTitle: "Recall",
            systemImageName: "magnifyingglass"
        )
    }
}

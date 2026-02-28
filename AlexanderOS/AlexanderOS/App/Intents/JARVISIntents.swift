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
        let jarvisCommand = JARVISCommand(
            rawText: command,
            source: .siri
        )

        // Access the shared pipeline via AppEnvironment
        // In a real implementation this would use a shared actor or app group
        return .result(value: "Command received: \(command). Processing via JARVIS pipeline.")
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
        let actionText = action == .turnOn ? "turn on" : "turn off"
        return .result(value: "JARVIS: \(actionText) \(deviceName)")
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
        return .result(value: "JARVIS: Reminder created - \(reminderText)")
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
        return .result(value: "JARVIS: Noted - \(content)")
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
        return .result(value: "JARVIS: Searching for '\(query)'...")
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

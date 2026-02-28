import Foundation
import JARVISCore

/// Handles formatting and sending responses back through the relay.
public actor ResponseFormatter: ResponseHandling {
    /// Callback to send a text reply via the WebSocket relay.
    public typealias SendReply = @Sendable (String, String, String?) async throws -> Void
    // Parameters: (recipientJID, messageBody, quotedMessageId?)

    private var sendReplyCallback: SendReply?
    private var lastRecipientJID: String?

    public init() {}

    /// Configure the reply transport.
    public func configure(sendReply: @escaping SendReply) {
        self.sendReplyCallback = sendReply
    }

    /// Set the default recipient JID (last person who sent a command).
    public func setRecipient(_ jid: String) {
        self.lastRecipientJID = jid
    }

    // MARK: - ResponseHandling

    public func send(response: ExecutionResult, for command: JARVISCommand) async throws {
        let message = format(response: response)

        guard let sendReply = sendReplyCallback else {
            // No transport configured - just log
            return
        }

        guard let jid = lastRecipientJID else {
            return
        }

        try await sendReply(jid, message, nil)
    }

    public func formatConfirmation(intent: JARVISIntent) -> String {
        switch intent.action {
        case .unlockDoor:
            return "Unlock \(intent.target ?? "the door")? Reply *yes* to confirm."
        case .sendMessage:
            let to = intent.parameters["to"] ?? "the contact"
            let body = intent.parameters["body"]?.prefix(50) ?? ""
            return "Send to \(to): \"\(body)\"? Reply *yes* to confirm."
        case .makeCall:
            let to = intent.parameters["to"] ?? "the contact"
            return "Call \(to)? Reply *yes* to confirm."
        case .createCalendarEvent:
            let title = intent.parameters["title"] ?? intent.target ?? "event"
            return "Create event '\(title)'? Reply *yes* to confirm."
        case .lockDoor:
            return "Lock \(intent.target ?? "the door")? Reply *yes* to confirm."
        case .turnOff:
            return "Turn off \(intent.target ?? "the device")? Reply *yes* to confirm."
        case .setThermostat:
            let temp = intent.parameters["temperature"] ?? "?"
            return "Set \(intent.target ?? "thermostat") to \(temp)°? Reply *yes* to confirm."
        default:
            return "\(intent.humanReadable)? Reply *yes* to confirm."
        }
    }

    // MARK: - Formatting

    public func format(response: ExecutionResult) -> String {
        switch response {
        case .success(let message):
            return message

        case .failure(let error):
            return "Sorry, that didn't work: \(error)"

        case .confirmationRequired(let prompt, _):
            return prompt

        case .ambiguous(let options):
            var text = "I found multiple matches. Which did you mean?\n"
            for (i, option) in options.enumerated() {
                text += "\(i + 1). \(option)\n"
            }
            return text.trimmingCharacters(in: .newlines)
        }
    }
}

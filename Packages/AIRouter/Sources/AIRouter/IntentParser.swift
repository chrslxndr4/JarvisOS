import Foundation
import JARVISCore

// MARK: - Errors

enum IntentParserError: Error, LocalizedError {
    case invalidJSON(String)
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Invalid JSON from LLM: \(detail)"
        case .missingRequiredField(let field):
            return "LLM response missing required field: '\(field)'"
        }
    }
}

// MARK: - Parser

/// Parses the JSON string produced by `LlamaEngine.generate` into a typed
/// `JARVISIntent`.
///
/// When the GBNF grammar is in use the JSON is structurally guaranteed to be
/// valid, so most error paths here are last-resort safety nets.  The parser
/// is a value type with no mutable state so it can be called from any
/// concurrency context.
struct IntentParser {

    /// Parse a JSON string into a `JARVISIntent`.
    ///
    /// - Parameter json: Raw string returned by the LLM (may contain leading /
    ///                   trailing whitespace).
    /// - Throws: `IntentParserError` if the string cannot be decoded.
    static func parse(json: String) throws -> JARVISIntent {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmed.data(using: .utf8) else {
            throw IntentParserError.invalidJSON("String could not be encoded as UTF-8")
        }

        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Surface the first 200 characters to aid debugging without
            // flooding logs with huge strings.
            throw IntentParserError.invalidJSON(
                "Not a valid JSON object: \(trimmed.prefix(200))"
            )
        }

        // ------------------------------------------------------------------
        // Required fields
        // ------------------------------------------------------------------
        guard let actionStr = dict["action"] as? String else {
            throw IntentParserError.missingRequiredField("action")
        }

        // Fall back to .unknown for any action value that isn't in the enum,
        // rather than throwing.  This is defensive: the grammar should
        // prevent it, but belt-and-suspenders is warranted here.
        let action = IntentAction(rawValue: actionStr) ?? .unknown

        // ------------------------------------------------------------------
        // Optional / derived fields
        // ------------------------------------------------------------------
        let target        = dict["target"] as? String
        let confidence    = dict["confidence"] as? Double ?? 0.0
        let humanReadable = dict["humanReadable"] as? String ?? actionStr

        // Parameters values are always strings per the grammar, but we
        // stringify any non-string values defensively.
        var parameters: [String: String] = [:]
        if let params = dict["parameters"] as? [String: Any] {
            for (key, value) in params {
                parameters[key] = "\(value)"
            }
        }

        let needsConfirmation = Self.requiresConfirmation(
            action: action,
            confidence: confidence
        )

        return JARVISIntent(
            action: action,
            target: target,
            parameters: parameters,
            confidence: confidence,
            requiresConfirmation: needsConfirmation,
            humanReadable: humanReadable
        )
    }

    // MARK: - Confirmation policy

    /// Decides whether an intent must be confirmed by the user before
    /// execution.
    ///
    /// Two tiers:
    /// - **Always confirm** — actions that are difficult or impossible to
    ///   reverse (sending a message, making a call, creating calendar events,
    ///   unlocking a door).
    /// - **Confirm when uncertain** — actions that are reversible but
    ///   potentially disruptive when the model is not confident (turning off
    ///   devices, adjusting the thermostat, locking a door, creating
    ///   reminders).  Triggered below the 0.85 confidence threshold.
    private static func requiresConfirmation(
        action: IntentAction,
        confidence: Double
    ) -> Bool {
        let alwaysConfirm: Set<IntentAction> = [
            .unlockDoor, .sendMessage, .makeCall, .createCalendarEvent
        ]
        if alwaysConfirm.contains(action) { return true }

        let confirmWhenUnsure: Set<IntentAction> = [
            .turnOff, .setThermostat, .lockDoor, .createReminder
        ]
        if confirmWhenUnsure.contains(action) && confidence < 0.85 { return true }

        return false
    }
}

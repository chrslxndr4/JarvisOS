import Foundation

/// Handles incoming `jarvis://` URLs for x-callback-url round trips and deep linking.
///
/// Supported URL formats:
/// - `jarvis://callback?id=UUID&result=encoded_text` — shortcut result callback
/// - `jarvis://callback?id=UUID&error=encoded_text` — shortcut error callback
/// - `jarvis://command?text=encoded_text` — deep link to process a command
@MainActor
final class JARVISURLHandler {
    static let shared = JARVISURLHandler()
    private init() {}

    private var pendingCallbacks: [String: CheckedContinuation<String, Error>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    enum URLHandlerError: LocalizedError {
        case timeout
        case cancelled
        case shortcutError(String)
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .timeout: return "Shortcut timed out after 30 seconds"
            case .cancelled: return "Shortcut was cancelled"
            case .shortcutError(let msg): return "Shortcut error: \(msg)"
            case .invalidURL: return "Invalid callback URL"
            }
        }
    }

    // MARK: - Incoming URL Handling

    func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else { return }

        switch host {
        case "callback":
            handleCallback(components: components)
        case "command":
            handleCommand(components: components)
        default:
            break
        }
    }

    private func handleCallback(components: URLComponents) {
        let params = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )

        guard let id = params["id"] else { return }

        // Cancel the timeout
        timeoutTasks[id]?.cancel()
        timeoutTasks.removeValue(forKey: id)

        if let result = params["result"] {
            pendingCallbacks[id]?.resume(returning: result)
            pendingCallbacks.removeValue(forKey: id)
        } else if let error = params["error"] {
            let err = error == "cancelled" ? URLHandlerError.cancelled : URLHandlerError.shortcutError(error)
            pendingCallbacks[id]?.resume(throwing: err)
            pendingCallbacks.removeValue(forKey: id)
        }
    }

    private func handleCommand(components: URLComponents) {
        guard let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
              !text.isEmpty else { return }

        Task {
            _ = try? await PipelineAccessor.shared.processCommand(text)
        }
    }

    // MARK: - Callback Registration

    /// Register a callback continuation for a shortcut invocation.
    /// Returns the result string when the shortcut calls back via `jarvis://callback`.
    /// Times out after 30 seconds.
    func registerCallback(id: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            pendingCallbacks[id] = continuation

            // Set up 30s timeout
            timeoutTasks[id] = Task {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if pendingCallbacks.removeValue(forKey: id) != nil {
                    continuation.resume(throwing: URLHandlerError.timeout)
                }
                timeoutTasks.removeValue(forKey: id)
            }
        }
    }
}

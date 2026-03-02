import Foundation
import JARVISCore

#if canImport(UIKit)
import UIKit
#endif

public actor ShortcutExecutor {
    private let runner: ShortcutRunning?

    public init(runner: ShortcutRunning? = nil) {
        self.runner = runner
    }

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        guard let shortcutName = intent.target else {
            return .failure(error: "No shortcut name specified")
        }

        // If we have a runner, use it for bidirectional communication
        if let runner {
            do {
                let result = try await runner.runShortcut(
                    name: shortcutName,
                    input: intent.parameters.isEmpty ? nil : intent.parameters
                )
                return .success(message: result)
            } catch {
                return .failure(error: "Shortcut '\(shortcutName)' failed: \(error.localizedDescription)")
            }
        }

        // Fallback: fire-and-forget via shortcuts:// URL
        guard let encoded = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else {
            return .failure(error: "Invalid shortcut name: \(shortcutName)")
        }

        #if canImport(UIKit)
        let opened = await UIApplication.shared.open(url)
        if opened {
            return .success(message: "Running shortcut '\(shortcutName)'")
        } else {
            return .failure(error: "Failed to open shortcut '\(shortcutName)'. Is it installed?")
        }
        #else
        return .failure(error: "Shortcuts execution requires iOS")
        #endif
    }
}

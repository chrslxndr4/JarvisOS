import Foundation
import JARVISCore

#if canImport(UIKit)
import UIKit
#endif

public actor ShortcutExecutor {
    public init() {}

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        guard let shortcutName = intent.target else {
            return .failure(error: "No shortcut name specified")
        }

        // Build shortcuts:// URL
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

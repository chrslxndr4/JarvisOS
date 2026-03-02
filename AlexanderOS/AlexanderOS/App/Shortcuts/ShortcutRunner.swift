import Foundation
import UIKit
import JARVISCore

/// Concrete implementation of `ShortcutRunning` that uses x-callback-url
/// to run Apple Shortcuts and await their results via `jarvis://callback`.
final class ShortcutRunner: ShortcutRunning {

    func runShortcut(name: String, input: [String: String]?) async throws -> String {
        let callbackID = UUID().uuidString

        // Build the x-callback-url
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"

        var queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "jarvis://callback?id=\(callbackID)&result="),
            URLQueryItem(name: "x-error", value: "jarvis://callback?id=\(callbackID)&error="),
            URLQueryItem(name: "x-cancel", value: "jarvis://callback?id=\(callbackID)&error=cancelled"),
        ]

        // Pass input as text
        if let input, !input.isEmpty {
            if input.count == 1, let singleValue = input.values.first {
                // Single value — pass directly as text input
                queryItems.append(URLQueryItem(name: "input", value: singleValue))
                queryItems.append(URLQueryItem(name: "input-type", value: "text"))
            } else {
                // Multiple values — JSON encode
                let jsonData = try JSONSerialization.data(withJSONObject: input)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                queryItems.append(URLQueryItem(name: "input", value: jsonString))
                queryItems.append(URLQueryItem(name: "input-type", value: "text"))
            }
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw JARVISURLHandler.URLHandlerError.invalidURL
        }

        // Open the Shortcuts URL and register callback
        let handler = await MainActor.run { JARVISURLHandler.shared }

        await MainActor.run {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    Task { @MainActor in
                        // If the URL couldn't be opened, we need to clean up the pending callback
                        // The callback will be cleaned up by the timeout, or we can handle it here
                    }
                }
            }
        }

        // Wait for the callback (30s timeout built into handler)
        return try await handler.registerCallback(id: callbackID)
    }
}

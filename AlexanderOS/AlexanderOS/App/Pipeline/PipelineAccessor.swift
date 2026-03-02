import Foundation

/// Process-wide singleton that gives App Intents access to the running pipeline.
/// App Intents can't access @StateObject, so they need this static entry point.
@MainActor
final class PipelineAccessor {
    static let shared = PipelineAccessor()
    weak var environment: AppEnvironment?
    private init() {}

    func processCommand(_ text: String) async throws -> String {
        guard let env = environment else {
            return "JARVIS is not running. Please open the app."
        }
        return try await env.processCommand(text)
    }
}

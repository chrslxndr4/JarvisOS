import Foundation
import JARVISCore

/// Routes a `JARVISCommand` through the on-device LLM pipeline and returns a
/// structured `JARVISIntent`.
///
/// The pipeline is:
/// 1. Build a ChatML prompt that injects the live `CommandCatalog` and recent
///    context (via `PromptBuilder`).
/// 2. Run inference with `LlamaEngine`, constrained by the GBNF grammar in
///    `IntentGrammar` so the model can only emit valid intent JSON.
/// 3. Parse the JSON into a `JARVISIntent` via `IntentParser`.
///
/// `IntentClassifier` is an `actor` so its internal state (warm-up flag, engine
/// reference) is safe to access from concurrent callers without explicit locking.
public actor IntentClassifier: IntentRouting {

    private let engine: LlamaEngine
    private var isWarmedUp = false

    /// - Parameter engine: The `LlamaEngine` instance to use.  Defaults to a
    ///   fresh engine so callers can rely on the no-argument convenience init.
    public init(engine: LlamaEngine = LlamaEngine()) {
        self.engine = engine
    }

    // MARK: - IntentRouting

    public func route(
        command: JARVISCommand,
        catalog: CommandCatalog
    ) async throws -> JARVISIntent {
        // Build the full ChatML prompt with the live catalog injected.
        // Recent context is wired to the MemorySystem in a future phase.
        let recentContext: [String] = [] // TODO: inject from MemorySystem
        let promptBuilder = PromptBuilder(catalog: catalog, recentContext: recentContext)
        let fullPrompt    = promptBuilder.buildFullPrompt(command: command.rawText)

        // Run inference.  The GBNF grammar forces the model to emit valid
        // intent JSON, so IntentParser.parse should not fail in practice.
        let jsonOutput = try await engine.generate(
            prompt: fullPrompt,
            grammar: IntentGrammar.grammar,
            maxTokens: 256,
            temperature: 0.1
        )

        // Decode the constrained JSON output into a typed JARVISIntent.
        return try IntentParser.parse(json: jsonOutput)
    }

    /// Load the model into memory so the first `route` call has no cold-start
    /// latency.  Safe to call multiple times — subsequent calls are no-ops.
    public func warmUp() async throws {
        guard !isWarmedUp else { return }

        // Locate the model file that was downloaded by ModelDownloadManager.
        let downloadManager = try ModelDownloadManager()
        guard let modelURL = await downloadManager.localPath(for: .qwen2_5_1_5B) else {
            throw LlamaEngineError.modelNotLoaded
        }

        try await engine.loadModel(at: modelURL.path, contextSize: 2048)
        isWarmedUp = true
    }

    /// Unload the model and release Metal / RAM resources.  Call this when the
    /// app moves to the background and inference is not expected imminently.
    public func coolDown() async {
        await engine.unload()
        isWarmedUp = false
    }
}

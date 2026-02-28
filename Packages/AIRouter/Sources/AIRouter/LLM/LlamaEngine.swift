import Foundation
import JARVISCore

public enum LlamaEngineError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case inferenceError(String)
    case grammarError(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "LLM model not loaded"
        case .modelLoadFailed(let msg): return "Model load failed: \(msg)"
        case .inferenceError(let msg): return "Inference error: \(msg)"
        case .grammarError(let msg): return "Grammar error: \(msg)"
        }
    }
}

/// Actor wrapping llama.cpp for on-device LLM inference.
/// Uses GBNF grammar constraints to guarantee valid JSON output.
///
/// When LLAMA_CPP_AVAILABLE is defined (i.e. the llama.cpp XCFramework has been
/// linked into the Xcode project), this actor calls through to the real C API.
/// Otherwise it falls back to a deterministic mock that keeps the package
/// buildable standalone via `swift build`.
public actor LlamaEngine {
    private var isLoaded = false
    private var modelPath: String?

    // llama.cpp opaque pointers (only used when the C library is present)
    #if LLAMA_CPP_AVAILABLE
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    #endif

    public init() {}

    // MARK: - Public API

    /// Load a GGUF model from disk.
    ///
    /// - Parameters:
    ///   - path: Absolute filesystem path to the `.gguf` model file.
    ///   - contextSize: KV-cache context window in tokens (default 2 048).
    public func loadModel(at path: String, contextSize: Int = 2048) throws {
        self.modelPath = path

        #if LLAMA_CPP_AVAILABLE
        // Initialise the llama backend (no-op if already done).
        llama_backend_init()

        // ------------------------------------------------------------------
        // Model parameters
        // ------------------------------------------------------------------
        var modelParams = llama_model_default_params()
        // Offload all transformer layers to Metal on Apple Silicon.
        modelParams.n_gpu_layers = 99

        guard let m = llama_model_load_from_file(path, modelParams) else {
            throw LlamaEngineError.modelLoadFailed("Failed to load model at \(path)")
        }
        self.model = m

        // ------------------------------------------------------------------
        // Context parameters
        // ------------------------------------------------------------------
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx     = UInt32(contextSize)
        ctxParams.n_batch   = 512
        // Cap thread count to 4 to avoid thermal pressure on mobile devices.
        ctxParams.n_threads = UInt32(min(ProcessInfo.processInfo.activeProcessorCount, 4))
        ctxParams.flash_attn = true

        guard let ctx = llama_init_from_model(m, ctxParams) else {
            llama_model_free(m)
            self.model = nil
            throw LlamaEngineError.modelLoadFailed("Failed to create inference context")
        }
        self.context = ctx
        #endif

        self.isLoaded = true
    }

    /// Run inference with a prompt, optionally constrained by a GBNF grammar.
    ///
    /// - Parameters:
    ///   - prompt:      The full formatted prompt string (e.g. ChatML).
    ///   - grammar:     Optional GBNF grammar source. When provided, the
    ///                  sampler will only produce tokens that satisfy the
    ///                  grammar, guaranteeing well-formed JSON output.
    ///   - maxTokens:   Hard cap on generated tokens (default 512).
    ///   - temperature: Sampling temperature. Use low values (≤0.1) for
    ///                  deterministic structured output (default 0.1).
    /// - Returns: The generated text string.
    public func generate(
        prompt: String,
        grammar: String? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.1
    ) throws -> String {
        guard isLoaded else { throw LlamaEngineError.modelNotLoaded }

        #if LLAMA_CPP_AVAILABLE
        return try generateWithLlama(
            prompt: prompt,
            grammar: grammar,
            maxTokens: maxTokens,
            temperature: temperature
        )
        #else
        // Development fallback: deterministic mock responses without any C
        // library dependency so the package compiles standalone.
        return mockGenerate(prompt: prompt)
        #endif
    }

    /// Unload the model and free all llama.cpp resources.
    public func unload() {
        #if LLAMA_CPP_AVAILABLE
        if let ctx = context {
            llama_free(ctx)
            self.context = nil
        }
        if let m = model {
            llama_model_free(m)
            self.model = nil
        }
        llama_backend_free()
        #endif
        self.isLoaded = false
    }

    /// Whether a model is currently loaded and ready for inference.
    public var loaded: Bool { isLoaded }

    // deinit intentionally omitted: actor-isolated state cannot be accessed
    // from deinit. Resources are released via unload() or reclaimed by the OS.

    // MARK: - llama.cpp inference path

    #if LLAMA_CPP_AVAILABLE
    private func generateWithLlama(
        prompt: String,
        grammar: String?,
        maxTokens: Int,
        temperature: Float
    ) throws -> String {
        guard let model, let context else { throw LlamaEngineError.modelNotLoaded }

        // ------------------------------------------------------------------
        // 1. Tokenise the prompt
        // ------------------------------------------------------------------
        let promptTokens = tokenize(text: prompt, model: model)

        // Clear the KV cache so previous calls don't bleed into this one.
        llama_kv_cache_clear(context)

        // ------------------------------------------------------------------
        // 2. Build sampler chain
        // ------------------------------------------------------------------
        let sparams  = llama_sampler_chain_default_params()
        let sampler  = llama_sampler_chain_init(sparams)

        // Temperature must be added before the distribution sampler.
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max))
        )

        // Grammar constraint — applied last so it gates the final sample.
        if let grammar {
            let grammarSampler = llama_sampler_init_grammar(model, grammar, "root")
            llama_sampler_chain_add(sampler, grammarSampler)
        }

        // ------------------------------------------------------------------
        // 3. Process prompt tokens (prefill)
        // ------------------------------------------------------------------
        var batch = llama_batch_init(Int32(promptTokens.count), 0, 1)
        defer { llama_batch_free(batch) }

        for (i, token) in promptTokens.enumerated() {
            // Set logits=true only for the last token so we can sample from it.
            llama_batch_add(&batch, token, Int32(i), [0], i == promptTokens.count - 1)
        }

        guard llama_decode(context, batch) == 0 else {
            llama_sampler_free(sampler)
            throw LlamaEngineError.inferenceError("Failed to process prompt tokens")
        }

        // ------------------------------------------------------------------
        // 4. Autoregressive decode loop
        // ------------------------------------------------------------------
        var outputTokens: [llama_token] = []
        var curPos = Int32(promptTokens.count)

        for _ in 0..<maxTokens {
            let newToken = llama_sampler_sample(sampler, context, -1)

            // Stop on any end-of-generation token (EOS, EOT, etc.).
            if llama_token_is_eog(model, newToken) { break }

            outputTokens.append(newToken)

            var nextBatch = llama_batch_init(1, 0, 1)
            llama_batch_add(&nextBatch, newToken, curPos, [0], true)

            let decodeResult = llama_decode(context, nextBatch)
            llama_batch_free(nextBatch)

            guard decodeResult == 0 else { break }
            curPos += 1
        }

        llama_sampler_free(sampler)

        // ------------------------------------------------------------------
        // 5. Detokenise and return
        // ------------------------------------------------------------------
        return detokenize(tokens: outputTokens, model: model)
    }

    /// Convert a Swift string to llama token IDs.
    private func tokenize(text: String, model: OpaquePointer) -> [llama_token] {
        let utf8      = Array(text.utf8)
        let maxTokens = utf8.count + 16
        var tokens    = [llama_token](repeating: 0, count: maxTokens)
        let nTokens   = llama_tokenize(
            model, text, Int32(utf8.count),
            &tokens, Int32(maxTokens),
            true,   // add_bos
            false   // special
        )
        return Array(tokens.prefix(Int(nTokens)))
    }

    /// Convert llama token IDs back to a UTF-8 string.
    private func detokenize(tokens: [llama_token], model: OpaquePointer) -> String {
        var result = ""
        for token in tokens {
            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(model, token, &buf, 256, 0, false)
            if len > 0 {
                result += String(cString: buf)
            }
        }
        return result
    }
    #endif

    // MARK: - Mock fallback (no llama.cpp)

    /// Deterministic mock that returns plausible JSON intent strings so the
    /// rest of the pipeline can be developed and tested without the real
    /// llama.cpp library present.
    private func mockGenerate(prompt: String) -> String {
        let lower = prompt.lowercased()

        if lower.contains("turn on") || lower.contains("turn off") {
            let action = lower.contains("turn on") ? "turnOn" : "turnOff"
            let verb   = action == "turnOn" ? "on" : "off"
            return """
            {"action":"\(action)","target":"living room lights","parameters":{},"confidence":0.95,"humanReadable":"Turn \(verb) the living room lights"}
            """
        }

        if lower.contains("remind") {
            return """
            {"action":"createReminder","target":null,"parameters":{"title":"Reminder from voice command","dueDate":"tomorrow"},"confidence":0.85,"humanReadable":"Create a reminder"}
            """
        }

        if lower.contains("yes") || lower.contains("confirm") {
            return """
            {"action":"confirmYes","target":null,"parameters":{},"confidence":0.99,"humanReadable":"Confirmed"}
            """
        }

        if lower.contains("no") || lower.contains("cancel") {
            return """
            {"action":"confirmNo","target":null,"parameters":{},"confidence":0.99,"humanReadable":"Cancelled"}
            """
        }

        if lower.contains("lock") {
            return """
            {"action":"lockDoor","target":"front door","parameters":{},"confidence":0.90,"humanReadable":"Lock the front door"}
            """
        }

        if lower.contains("brightness") || lower.contains("dim") {
            return """
            {"action":"setBrightness","target":"living room lights","parameters":{"brightness":"50"},"confidence":0.88,"humanReadable":"Set brightness to 50%"}
            """
        }

        return """
        {"action":"unknown","target":null,"parameters":{},"confidence":0.0,"humanReadable":"Could not understand the command"}
        """
    }
}

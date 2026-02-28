import Foundation
import JARVISCore

/// Builds structured prompts for the LLM inference step.
///
/// `PromptBuilder` combines three sources of context into a single
/// ChatML-formatted string:
///
/// 1. **System instruction** — rules that constrain how the model must behave.
/// 2. **Catalog injection** — the live set of devices, scenes, and shortcuts
///    that actually exist in the user's home, so the model only references
///    things that are real.
/// 3. **Recent context** — the last few interaction summaries from the memory
///    system, giving the model short-term conversational awareness.
///
/// The output format is ChatML (`<|im_start|>` / `<|im_end|>`) which is
/// natively understood by Qwen 2.5 Instruct models.
public struct PromptBuilder {

    private let catalog: CommandCatalog
    private let recentContext: [String]

    /// - Parameters:
    ///   - catalog:       The current `CommandCatalog` snapshot.
    ///   - recentContext: Optional recent interaction summaries (newest last).
    ///                    At most the five most recent entries are injected.
    public init(catalog: CommandCatalog, recentContext: [String] = []) {
        self.catalog       = catalog
        self.recentContext = recentContext
    }

    // MARK: - Public

    /// The system turn content: rules + catalog + optional context.
    public func buildSystemPrompt() -> String {
        var parts: [String] = []

        parts.append("""
        You are JARVIS, a smart home and personal assistant. \
        Parse the user's command and return a structured JSON intent.

        RULES:
        1. ONLY use actions from the allowed list
        2. ONLY reference devices, scenes, and shortcuts that exist in the catalog below
        3. If you cannot match the command to a known action, use action "unknown" with confidence 0.0
        4. Set confidence between 0.0 and 1.0 based on how certain you are
        5. Set target to the device/item name exactly as listed in the catalog
        6. Include relevant parameters (brightness as 0-100, temperature in celsius, etc.)
        7. humanReadable should be a short description of what will happen
        """)

        // Inject catalog so the model knows what actually exists.
        let catalogDesc = catalog.promptDescription
        if !catalogDesc.isEmpty {
            parts.append("AVAILABLE CATALOG:\n\(catalogDesc)")
        } else {
            parts.append("AVAILABLE CATALOG: (none discovered yet)")
        }

        // Inject the tail of the recent-context window (up to 5 entries).
        if !recentContext.isEmpty {
            let contextStr = recentContext.suffix(5).joined(separator: "\n")
            parts.append("RECENT CONTEXT:\n\(contextStr)")
        }

        return parts.joined(separator: "\n\n")
    }

    /// The user turn content: the raw command text.
    public func buildUserPrompt(command: String) -> String {
        "Parse this command: \(command)"
    }

    /// The full ChatML-formatted prompt ready for tokenisation.
    ///
    /// The prompt ends with `<|im_start|>assistant` (no closing tag) so the
    /// model immediately begins generating the assistant reply — the JSON
    /// intent object — without any preamble.
    public func buildFullPrompt(command: String) -> String {
        let system = buildSystemPrompt()
        let user   = buildUserPrompt(command: command)

        return """
        <|im_start|>system
        \(system)<|im_end|>
        <|im_start|>user
        \(user)<|im_end|>
        <|im_start|>assistant
        """
    }
}

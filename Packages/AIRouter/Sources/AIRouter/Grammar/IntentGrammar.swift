import Foundation

/// Provides the GBNF grammar that constrains LLM output to valid JARVISIntent
/// JSON.  By feeding this grammar into the llama.cpp sampler chain, the model
/// is physically unable to produce tokens that violate the schema — eliminating
/// hallucinated or misspelled action names at the source.
///
/// The grammar is written in GBNF (Grammar-Based Normal Form), which is the
/// format accepted by `llama_sampler_init_grammar`.  Each rule name maps
/// directly to a field in `JARVISIntent`.
///
/// Usage:
/// ```swift
/// let output = try await engine.generate(
///     prompt: fullPrompt,
///     grammar: IntentGrammar.grammar
/// )
/// ```
public enum IntentGrammar {

    /// GBNF grammar that constrains LLM output to valid JARVISIntent JSON.
    ///
    /// The top-level `root` rule produces exactly one JSON object with the
    /// five required fields in a fixed order so the grammar remains
    /// unambiguous and the sampler can evaluate it efficiently.
    ///
    /// Field ordering: action → target → parameters → confidence → humanReadable
    public static let grammar: String = #"""
    root         ::= "{" ws intent-body ws "}"

    intent-body  ::= action-field     "," ws
                     target-field     "," ws
                     params-field     "," ws
                     confidence-field "," ws
                     human-field

    # -----------------------------------------------------------------------
    # action – must be one of the known IntentAction raw values
    # -----------------------------------------------------------------------
    action-field ::= "\"action\""  ws ":" ws "\"" action-value "\""
    action-value ::= "turnOn"
                   | "turnOff"
                   | "setBrightness"
                   | "setTemperature"
                   | "lockDoor"
                   | "unlockDoor"
                   | "setThermostat"
                   | "setScene"
                   | "sendMessage"
                   | "makeCall"
                   | "createReminder"
                   | "createCalendarEvent"
                   | "createNote"
                   | "createTask"
                   | "runShortcut"
                   | "getDirections"
                   | "queryHealth"
                   | "remember"
                   | "recall"
                   | "unknown"
                   | "confirmYes"
                   | "confirmNo"

    # -----------------------------------------------------------------------
    # target – device / scene / shortcut name, or JSON null
    # -----------------------------------------------------------------------
    target-field  ::= "\"target\""  ws ":" ws ( null | "\"" target-chars "\"" )
    target-chars  ::= [^"\\]+

    # -----------------------------------------------------------------------
    # parameters – object whose values are always strings
    # -----------------------------------------------------------------------
    params-field   ::= "\"parameters\"" ws ":" ws "{" ws params-entries? ws "}"
    params-entries ::= param-entry ( "," ws param-entry )*
    param-entry    ::= "\"" param-key "\"" ws ":" ws "\"" param-value "\""
    param-key      ::= [a-zA-Z_] [a-zA-Z0-9_]*
    param-value    ::= [^"\\]*

    # -----------------------------------------------------------------------
    # confidence – decimal in [0.0, 1.0] with up to two decimal places
    # -----------------------------------------------------------------------
    confidence-field  ::= "\"confidence\""  ws ":" ws confidence-number
    confidence-number ::= "0" ( "." [0-9] [0-9]? )?
                        | "1" ( ".0" "0"? )?

    # -----------------------------------------------------------------------
    # humanReadable – short natural-language description
    # -----------------------------------------------------------------------
    human-field  ::= "\"humanReadable\"" ws ":" ws "\"" human-chars "\""
    human-chars  ::= [^"\\]+

    # -----------------------------------------------------------------------
    # Terminals
    # -----------------------------------------------------------------------
    null ::= "null"
    ws   ::= [ \t\n]*
    """#
}

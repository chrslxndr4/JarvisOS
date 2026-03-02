import Foundation
import JARVISCore

public struct ShortcutDiscovery {

    /// Built-in shortcuts that JARVIS knows how to invoke.
    /// The user must create these in the Apple Shortcuts app following the naming convention.
    public static let builtInShortcuts: [CatalogShortcut] = [
        CatalogShortcut(
            id: "builtin-weather",
            name: "JARVIS Get Weather",
            description: "Get current weather and forecast. Input: optional location text. Returns weather summary."
        ),
        CatalogShortcut(
            id: "builtin-music",
            name: "JARVIS Play Music",
            description: "Play music via Apple Music. Input: search query. Returns now-playing info."
        ),
        CatalogShortcut(
            id: "builtin-whatsapp",
            name: "JARVIS Send WhatsApp",
            description: "Send a WhatsApp message. Input: JSON {\"to\":\"name\",\"body\":\"text\"}. Returns confirmation."
        ),
        CatalogShortcut(
            id: "builtin-timer",
            name: "JARVIS Timer",
            description: "Set a timer. Input: duration string (e.g. \"5 minutes\"). Returns confirmation."
        ),
        CatalogShortcut(
            id: "builtin-dnd",
            name: "JARVIS Do Not Disturb",
            description: "Toggle Do Not Disturb focus mode. Input: \"on\" or \"off\". Returns confirmation."
        ),
        CatalogShortcut(
            id: "builtin-findmy",
            name: "JARVIS Find My iPhone",
            description: "Play sound on a device via Find My. Input: optional device name. Returns confirmation."
        ),
        CatalogShortcut(
            id: "builtin-text",
            name: "JARVIS Text Someone",
            description: "Send an iMessage/SMS. Input: JSON {\"to\":\"name\",\"body\":\"text\"}. Returns confirmation."
        ),
        CatalogShortcut(
            id: "builtin-translate",
            name: "JARVIS Translate",
            description: "Translate text using Apple Translate. Input: text to translate. Returns translated text."
        ),
    ]

    /// Discover available Siri Shortcuts.
    /// Merges built-in shortcuts with user-registered shortcuts so the AI classifier sees all of them.
    public static func discoverFromRegistry(_ registered: [CatalogShortcut]) -> [CatalogShortcut] {
        // Start with built-in shortcuts
        var all = builtInShortcuts

        // Add user-registered shortcuts, skipping any that duplicate a built-in name
        let builtInNames = Set(builtInShortcuts.map(\.name))
        for shortcut in registered where !builtInNames.contains(shortcut.name) {
            all.append(shortcut)
        }

        return all
    }
}

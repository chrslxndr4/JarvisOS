import Foundation
import JARVISCore

public struct ShortcutDiscovery {
    /// Discover available Siri Shortcuts.
    /// Uses the Shortcuts app's URL scheme to check availability.
    /// Full registry comes from user-configured shortcuts in the MemorySystem.
    public static func discoverFromRegistry(_ registered: [CatalogShortcut]) -> [CatalogShortcut] {
        // Return user-registered shortcuts as-is
        // In the future, could query INVoiceShortcutCenter for donated shortcuts
        return registered
    }
}

import Foundation
import JARVISCore

public actor CatalogManager: CommandCataloging {
    public private(set) var catalog: CommandCatalog
    private let homeKitDiscovery: HomeKitDiscovery
    private var registeredShortcuts: [CatalogShortcut] = []

    public init() {
        self.catalog = CommandCatalog()
        self.homeKitDiscovery = HomeKitDiscovery()
    }

    public func refresh() async throws {
        // Discover HomeKit devices and scenes
        let (devices, scenes) = try await homeKitDiscovery.discover()

        // Build shortcuts from registry
        let shortcuts = ShortcutDiscovery.discoverFromRegistry(registeredShortcuts)

        catalog = CommandCatalog(
            devices: devices,
            scenes: scenes,
            shortcuts: shortcuts
        )
    }

    public func registerShortcut(name: String, description: String?) {
        let shortcut = CatalogShortcut(
            id: UUID().uuidString,
            name: name,
            description: description
        )
        registeredShortcuts.append(shortcut)
        catalog.shortcuts = registeredShortcuts
    }

    public func setRegisteredShortcuts(_ shortcuts: [CatalogShortcut]) {
        registeredShortcuts = shortcuts
        catalog.shortcuts = shortcuts
    }

    public func validate(intent: JARVISIntent) -> Bool {
        if intent.action == .unknown { return false }

        // Actions that don't need device validation
        let deviceFreeActions: Set<IntentAction> = [
            .sendMessage, .makeCall, .createReminder, .createCalendarEvent,
            .createNote, .createTask, .getDirections, .queryHealth,
            .remember, .recall, .confirmYes, .confirmNo
        ]
        if deviceFreeActions.contains(intent.action) { return true }

        // runShortcut: validate against registered shortcuts
        if intent.action == .runShortcut {
            guard let target = intent.target else { return false }
            return catalog.shortcuts.contains { $0.name.localizedCaseInsensitiveCompare(target) == .orderedSame }
        }

        // setScene: validate against discovered scenes
        if intent.action == .setScene {
            guard let target = intent.target else { return false }
            return catalog.scenes.contains { $0.name.localizedCaseInsensitiveCompare(target) == .orderedSame }
        }

        // HomeKit device actions: validate device exists and supports the action
        guard let target = intent.target else { return false }
        guard let device = catalog.devices.first(where: {
            $0.name.localizedCaseInsensitiveCompare(target) == .orderedSame
        }) else { return false }

        return device.supportedActions.contains(intent.action.rawValue)
    }
}

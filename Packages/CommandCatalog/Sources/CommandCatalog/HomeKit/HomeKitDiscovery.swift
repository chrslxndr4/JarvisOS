import Foundation
import JARVISCore

#if canImport(HomeKit)
import HomeKit
#endif

public actor HomeKitDiscovery {
    #if canImport(HomeKit)
    private var homeManager: HMHomeManager?
    private var delegate: HomeManagerDelegate?
    #endif

    public init() {}

    public func discover() async throws -> (devices: [CatalogDevice], scenes: [CatalogScene]) {
        #if canImport(HomeKit)
        return try await discoverWithHomeKit()
        #else
        return ([], [])
        #endif
    }

    #if canImport(HomeKit)
    private func discoverWithHomeKit() async throws -> (devices: [CatalogDevice], scenes: [CatalogScene]) {
        let manager = HMHomeManager()
        let delegate = HomeManagerDelegate()
        self.homeManager = manager
        self.delegate = delegate
        manager.delegate = delegate

        // Wait for HomeKit to load homes
        try await delegate.waitForReady()

        var devices: [CatalogDevice] = []
        var scenes: [CatalogScene] = []

        for home in manager.homes {
            // Discover accessories
            for room in home.rooms {
                for accessory in room.accessories {
                    for service in accessory.services {
                        let catalogDevice = mapAccessoryToCatalog(
                            accessory: accessory,
                            service: service,
                            room: room
                        )
                        if let catalogDevice {
                            devices.append(catalogDevice)
                        }
                    }
                }
            }

            // Discover scenes (action sets)
            for actionSet in home.actionSets {
                scenes.append(CatalogScene(
                    id: actionSet.uniqueIdentifier.uuidString,
                    name: actionSet.name
                ))
            }
        }

        return (devices, scenes)
    }

    private func mapAccessoryToCatalog(accessory: HMAccessory, service: HMService, room: HMRoom) -> CatalogDevice? {
        let serviceType = service.serviceType

        // Map HMServiceType to supported actions
        var actions: [String] = []
        var deviceType = "unknown"

        switch serviceType {
        case HMServiceTypeLightbulb:
            deviceType = "light"
            actions = ["turnOn", "turnOff"]
            if service.characteristics.contains(where: { $0.characteristicType == HMCharacteristicTypeBrightness }) {
                actions.append("setBrightness")
            }
            if service.characteristics.contains(where: { $0.characteristicType == HMCharacteristicTypeHue }) {
                actions.append("setColor")
            }
        case HMServiceTypeSwitch, HMServiceTypeOutlet:
            deviceType = "switch"
            actions = ["turnOn", "turnOff"]
        case HMServiceTypeThermostat:
            deviceType = "thermostat"
            actions = ["setThermostat", "setTemperature"]
        case HMServiceTypeLockMechanism:
            deviceType = "lock"
            actions = ["lockDoor", "unlockDoor"]
        case HMServiceTypeGarageDoorOpener:
            deviceType = "garage"
            actions = ["turnOn", "turnOff"]
        case HMServiceTypeFan:
            deviceType = "fan"
            actions = ["turnOn", "turnOff"]
            if service.characteristics.contains(where: { $0.characteristicType == HMCharacteristicTypeRotationSpeed }) {
                actions.append("setBrightness") // reuse brightness for speed
            }
        case HMServiceTypeWindowCovering:
            deviceType = "blinds"
            actions = ["turnOn", "turnOff", "setBrightness"]
        default:
            return nil // Skip unsupported service types
        }

        guard !actions.isEmpty else { return nil }

        let name = accessory.name
        return CatalogDevice(
            id: accessory.uniqueIdentifier.uuidString,
            name: name,
            room: room.name,
            type: deviceType,
            supportedActions: actions
        )
    }
    #endif
}

#if canImport(HomeKit)
private final class HomeManagerDelegate: NSObject, HMHomeManagerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var isReady = false

    func waitForReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        isReady = true
        continuation?.resume()
        continuation = nil
    }
}
#endif

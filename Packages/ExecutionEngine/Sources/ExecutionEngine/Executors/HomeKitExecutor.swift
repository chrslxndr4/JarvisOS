import Foundation
import JARVISCore

#if canImport(HomeKit)
import HomeKit
#endif

public actor HomeKitExecutor {
    #if canImport(HomeKit)
    private var homeManager: HMHomeManager?
    #endif

    public init() {}

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        #if canImport(HomeKit)
        return try await executeWithHomeKit(intent: intent)
        #else
        return .failure(error: "HomeKit not available on this platform")
        #endif
    }

    #if canImport(HomeKit)
    private func executeWithHomeKit(intent: JARVISIntent) async throws -> ExecutionResult {
        guard let target = intent.target else {
            return .failure(error: "No target device specified")
        }

        let manager = HMHomeManager()
        self.homeManager = manager

        // Find the accessory by name
        var foundAccessory: HMAccessory?
        var foundService: HMService?

        for home in manager.homes {
            for room in home.rooms {
                for accessory in room.accessories {
                    if accessory.name.localizedCaseInsensitiveCompare(target) == .orderedSame {
                        foundAccessory = accessory
                        foundService = accessory.services.first { svc in
                            svc.serviceType != HMServiceTypeAccessoryInformation
                        }
                        break
                    }
                }
                if foundAccessory != nil { break }
            }
            if foundAccessory != nil { break }
        }

        guard let accessory = foundAccessory, let service = foundService else {
            return .failure(error: "Device '\(target)' not found")
        }

        switch intent.action {
        case .turnOn:
            return try await setPowerState(service: service, on: true, deviceName: target)
        case .turnOff:
            return try await setPowerState(service: service, on: false, deviceName: target)
        case .setBrightness:
            guard let value = intent.parameters["brightness"].flatMap(Int.init) else {
                return .failure(error: "Missing brightness value")
            }
            return try await setBrightness(service: service, value: value, deviceName: target)
        case .setTemperature, .setThermostat:
            guard let value = intent.parameters["temperature"].flatMap(Double.init) else {
                return .failure(error: "Missing temperature value")
            }
            return try await setTemperature(service: service, value: value, deviceName: target)
        case .lockDoor:
            return try await setLockState(service: service, locked: true, deviceName: target)
        case .unlockDoor:
            return try await setLockState(service: service, locked: false, deviceName: target)
        case .setScene:
            return try await activateScene(name: target, manager: manager)
        default:
            return .failure(error: "Unsupported HomeKit action: \(intent.action.rawValue)")
        }
    }

    private func setPowerState(service: HMService, on: Bool, deviceName: String) async throws -> ExecutionResult {
        guard let characteristic = service.characteristics.first(where: {
            $0.characteristicType == HMCharacteristicTypePowerState
        }) else {
            return .failure(error: "Device '\(deviceName)' doesn't support power control")
        }
        try await characteristic.writeValue(on)
        return .success(message: "\(deviceName) turned \(on ? "on" : "off")")
    }

    private func setBrightness(service: HMService, value: Int, deviceName: String) async throws -> ExecutionResult {
        guard let characteristic = service.characteristics.first(where: {
            $0.characteristicType == HMCharacteristicTypeBrightness
        }) else {
            return .failure(error: "Device '\(deviceName)' doesn't support brightness")
        }
        let clamped = min(max(value, 0), 100)
        try await characteristic.writeValue(clamped)
        return .success(message: "\(deviceName) brightness set to \(clamped)%")
    }

    private func setTemperature(service: HMService, value: Double, deviceName: String) async throws -> ExecutionResult {
        guard let characteristic = service.characteristics.first(where: {
            $0.characteristicType == HMCharacteristicTypeTargetTemperature
        }) else {
            return .failure(error: "Device '\(deviceName)' doesn't support temperature control")
        }
        try await characteristic.writeValue(value)
        return .success(message: "\(deviceName) temperature set to \(value)°C")
    }

    private func setLockState(service: HMService, locked: Bool, deviceName: String) async throws -> ExecutionResult {
        guard let characteristic = service.characteristics.first(where: {
            $0.characteristicType == HMCharacteristicTypeLockTargetState
        }) else {
            return .failure(error: "Device '\(deviceName)' doesn't support lock control")
        }
        let state = locked ? HMLockTargetState.secured.rawValue : HMLockTargetState.unsecured.rawValue
        try await characteristic.writeValue(state)
        return .success(message: "\(deviceName) \(locked ? "locked" : "unlocked")")
    }

    private func activateScene(name: String, manager: HMHomeManager) async throws -> ExecutionResult {
        for home in manager.homes {
            if let actionSet = home.actionSets.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                try await home.executeActionSet(actionSet)
                return .success(message: "Scene '\(name)' activated")
            }
        }
        return .failure(error: "Scene '\(name)' not found")
    }
    #endif
}

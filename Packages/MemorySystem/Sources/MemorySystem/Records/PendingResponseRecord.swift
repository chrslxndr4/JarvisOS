import Foundation
import GRDB
import JARVISCore

public struct PendingResponseRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pendingResponse"

    public var id: String
    public var commandId: String
    public var intentAction: String
    public var intentTarget: String?
    public var intentParameters: String? // JSON
    public var prompt: String
    public var createdAt: Date
    public var expiresAt: Date

    public init(
        id: String,
        commandId: String,
        intentAction: String,
        intentTarget: String?,
        intentParameters: String?,
        prompt: String,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.commandId = commandId
        self.intentAction = intentAction
        self.intentTarget = intentTarget
        self.intentParameters = intentParameters
        self.prompt = prompt
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public static func from(commandId: UUID, intent: JARVISIntent, prompt: String, ttl: TimeInterval = 120) -> PendingResponseRecord {
        let paramsJSON = try? String(data: JSONEncoder().encode(intent.parameters), encoding: .utf8)
        let now = Date()
        return PendingResponseRecord(
            id: UUID().uuidString,
            commandId: commandId.uuidString,
            intentAction: intent.action.rawValue,
            intentTarget: intent.target,
            intentParameters: paramsJSON,
            prompt: prompt,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl)
        )
    }
}

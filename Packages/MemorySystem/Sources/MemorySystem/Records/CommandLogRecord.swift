import Foundation
import GRDB
import JARVISCore

public struct CommandLogRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "commandLog"

    public var id: String
    public var rawText: String
    public var source: String
    public var intentAction: String?
    public var intentTarget: String?
    public var intentParameters: String? // JSON
    public var intentConfidence: Double?
    public var resultType: String?
    public var resultMessage: String?
    public var timestamp: Date

    public init(
        id: String,
        rawText: String,
        source: String,
        intentAction: String?,
        intentTarget: String?,
        intentParameters: String?,
        intentConfidence: Double?,
        resultType: String?,
        resultMessage: String?,
        timestamp: Date
    ) {
        self.id = id
        self.rawText = rawText
        self.source = source
        self.intentAction = intentAction
        self.intentTarget = intentTarget
        self.intentParameters = intentParameters
        self.intentConfidence = intentConfidence
        self.resultType = resultType
        self.resultMessage = resultMessage
        self.timestamp = timestamp
    }

    public static func from(command: JARVISCommand, intent: JARVISIntent?, result: ExecutionResult?) -> CommandLogRecord {
        let resultType: String?
        let resultMessage: String?

        switch result {
        case .success(let msg):
            resultType = "success"
            resultMessage = msg
        case .failure(let err):
            resultType = "failure"
            resultMessage = err
        case .confirmationRequired(let prompt, _):
            resultType = "confirmation"
            resultMessage = prompt
        case .ambiguous(let options):
            resultType = "ambiguous"
            resultMessage = options.joined(separator: ", ")
        case nil:
            resultType = nil
            resultMessage = nil
        }

        let paramsJSON: String?
        if let params = intent?.parameters, !params.isEmpty {
            paramsJSON = try? String(data: JSONEncoder().encode(params), encoding: .utf8)
        } else {
            paramsJSON = nil
        }

        return CommandLogRecord(
            id: command.id.uuidString,
            rawText: command.rawText,
            source: command.source.rawValue,
            intentAction: intent?.action.rawValue,
            intentTarget: intent?.target,
            intentParameters: paramsJSON,
            intentConfidence: intent?.confidence,
            resultType: resultType,
            resultMessage: resultMessage,
            timestamp: command.timestamp
        )
    }
}

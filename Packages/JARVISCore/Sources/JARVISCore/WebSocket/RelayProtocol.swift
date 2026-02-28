import Foundation

// Relay -> iOS
public enum RelayIncoming: Sendable {
    case text(RelayTextMessage)
    case audio(RelayAudioMessage)
    case image(RelayImageMessage)
    case status(RelayStatusMessage)
}

public struct RelayTextMessage: Sendable, Codable {
    public let id: String
    public let from: String
    public let pushName: String
    public let body: String
    public let timestamp: Double
}

public struct RelayAudioMessage: Sendable, Codable {
    public let id: String
    public let from: String
    public let pushName: String
    public let mimetype: String
    public let seconds: Int
    public let data: String // base64
    public let ptt: Bool
    public let timestamp: Double
}

public struct RelayImageMessage: Sendable, Codable {
    public let id: String
    public let from: String
    public let pushName: String
    public let mimetype: String
    public let caption: String?
    public let width: Int
    public let height: Int
    public let data: String // base64
    public let timestamp: Double
}

public struct RelayStatusMessage: Sendable, Codable {
    public let whatsapp: String
    public let uptime: Int
}

// iOS -> Relay
public struct RelayTextReply: Sendable, Codable {
    public var type: String = "reply.text"
    public let to: String
    public let body: String
    public let quotedId: String?

    public init(to: String, body: String, quotedId: String? = nil) {
        self.to = to
        self.body = body
        self.quotedId = quotedId
    }
}

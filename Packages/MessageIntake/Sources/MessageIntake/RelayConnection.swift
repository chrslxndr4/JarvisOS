import Foundation
import JARVISCore

/// WebSocket client connecting to the Mac relay.
/// Uses URLSessionWebSocketTask for native iOS WebSocket support.
public actor RelayConnection: MessageIntaking {
    private let url: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private var commandContinuation: AsyncStream<JARVISCommand>.Continuation?
    private var statusContinuation: AsyncStream<RelayStatusMessage>.Continuation?
    private var isListening = false
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

    // Callback for sending replies back through the WebSocket
    private var sendCallback: ((Data) -> Void)?

    public let incomingCommands: AsyncStream<JARVISCommand>
    public let statusUpdates: AsyncStream<RelayStatusMessage>

    public init(relayURL: URL) {
        self.url = relayURL

        var cmdCont: AsyncStream<JARVISCommand>.Continuation?
        self.incomingCommands = AsyncStream { cmdCont = $0 }
        self.commandContinuation = cmdCont

        var statusCont: AsyncStream<RelayStatusMessage>.Continuation?
        self.statusUpdates = AsyncStream { statusCont = $0 }
        self.statusContinuation = statusCont
    }

    // MARK: - MessageIntaking

    public func startListening() async throws {
        guard !isListening else { return }
        isListening = true
        reconnectDelay = 1.0
        connect()
    }

    public func stopListening() async {
        isListening = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        commandContinuation?.finish()
        statusContinuation?.finish()
    }

    // MARK: - Sending

    /// Send a text reply back through the WebSocket to the relay.
    public func sendReply(_ reply: RelayTextReply) async throws {
        let data = try JSONEncoder().encode(reply)
        try await sendRaw(data)
    }

    /// Send raw JSON data through the WebSocket.
    public func sendRaw(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw RelayConnectionError.notConnected
        }
        let message = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8)!)
        try await task.send(message)
    }

    /// Send a ping to keep the connection alive.
    public func sendPing() async {
        guard let task = webSocketTask else { return }
        let ping = #"{"type":"ping"}"#
        try? await task.send(.string(ping))
    }

    public var connected: Bool {
        webSocketTask?.state == .running
    }

    // MARK: - Private

    private func connect() {
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // Start receive loop
        Task { [weak self] in
            await self?.receiveLoop()
        }

        // Start ping timer
        Task { [weak self] in
            await self?.pingLoop()
        }
    }

    private func receiveLoop() async {
        while isListening {
            guard let task = webSocketTask else { break }

            do {
                let message = try await task.receive()
                reconnectDelay = 1.0 // Reset on successful receive

                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isListening {
                    await scheduleReconnect()
                }
                return
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        // Parse the "type" field to determine message kind
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        do {
            switch type {
            case "whatsapp.message.text":
                let msg = try JSONDecoder().decode(RelayTextMessage.self, from: data)
                let command = JARVISCommand(
                    rawText: msg.body,
                    source: .whatsappText,
                    timestamp: Date(timeIntervalSince1970: msg.timestamp)
                )
                commandContinuation?.yield(command)

            case "whatsapp.message.audio":
                let msg = try JSONDecoder().decode(RelayAudioMessage.self, from: data)
                let audioData = Data(base64Encoded: msg.data)
                let command = JARVISCommand(
                    rawText: "", // Will be filled by transcription
                    source: .whatsappVoice,
                    timestamp: Date(timeIntervalSince1970: msg.timestamp),
                    audioData: audioData
                )
                commandContinuation?.yield(command)

            case "relay.status":
                let msg = try JSONDecoder().decode(RelayStatusMessage.self, from: data)
                statusContinuation?.yield(msg)

            default:
                break // Ignore unknown types (images, pong, etc.)
            }
        } catch {
            // Log parse error but don't crash
        }
    }

    private func pingLoop() async {
        while isListening {
            try? await Task.sleep(for: .seconds(25))
            guard isListening else { break }
            await sendPing()
        }
    }

    private func scheduleReconnect() async {
        guard isListening else { return }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Exponential backoff
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)

        try? await Task.sleep(for: .seconds(delay))

        guard isListening else { return }
        connect()
    }
}

public enum RelayConnectionError: Error, LocalizedError {
    case notConnected
    case sendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to relay"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        }
    }
}

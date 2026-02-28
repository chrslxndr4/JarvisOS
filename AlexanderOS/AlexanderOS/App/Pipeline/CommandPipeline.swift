import Foundation
import JARVISCore
import MessageIntake
import AIRouter
import CommandCatalog
import ExecutionEngine
import MemorySystem
import ReplyHandler

/// The main orchestrator that connects all JARVIS modules.
/// Receives commands -> classifies intent -> validates -> executes -> replies.
actor CommandPipeline {
    private let intake: RelayConnection
    private let router: IntentClassifier
    private let catalog: CatalogManager
    private let executor: ExecutionRouter
    private let memory: MemoryStore
    private let reply: ResponseFormatter
    private let transcriber: WhisperTranscriber

    private var isRunning = false
    private var processingTask: Task<Void, Never>?

    // Observable state for UI
    private var onStateChange: (@Sendable (PipelineState) -> Void)?

    struct PipelineState: Sendable {
        var isProcessing: Bool = false
        var lastCommand: String?
        var lastResult: String?
        var relayConnected: Bool = false
        var whatsappConnected: Bool = false
    }

    init(
        relayURL: URL,
        memory: MemoryStore
    ) throws {
        self.intake = RelayConnection(relayURL: relayURL)
        self.router = IntentClassifier()
        self.catalog = CatalogManager()
        self.memory = memory
        self.reply = ResponseFormatter()
        self.transcriber = WhisperTranscriber()

        // Wire up executor with note storage callback
        self.executor = ExecutionRouter { [memory] content, tags in
            try await memory.storeNote(content: content, tags: tags)
        }

        // Wire up reply handler's send callback
        Task {
            await self.configureReplyTransport()
        }
    }

    func onStateUpdate(_ handler: @escaping @Sendable (PipelineState) -> Void) {
        self.onStateChange = handler
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        // 1. Warm up AI router (load LLM model)
        try await router.warmUp()

        // 2. Discover HomeKit devices + scenes
        try? await catalog.refresh()

        // 3. Load registered shortcuts from memory
        let shortcuts = try await memory.fetchShortcuts()
        let catalogShortcuts = shortcuts.map {
            CatalogShortcut(id: $0.id, name: $0.name, description: $0.description)
        }
        await catalog.setRegisteredShortcuts(catalogShortcuts)

        // 4. Start listening for relay messages
        try await intake.startListening()

        // 5. Start processing loop
        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.processCommandStream()
        }

        // 6. Monitor relay status
        Task { [weak self] in
            guard let self else { return }
            await self.monitorStatus()
        }
    }

    func stop() async {
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
        await intake.stopListening()
        await router.coolDown()
        transcriber.unload()
    }

    // MARK: - Command Processing

    private func processCommandStream() async {
        for await command in await intake.incomingCommands {
            guard isRunning else { break }

            var processedCommand = command

            // Transcribe audio if needed
            if command.source == .whatsappVoice, let audioData = command.audioData {
                do {
                    if !await transcriber.loaded {
                        let downloadManager = try ModelDownloadManager()
                        if let modelPath = await downloadManager.localPath(for: .whisperBaseEn) {
                            try await transcriber.loadModel(at: modelPath.path)
                        }
                    }
                    let transcript = try await transcriber.transcribe(
                        audioData: audioData,
                        mimeType: "audio/ogg; codecs=opus"
                    )
                    processedCommand = JARVISCommand(
                        id: command.id,
                        rawText: transcript,
                        source: command.source,
                        timestamp: command.timestamp,
                        audioData: command.audioData
                    )
                } catch {
                    let result = ExecutionResult.failure(error: "Transcription failed: \(error.localizedDescription)")
                    try? await replyAndLog(command: command, intent: nil, result: result)
                    continue
                }
            }

            // Skip empty commands
            guard !processedCommand.rawText.isEmpty else { continue }

            await notifyState(isProcessing: true, lastCommand: processedCommand.rawText)

            do {
                let result = try await processCommand(processedCommand)
                await notifyState(isProcessing: false, lastResult: formatResult(result))
            } catch {
                let result = ExecutionResult.failure(error: error.localizedDescription)
                try? await replyAndLog(command: processedCommand, intent: nil, result: result)
                await notifyState(isProcessing: false, lastResult: "Error: \(error.localizedDescription)")
            }
        }
    }

    func processCommand(_ command: JARVISCommand) async throws -> ExecutionResult {
        // 1. Get current catalog
        let currentCatalog = await catalog.catalog

        // 2. Route to intent via AI
        let intent = try await router.route(command: command, catalog: currentCatalog)

        // 3. Handle recall separately (needs memory access)
        if intent.action == .recall {
            let query = intent.parameters["query"] ?? intent.target ?? command.rawText
            let results = try await memory.search(query: query)
            let result: ExecutionResult
            if results.isEmpty {
                result = .success(message: "I don't have any notes about that.")
            } else {
                result = .success(message: results.prefix(3).joined(separator: "\n"))
            }
            try? await replyAndLog(command: command, intent: intent, result: result)
            return result
        }

        // 4. Validate intent against catalog
        let isValid = await catalog.validate(intent: intent)
        if !isValid && intent.action != .unknown {
            let result = ExecutionResult.failure(
                error: "'\(intent.target ?? "unknown")' not found in available devices/shortcuts"
            )
            try? await replyAndLog(command: command, intent: intent, result: result)
            return result
        }

        // 5. Execute (includes confirmation check)
        let result = try await executor.execute(intent: intent)

        // 6. Log and reply
        try? await replyAndLog(command: command, intent: intent, result: result)

        return result
    }

    // MARK: - Helpers

    private func replyAndLog(command: JARVISCommand, intent: JARVISIntent?, result: ExecutionResult) async throws {
        // Send reply via WebSocket
        try await reply.send(response: result, for: command)

        // Store in command log
        try await memory.storeCommandLog(command: command, intent: intent, result: result)
    }

    private func monitorStatus() async {
        for await status in await intake.statusUpdates {
            let waConnected = status.whatsapp == "connected"
            onStateChange?(PipelineState(
                relayConnected: await intake.connected,
                whatsappConnected: waConnected
            ))
        }
    }

    private func configureReplyTransport() async {
        await reply.configure { [weak self] jid, body, quotedId in
            guard let self else { return }
            let reply = RelayTextReply(to: jid, body: body, quotedId: quotedId)
            let data = try JSONEncoder().encode(reply)
            try await self.intake.sendRaw(data)
        }
    }

    private func notifyState(isProcessing: Bool = false, lastCommand: String? = nil, lastResult: String? = nil) {
        var state = PipelineState()
        state.isProcessing = isProcessing
        state.lastCommand = lastCommand
        state.lastResult = lastResult
        onStateChange?(state)
    }

    private func formatResult(_ result: ExecutionResult) -> String {
        switch result {
        case .success(let msg): return msg
        case .failure(let err): return "Error: \(err)"
        case .confirmationRequired(let prompt, _): return prompt
        case .ambiguous(let options): return "Multiple: \(options.joined(separator: ", "))"
        }
    }
}

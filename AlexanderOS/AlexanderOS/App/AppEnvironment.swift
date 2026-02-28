import SwiftUI
import Combine
import JARVISCore
import MemorySystem

@MainActor
final class AppEnvironment: ObservableObject {
    // Connection state
    @Published var relayConnected = false
    @Published var whatsappConnected = false

    // Pipeline state
    @Published var isProcessing = false
    @Published var lastCommand: String?
    @Published var lastResult: String?
    @Published var modelStatus: ModelStatus = .notDownloaded

    // Settings
    @Published var relayURL: String {
        didSet { AppConfig.setRelayURL(relayURL) }
    }
    @Published var registeredShortcuts: [String] = []

    // Internal
    private var pipeline: CommandPipeline?
    private var memory: MemoryStore?
    private var downloadManager: ModelDownloadManager?

    enum ModelStatus: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case error(String)
    }

    init() {
        self.relayURL = UserDefaults.standard.string(forKey: AppConfig.relayURLKey) ?? AppConfig.defaultRelayURL

        Task {
            await setup()
        }
    }

    // MARK: - Setup

    private func setup() async {
        // Initialize memory store
        do {
            let store = try MemoryStore()
            self.memory = store

            // Load registered shortcuts
            let shortcuts = try await store.fetchShortcuts()
            self.registeredShortcuts = shortcuts.map(\.name)
        } catch {
            // Database init failed - non-fatal, UI still works
        }

        // Check model status
        do {
            let mgr = try ModelDownloadManager()
            self.downloadManager = mgr
            if await mgr.allModelsReady() {
                modelStatus = .ready
            }
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Pipeline

    func startPipeline() async {
        guard let memory else { return }
        guard let url = URL(string: relayURL) else { return }

        do {
            let pipe = try CommandPipeline(relayURL: url, memory: memory)
            self.pipeline = pipe

            await pipe.onStateUpdate { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isProcessing = state.isProcessing
                    if let cmd = state.lastCommand { self.lastCommand = cmd }
                    if let res = state.lastResult { self.lastResult = res }
                    self.relayConnected = state.relayConnected
                    self.whatsappConnected = state.whatsappConnected
                }
            }

            try await pipe.start()
        } catch {
            lastResult = "Pipeline error: \(error.localizedDescription)"
        }
    }

    func stopPipeline() async {
        await pipeline?.stop()
        pipeline = nil
    }

    // MARK: - Model Management

    func downloadModels() async {
        guard let mgr = downloadManager else { return }
        modelStatus = .downloading(progress: 0)

        let stream = await mgr.downloadAllModels()
        for await progress in stream {
            switch progress.state {
            case .downloading(let p):
                modelStatus = .downloading(progress: p)
            case .completed:
                // Check if all done
                if await mgr.allModelsReady() {
                    modelStatus = .ready
                }
            case .failed(let err):
                modelStatus = .error(err)
                return
            case .notStarted:
                break
            }
        }

        if await mgr.allModelsReady() {
            modelStatus = .ready
        }
    }

    func deleteModels() async {
        guard let mgr = downloadManager else { return }
        for model in ModelInfo.allRequired {
            try? await mgr.deleteModel(model)
        }
        modelStatus = .notDownloaded
    }

    // MARK: - Shortcuts

    func saveShortcut(name: String, description: String) async {
        try? await memory?.storeShortcut(name: name, description: description.isEmpty ? nil : description)
    }

    // MARK: - Commands

    func fetchRecentCommands() async throws -> [CommandLogRecord] {
        guard let memory else { return [] }
        return try await memory.fetchRecentCommands()
    }

    // MARK: - Connection

    func reconnect() async {
        await stopPipeline()
        await startPipeline()
    }

    func refreshStatus() async {
        // Re-check model status
        if let mgr = downloadManager, await mgr.allModelsReady() {
            modelStatus = .ready
        }
    }
}

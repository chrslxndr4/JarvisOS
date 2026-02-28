import Foundation

public enum ModelDownloadState: Sendable {
    case notStarted
    case downloading(progress: Double) // 0.0 to 1.0
    case completed(localPath: URL)
    case failed(error: String)
}

public struct ModelDownloadProgress: Sendable {
    public let modelId: String
    public let state: ModelDownloadState
}

/// Manages downloading and storing AI models in Application Support.
/// Models are excluded from iCloud backup.
public actor ModelDownloadManager {
    private let modelsDirectory: URL
    private var activeTasks: [String: URLSessionDownloadTask] = [:]

    public init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.modelsDirectory = appSupport
            .appendingPathComponent("AlexanderOS", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)

        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )

        // Exclude from iCloud backup
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = modelsDirectory
        try mutableDir.setResourceValues(resourceValues)
    }

    /// Returns the local path for a model if it's already downloaded.
    public func localPath(for model: ModelInfo) -> URL? {
        let path = modelsDirectory.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Check if all required models are downloaded.
    public func allModelsReady() -> Bool {
        ModelInfo.allRequired.allSatisfy { localPath(for: $0) != nil }
    }

    /// Returns the state of each required model.
    public func modelStates() -> [String: ModelDownloadState] {
        var states: [String: ModelDownloadState] = [:]
        for model in ModelInfo.allRequired {
            if let path = localPath(for: model) {
                states[model.id] = .completed(localPath: path)
            } else if activeTasks[model.id] != nil {
                states[model.id] = .downloading(progress: 0)
            } else {
                states[model.id] = .notStarted
            }
        }
        return states
    }

    /// Download all required models, yielding progress updates.
    public func downloadAllModels() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            Task {
                for model in ModelInfo.allRequired {
                    if localPath(for: model) != nil {
                        continuation.yield(ModelDownloadProgress(
                            modelId: model.id,
                            state: .completed(localPath: modelsDirectory.appendingPathComponent(model.filename))
                        ))
                        continue
                    }

                    do {
                        let stream = downloadModel(model)
                        for await progress in stream {
                            continuation.yield(progress)
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Download a single model with progress reporting.
    public func downloadModel(_ model: ModelInfo) -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            let destination = modelsDirectory.appendingPathComponent(model.filename)

            // Already exists
            if FileManager.default.fileExists(atPath: destination.path) {
                continuation.yield(ModelDownloadProgress(
                    modelId: model.id,
                    state: .completed(localPath: destination)
                ))
                continuation.finish()
                return
            }

            let delegate = DownloadDelegate(
                modelId: model.id,
                destination: destination,
                expectedSize: model.expectedSizeBytes,
                continuation: continuation
            )

            let session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )

            // Check for partial download to resume
            let partialPath = destination.appendingPathExtension("partial")
            var request = URLRequest(url: model.remoteURL)

            if FileManager.default.fileExists(atPath: partialPath.path),
               let fileSize = try? FileManager.default.attributesOfItem(atPath: partialPath.path)[.size] as? Int64 {
                request.setValue("bytes=\(fileSize)-", forHTTPHeaderField: "Range")
                delegate.resumeOffset = fileSize
            }

            let task = session.downloadTask(with: request)
            delegate.task = task
            task.resume()

            continuation.yield(ModelDownloadProgress(
                modelId: model.id,
                state: .downloading(progress: 0)
            ))
        }
    }

    /// Delete a downloaded model.
    public func deleteModel(_ model: ModelInfo) throws {
        let path = modelsDirectory.appendingPathComponent(model.filename)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    /// Cancel an in-progress download.
    public func cancelDownload(_ modelId: String) {
        activeTasks[modelId]?.cancel()
        activeTasks.removeValue(forKey: modelId)
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let modelId: String
    let destination: URL
    let expectedSize: Int64
    let continuation: AsyncStream<ModelDownloadProgress>.Continuation
    nonisolated(unsafe) var resumeOffset: Int64 = 0
    nonisolated(unsafe) var task: URLSessionDownloadTask?

    init(
        modelId: String,
        destination: URL,
        expectedSize: Int64,
        continuation: AsyncStream<ModelDownloadProgress>.Continuation
    ) {
        self.modelId = modelId
        self.destination = destination
        self.expectedSize = expectedSize
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            // Remove existing file if any
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)

            // Exclude from backup
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDest = destination
            try mutableDest.setResourceValues(resourceValues)

            continuation.yield(ModelDownloadProgress(
                modelId: modelId,
                state: .completed(localPath: destination)
            ))
        } catch {
            continuation.yield(ModelDownloadProgress(
                modelId: modelId,
                state: .failed(error: "Failed to save: \(error.localizedDescription)")
            ))
        }
        continuation.finish()
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : expectedSize
        let written = totalBytesWritten + resumeOffset
        let progress = total > 0 ? Double(written) / Double(total + resumeOffset) : 0

        continuation.yield(ModelDownloadProgress(
            modelId: modelId,
            state: .downloading(progress: min(progress, 1.0))
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            continuation.yield(ModelDownloadProgress(
                modelId: modelId,
                state: .failed(error: error.localizedDescription)
            ))
            continuation.finish()
        }
        session.invalidateAndCancel()
    }
}

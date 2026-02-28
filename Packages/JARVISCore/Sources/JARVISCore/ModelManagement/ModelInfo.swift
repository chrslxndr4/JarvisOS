import Foundation

public struct ModelInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let remoteURL: URL
    public let filename: String
    public let expectedSizeBytes: Int64 // approximate, for progress display

    public init(id: String, displayName: String, remoteURL: URL, filename: String, expectedSizeBytes: Int64) {
        self.id = id
        self.displayName = displayName
        self.remoteURL = remoteURL
        self.filename = filename
        self.expectedSizeBytes = expectedSizeBytes
    }
}

public extension ModelInfo {
    static let qwen2_5_1_5B = ModelInfo(
        id: "qwen2.5-1.5b-instruct",
        displayName: "Qwen 2.5 1.5B Instruct (Q4_K_M)",
        remoteURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
        filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        expectedSizeBytes: 1_060_000_000 // ~1 GB
    )

    static let whisperBaseEn = ModelInfo(
        id: "whisper-base-en",
        displayName: "Whisper Base English",
        remoteURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
        filename: "ggml-base.en.bin",
        expectedSizeBytes: 148_000_000 // ~148 MB
    )

    static let allRequired: [ModelInfo] = [qwen2_5_1_5B, whisperBaseEn]
}

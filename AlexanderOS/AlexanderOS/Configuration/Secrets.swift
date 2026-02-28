import Foundation

enum AppConfig {
    static let defaultRelayURL = "ws://192.168.1.100:8080"
    static let relayURLKey = "relay_url"

    static var relayURL: URL {
        let stored = UserDefaults.standard.string(forKey: relayURLKey) ?? defaultRelayURL
        return URL(string: stored)!
    }

    static func setRelayURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: relayURLKey)
    }

    // Model URLs
    static let qwenModelURL = URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
    static let whisperModelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!

    // Model file names
    static let qwenModelFilename = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    static let whisperModelFilename = "ggml-base.en.bin"
}

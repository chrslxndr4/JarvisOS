import Foundation
import JARVISCore

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

public enum WhisperError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case audioConversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not loaded"
        case .modelLoadFailed(let msg): return "Whisper model load failed: \(msg)"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .audioConversionFailed(let msg): return "Audio conversion failed: \(msg)"
        }
    }
}

/// Actor wrapping whisper.cpp for on-device speech-to-text.
/// Designed to be loaded on demand (not kept resident like the LLM).
public actor WhisperTranscriber {
    private var isLoaded = false

    #if WHISPER_CPP_AVAILABLE
    private var whisperContext: OpaquePointer?
    #endif

    public init() {}

    /// Load the whisper model from disk.
    public func loadModel(at path: String) throws {
        #if WHISPER_CPP_AVAILABLE
        var params = whisper_context_default_params()
        params.use_gpu = true

        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            throw WhisperError.modelLoadFailed("Failed to load whisper model at \(path)")
        }
        self.whisperContext = ctx
        #endif

        self.isLoaded = true
    }

    /// Transcribe raw PCM audio data (16kHz, mono, Float32).
    public func transcribe(audioSamples: [Float]) throws -> String {
        guard isLoaded else { throw WhisperError.modelNotLoaded }

        #if WHISPER_CPP_AVAILABLE
        return try transcribeWithWhisper(samples: audioSamples)
        #else
        return mockTranscribe(sampleCount: audioSamples.count)
        #endif
    }

    /// Transcribe from raw audio data (e.g., ogg/opus from WhatsApp voice notes).
    /// Converts to PCM 16kHz mono first.
    public func transcribe(audioData: Data, mimeType: String) throws -> String {
        let samples = try convertToPCM(data: audioData, mimeType: mimeType)
        return try transcribe(audioSamples: samples)
    }

    /// Unload model and free resources.
    public func unload() {
        #if WHISPER_CPP_AVAILABLE
        if let ctx = whisperContext {
            whisper_free(ctx)
            self.whisperContext = nil
        }
        #endif
        self.isLoaded = false
    }

    public var loaded: Bool { isLoaded }

    // MARK: - Whisper C API

    #if WHISPER_CPP_AVAILABLE
    private func transcribeWithWhisper(samples: [Float]) throws -> String {
        guard let ctx = whisperContext else { throw WhisperError.modelNotLoaded }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.single_segment = true
        params.no_context = true
        params.language = "en".withCString { strdup($0) }
        params.n_threads = Int32(min(ProcessInfo.processInfo.activeProcessorCount, 4))

        let result = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }

        guard result == 0 else {
            throw WhisperError.transcriptionFailed("whisper_full returned \(result)")
        }

        let nSegments = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<nSegments {
            if let segmentText = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segmentText)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    // MARK: - Audio Conversion

    private func convertToPCM(data: Data, mimeType: String) throws -> [Float] {
        #if canImport(AVFoundation)
        return try convertWithAVFoundation(data: data, mimeType: mimeType)
        #else
        throw WhisperError.audioConversionFailed("AVFoundation not available")
        #endif
    }

    #if canImport(AVFoundation)
    private func convertWithAVFoundation(data: Data, mimeType: String) throws -> [Float] {
        // Write data to temp file for AVAudioFile
        let tempDir = FileManager.default.temporaryDirectory
        let ext: String
        if mimeType.contains("ogg") { ext = "ogg" }
        else if mimeType.contains("mp4") || mimeType.contains("m4a") { ext = "m4a" }
        else { ext = "wav" }

        let tempURL = tempDir.appendingPathComponent("whisper_input_\(UUID().uuidString).\(ext)")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let audioFile = try AVAudioFile(forReading: tempURL)
        let sourceFormat = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)

        // Target: 16kHz mono Float32 (whisper.cpp requirement)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperError.audioConversionFailed("Cannot create target audio format")
        }

        // Read source audio
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw WhisperError.audioConversionFailed("Cannot create source buffer")
        }
        try audioFile.read(into: sourceBuffer)

        // Convert to 16kHz mono
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw WhisperError.audioConversionFailed("Cannot create audio converter")
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let targetFrameCount = UInt32(Double(frameCount) * ratio)
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            throw WhisperError.audioConversionFailed("Cannot create target buffer")
        }

        var conversionError: NSError?
        converter.convert(to: targetBuffer, error: &conversionError) { _, status in
            status.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw WhisperError.audioConversionFailed(conversionError.localizedDescription)
        }

        guard let channelData = targetBuffer.floatChannelData?[0] else {
            throw WhisperError.audioConversionFailed("No channel data in converted buffer")
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(targetBuffer.frameLength)))
    }
    #endif

    // MARK: - Mock

    private func mockTranscribe(sampleCount: Int) -> String {
        let duration = Float(sampleCount) / 16000.0
        return "[Mock transcription of \(String(format: "%.1f", duration))s audio]"
    }
}

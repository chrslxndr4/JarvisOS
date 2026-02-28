import Foundation

/// Utility for audio data processing before transcription.
public struct AudioProcessor {
    /// Decode base64-encoded audio data from the relay.
    public static func decodeBase64Audio(_ base64String: String) -> Data? {
        Data(base64Encoded: base64String)
    }

    /// Check if audio data is likely OGG/Opus (WhatsApp voice note format).
    public static func isOggOpus(data: Data) -> Bool {
        // OGG files start with "OggS" magic bytes
        guard data.count >= 4 else { return false }
        let magic = data.prefix(4)
        return magic == Data([0x4F, 0x67, 0x67, 0x53]) // "OggS"
    }

    /// Determine mime type from audio data if not provided.
    public static func detectMimeType(data: Data) -> String {
        if isOggOpus(data: data) {
            return "audio/ogg; codecs=opus"
        }
        // Check for WAV
        if data.count >= 4 && data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]) {
            return "audio/wav"
        }
        // Check for MP4/M4A
        if data.count >= 8 {
            let ftypRange = data[4..<8]
            if ftypRange == Data([0x66, 0x74, 0x79, 0x70]) { // "ftyp"
                return "audio/mp4"
            }
        }
        return "audio/unknown"
    }
}

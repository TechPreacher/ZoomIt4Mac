import Foundation

public enum RecordingCodec: String, Codable, Equatable, Sendable {
    case hevc
    case h264
}

extension RecordingCodec {
    /// Average bitrate for screen-content encoding. Screen content (flat
    /// regions, static areas, sharp edges) compresses far better than camera
    /// video, so these bits-per-pixel targets stay visually lossless while
    /// roughly halving VideoToolbox's dimension-scaled default.
    public func averageBitRate(width: Int, height: Int, frameRate: Int) -> Int {
        let bitsPerPixel: Double
        switch self {
        case .h264: bitsPerPixel = 0.07
        case .hevc: bitsPerPixel = 0.04
        }
        let raw = Double(width) * Double(height) * Double(frameRate) * bitsPerPixel
        return max(1_000_000, Int(raw.rounded()))
    }
}

public struct RecordingConfiguration: Codable, Equatable, Sendable {
    public var recordMicrophone: Bool
    public var recordSystemAudio: Bool
    public var codec: RecordingCodec

    enum CodingKeys: String, CodingKey {
        case recordMicrophone
        case recordSystemAudio
        case codec
    }

    public static let `default` = RecordingConfiguration(
        recordMicrophone: true,
        recordSystemAudio: false
    )

    public init(
        recordMicrophone: Bool,
        recordSystemAudio: Bool,
        codec: RecordingCodec = .hevc
    ) {
        self.recordMicrophone = recordMicrophone
        self.recordSystemAudio = recordSystemAudio
        self.codec = codec
    }

    // Migration: JSON persisted before the codec field existed has no codec key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordMicrophone = try container.decode(Bool.self, forKey: .recordMicrophone)
        recordSystemAudio = try container.decode(Bool.self, forKey: .recordSystemAudio)
        codec = try container.decodeIfPresent(RecordingCodec.self, forKey: .codec) ?? .hevc
    }
}

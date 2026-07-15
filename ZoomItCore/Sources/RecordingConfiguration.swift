import Foundation

public struct RecordingConfiguration: Codable, Equatable, Sendable {
    public var recordMicrophone: Bool
    public var recordSystemAudio: Bool

    public static let `default` = RecordingConfiguration(
        recordMicrophone: true,
        recordSystemAudio: false
    )
}

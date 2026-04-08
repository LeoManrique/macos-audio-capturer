import CoreAudio
import Foundation

final class ProcessTap: @unchecked Sendable {
    let tapID: AudioObjectID
    let tapUUID: UUID
    let format: AudioStreamBasicDescription

    init(bundleID: String) throws {
        let uuid = UUID()
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [])
        tapDescription.bundleIDs = [bundleID]
        tapDescription.uuid = uuid
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        tapDescription.name = "AudioCapturer-\(bundleID)"

        var outTapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &outTapID)
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "Failed to create process tap for \(bundleID)")
        }

        self.tapID = outTapID
        self.tapUUID = uuid
        self.format = try readTapFormat(tapID: outTapID)
    }

    func destroy() {
        AudioHardwareDestroyProcessTap(tapID)
    }

    deinit {
        destroy()
    }
}

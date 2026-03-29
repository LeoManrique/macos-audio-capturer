import CoreAudio
import Foundation

final class AggregateDevice: @unchecked Sendable {
    let deviceID: AudioObjectID

    init(tapUUID: UUID) throws {
        let outputDeviceID = try getDefaultOutputDeviceID()
        let outputUID = try getDeviceUID(deviceID: outputDeviceID)

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioCapturer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                ]
            ],
        ]

        var outDeviceID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &outDeviceID)
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "Failed to create aggregate device")
        }

        self.deviceID = outDeviceID
    }

    func destroy() {
        AudioHardwareDestroyAggregateDevice(deviceID)
    }

    deinit {
        destroy()
    }
}

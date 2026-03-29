import CoreAudio
import Foundation

enum CoreAudioError: LocalizedError {
    case osStatus(OSStatus, String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .osStatus(let code, let context):
            return "\(context) (OSStatus \(code))"
        case .notFound(let what):
            return "\(what) not found"
        }
    }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func readProperty<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<T>.alignment
        )
        defer { value.deallocate() }

        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &size, value)
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "Failed to read property \(selector)")
        }
        return value.load(as: T.self)
    }

    func readPropertyString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?

        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let cfString = value?.takeUnretainedValue() else {
            throw CoreAudioError.osStatus(status, "Failed to read string property \(selector)")
        }
        return cfString as String
    }
}

func getDefaultOutputDeviceID() throws -> AudioObjectID {
    try AudioObjectID.system.readProperty(kAudioHardwarePropertyDefaultSystemOutputDevice)
}

func getDeviceUID(deviceID: AudioObjectID) throws -> String {
    try deviceID.readPropertyString(kAudioDevicePropertyDeviceUID)
}

func readTapFormat(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(tapID, &address, 0, nil, &size)
    guard status == noErr, size > 0 else {
        throw CoreAudioError.osStatus(status, "Failed to get tap format size")
    }
    var format = AudioStreamBasicDescription()
    status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
    guard status == noErr else {
        throw CoreAudioError.osStatus(status, "Failed to read tap format")
    }
    return format
}

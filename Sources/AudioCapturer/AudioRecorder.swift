import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

enum AudioFormat: String, CaseIterable {
    case wav
    case m4a
}

final class AudioRecorder: @unchecked Sendable {
    private let aggregateDevice: AggregateDevice
    private let extAudioFile: ExtAudioFileRef
    private let avFormat: AVAudioFormat
    private var ioProcID: AudioDeviceIOProcID?
    private var ioQueue: DispatchQueue?

    init(
        aggregateDevice: AggregateDevice,
        tapFormat: AudioStreamBasicDescription,
        outputURL: URL,
        format: AudioFormat
    ) throws {
        self.aggregateDevice = aggregateDevice

        var streamDesc = tapFormat
        guard let avFormat = AVAudioFormat(streamDescription: &streamDesc) else {
            throw CoreAudioError.notFound("Could not create AVAudioFormat from tap format")
        }
        self.avFormat = avFormat

        let fileType: AudioFileTypeID
        var outputDesc: AudioStreamBasicDescription

        switch format {
        case .wav:
            fileType = kAudioFileWAVEType
            outputDesc = tapFormat
        case .m4a:
            fileType = kAudioFileM4AType
            outputDesc = AudioStreamBasicDescription(
                mSampleRate: tapFormat.mSampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: tapFormat.mChannelsPerFrame,
                mBitsPerChannel: 0,
                mReserved: 0
            )
        }

        var extFile: ExtAudioFileRef?
        let createStatus = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            fileType,
            &outputDesc,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &extFile
        )
        guard createStatus == noErr, let extFile else {
            throw CoreAudioError.osStatus(createStatus, "Failed to create audio file")
        }

        // Set the client (input) format to match the tap format
        var clientDesc = tapFormat
        let setStatus = ExtAudioFileSetProperty(
            extFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientDesc
        )
        guard setStatus == noErr else {
            throw CoreAudioError.osStatus(setStatus, "Failed to set client format")
        }

        self.extAudioFile = extFile
    }

    func start() throws {
        let extFile = extAudioFile
        let format = avFormat
        let deviceID = aggregateDevice.deviceID
        let queue = DispatchQueue(label: "com.audiocapturer.io", qos: .userInitiated)
        self.ioQueue = queue

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            deviceID,
            queue
        ) { _, inInputData, _, _, _ in
            let frameCount = inInputData.pointee.mBuffers.mDataByteSize
                / UInt32(MemoryLayout<Float32>.size * Int(format.channelCount))
            if frameCount == 0 { return }
            let bufferList = UnsafeMutablePointer(mutating: inInputData)
            ExtAudioFileWrite(extFile, frameCount, bufferList)
        }
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "Failed to create IOProc")
        }
        self.ioProcID = procID

        let startStatus = AudioDeviceStart(deviceID, procID)
        guard startStatus == noErr else {
            throw CoreAudioError.osStatus(startStatus, "Failed to start audio device")
        }
    }

    func stop() {
        let deviceID = aggregateDevice.deviceID
        if let procID = ioProcID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            ioProcID = nil
        }
        ExtAudioFileDispose(extAudioFile)
    }
}

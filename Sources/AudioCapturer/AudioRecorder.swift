import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import os

enum AudioFormat: String, CaseIterable {
    case wav
    case m4a
}

/// Thread-safe holder for the current ExtAudioFileRef, swappable during chunk rotation.
private final class FileHolder: @unchecked Sendable {
    private var file: ExtAudioFileRef?
    private let lock = OSAllocatedUnfairLock()

    init(_ file: ExtAudioFileRef?) { self.file = file }

    func write(_ frameCount: UInt32, _ bufferList: UnsafeMutablePointer<AudioBufferList>) {
        lock.lock()
        defer { lock.unlock() }
        if let file { ExtAudioFileWrite(file, frameCount, bufferList) }
    }

    func swap(new: ExtAudioFileRef?) -> ExtAudioFileRef? {
        lock.lock()
        defer { lock.unlock() }
        let old = file
        file = new
        return old
    }

    func dispose() {
        lock.lock()
        defer { lock.unlock() }
        if let file { ExtAudioFileDispose(file) }
        file = nil
    }
}

final class AudioRecorder: @unchecked Sendable {
    private let aggregateDevice: AggregateDevice
    private let tapFormat: AudioStreamBasicDescription
    private let avFormat: AVAudioFormat
    private let fileHolder: FileHolder
    private let silenceDetector: SilenceDetector
    private var ioProcID: AudioDeviceIOProcID?
    private var ioQueue: DispatchQueue?

    init(
        aggregateDevice: AggregateDevice,
        tapFormat: AudioStreamBasicDescription,
        outputURL: URL,
        format: AudioFormat,
        silenceDetector: SilenceDetector
    ) throws {
        self.aggregateDevice = aggregateDevice
        self.tapFormat = tapFormat
        self.silenceDetector = silenceDetector

        var streamDesc = tapFormat
        guard let avFormat = AVAudioFormat(streamDescription: &streamDesc) else {
            throw CoreAudioError.notFound("Could not create AVAudioFormat from tap format")
        }
        self.avFormat = avFormat

        let extFile = try Self.createExtAudioFile(
            outputURL: outputURL, format: format, tapFormat: tapFormat)
        self.fileHolder = FileHolder(extFile)
    }

    func start() throws {
        let holder = fileHolder
        let format = avFormat
        let detector = silenceDetector
        let deviceID = aggregateDevice.deviceID
        let queue = DispatchQueue(label: "com.audiocapturer.io", qos: .userInitiated)
        self.ioQueue = queue

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            deviceID,
            queue
        ) { _, inInputData, _, _, _ in
            let frameCount =
                inInputData.pointee.mBuffers.mDataByteSize
                / UInt32(MemoryLayout<Float32>.size * Int(format.channelCount))
            if frameCount == 0 { return }

            detector.feedAudio(inInputData, frameCount: frameCount)

            let bufferList = UnsafeMutablePointer(mutating: inInputData)
            holder.write(frameCount, bufferList)
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

    /// Swap to a new output file. The old file is finalized before returning.
    func rotateFile(newURL: URL, format: AudioFormat) throws {
        let newFile = try Self.createExtAudioFile(
            outputURL: newURL, format: format, tapFormat: tapFormat)

        let oldFile = fileHolder.swap(new: newFile)
        if let oldFile { ExtAudioFileDispose(oldFile) }
    }

    func stop() {
        let deviceID = aggregateDevice.deviceID
        if let procID = ioProcID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            ioProcID = nil
        }
        fileHolder.dispose()
    }

    // MARK: - Private

    private static func createExtAudioFile(
        outputURL: URL, format: AudioFormat, tapFormat: AudioStreamBasicDescription
    ) throws -> ExtAudioFileRef {
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

        return extFile
    }
}

import CoreAudio
import Foundation
import Synchronization

final class SilenceDetector: @unchecked Sendable {
    private let threshold: Float
    private let state: Mutex<State>
    private let timebaseNumer: Double
    private let timebaseDenom: Double

    private struct State {
        var silenceStartTicks: UInt64?
        var lastRMS: Float = 0
    }

    init(threshold: Float) {
        self.threshold = threshold
        self.state = Mutex(State())

        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.timebaseNumer = Double(info.numer)
        self.timebaseDenom = Double(info.denom)
    }

    /// Called from the IOProc callback — must be fast.
    func feedAudio(_ bufferList: UnsafePointer<AudioBufferList>, frameCount: UInt32) {
        let buffer = bufferList.pointee.mBuffers
        guard let data = buffer.mData?.assumingMemoryBound(to: Float32.self) else { return }

        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
        guard totalSamples > 0 else { return }

        var sumOfSquares: Float = 0
        for i in 0..<totalSamples {
            let sample = data[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrtf(sumOfSquares / Float(totalSamples))

        let now = mach_absolute_time()
        state.withLock { s in
            s.lastRMS = rms
            if rms < threshold {
                if s.silenceStartTicks == nil {
                    s.silenceStartTicks = now
                }
            } else {
                s.silenceStartTicks = nil
            }
        }
    }

    /// Returns true if silence has lasted at least `durationMs` milliseconds.
    func isSilent(forMs durationMs: Int) -> Bool {
        let now = mach_absolute_time()
        return state.withLock { s in
            guard let start = s.silenceStartTicks else { return false }
            let elapsedNs = Double(now - start) * timebaseNumer / timebaseDenom
            let elapsedMs = elapsedNs / 1_000_000
            return elapsedMs >= Double(durationMs)
        }
    }

    func reset() {
        state.withLock { s in
            s.silenceStartTicks = nil
            s.lastRMS = 0
        }
    }
}

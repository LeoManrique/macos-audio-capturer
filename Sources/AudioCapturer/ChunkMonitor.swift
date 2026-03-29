import Foundation
import os

/// Runs on a background queue, polls the silence detector, and sets a flag when rotation is needed.
/// Completely decoupled from MainActor.
final class ChunkMonitor: Sendable {
    private let detector: SilenceDetector
    private let config: ChunkingConfig
    private let chunkElapsed: OSAllocatedUnfairLock<TimeInterval>
    private let shouldRotate: OSAllocatedUnfairLock<Bool>
    private let timerSource: DispatchSourceTimer

    init(
        detector: SilenceDetector,
        config: ChunkingConfig,
        chunkElapsed: OSAllocatedUnfairLock<TimeInterval>,
        shouldRotate: OSAllocatedUnfairLock<Bool>
    ) {
        self.detector = detector
        self.config = config
        self.chunkElapsed = chunkElapsed
        self.shouldRotate = shouldRotate

        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + config.pollInterval, repeating: config.pollInterval)
        self.timerSource = source

        source.setEventHandler { [detector, config, chunkElapsed, shouldRotate] in
            let elapsed = chunkElapsed.withLock { $0 }

            let needed: Bool
            if elapsed >= config.hardCeilingDuration {
                needed = true
            } else if elapsed >= config.chunkMinDuration {
                needed = detector.isSilent(forMs: config.silenceDuration)
            } else {
                needed = false
            }

            if needed {
                shouldRotate.withLock { $0 = true }
            }
        }

        source.resume()
    }

    func cancel() {
        timerSource.cancel()
    }
}

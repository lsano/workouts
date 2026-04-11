import Foundation

// MARK: - Segment State

/// Represents the current state of set segmentation.
enum SegmentState {
    /// No significant movement detected.
    case idle
    /// Active exercise period detected, started at the given time.
    case active(startTime: TimeInterval)
    /// Exercise paused; resting since the given time.
    case resting(since: TimeInterval)
    /// A complete set was detected from startTime to endTime.
    case setComplete(startTime: TimeInterval, endTime: TimeInterval)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .idle:
            return "idle"
        case .active:
            return "active"
        case .resting:
            return "resting"
        case .setComplete:
            return "setComplete"
        }
    }
}

// MARK: - SetSegmenter

/// Detects active exercise periods vs rest by analyzing acceleration magnitude variance
/// over sliding windows. Uses hysteresis to prevent flapping between states.
final class SetSegmenter {

    // MARK: - Configuration

    /// Variance threshold (g^2) above which motion is considered "active".
    var activityThreshold: Double = 0.5

    /// Duration (seconds) of low variance required before transitioning to resting.
    var restDetectionSeconds: Double = 3.0

    /// Duration (seconds) of rest required to finalize a set as complete.
    var setCompletionRestSeconds: Double = 8.0

    /// Sliding window size (in samples) for computing variance.
    var varianceWindowSize: Int = 50

    /// Hysteresis factor: once active, the threshold to drop back is lower
    /// to prevent rapid toggling.
    var hysteresisMultiplier: Double = 0.7

    // MARK: - Internal State

    private var currentState: SegmentState = .idle
    private var activeStartTime: TimeInterval?
    private var restStartTime: TimeInterval?
    private var lastActiveTime: TimeInterval?

    /// Returns the current segmentation state without processing new data.
    var state: SegmentState {
        return currentState
    }

    // MARK: - Processing

    /// Analyze a window of fused sensor frames and return the updated segment state.
    /// Should be called periodically (e.g., every 200ms) with the latest data window.
    func processWindow(frames: [FusedSensorFrame]) -> SegmentState {
        guard !frames.isEmpty else { return currentState }

        // Extract acceleration magnitudes from all available sources
        let magnitudes = extractMagnitudes(from: frames)
        guard !magnitudes.isEmpty else { return currentState }

        // Compute variance over the most recent window
        let windowSamples = Array(magnitudes.suffix(varianceWindowSize))
        let currentVariance = SignalProcessing.variance(signal: windowSamples)

        let latestTimestamp = frames.last!.timestamp

        // Determine effective threshold based on current state (hysteresis)
        let effectiveThreshold: Double
        switch currentState {
        case .active:
            effectiveThreshold = activityThreshold * hysteresisMultiplier
        default:
            effectiveThreshold = activityThreshold
        }

        let isMoving = currentVariance > effectiveThreshold

        // State machine transitions
        switch currentState {
        case .idle:
            if isMoving {
                activeStartTime = latestTimestamp
                restStartTime = nil
                currentState = .active(startTime: latestTimestamp)
            }

        case .active(let startTime):
            if isMoving {
                lastActiveTime = latestTimestamp
                restStartTime = nil
            } else {
                // Movement stopped — begin rest countdown
                if restStartTime == nil {
                    restStartTime = latestTimestamp
                }

                let restDuration = latestTimestamp - (restStartTime ?? latestTimestamp)

                if restDuration >= restDetectionSeconds {
                    currentState = .resting(since: restStartTime ?? latestTimestamp)
                    activeStartTime = startTime
                }
            }

        case .resting(let since):
            if isMoving {
                // Resumed activity — go back to active
                let startTime = activeStartTime ?? latestTimestamp
                currentState = .active(startTime: startTime)
                restStartTime = nil
            } else {
                let restDuration = latestTimestamp - since
                if restDuration >= setCompletionRestSeconds {
                    let setStart = activeStartTime ?? since
                    let setEnd = lastActiveTime ?? since
                    currentState = .setComplete(startTime: setStart, endTime: setEnd)
                    // Reset for next set
                    activeStartTime = nil
                    restStartTime = nil
                    lastActiveTime = nil
                }
            }

        case .setComplete:
            // After a set completes, return to idle so we can detect the next one
            if isMoving {
                activeStartTime = latestTimestamp
                restStartTime = nil
                currentState = .active(startTime: latestTimestamp)
            } else {
                currentState = .idle
            }
        }

        return currentState
    }

    /// Reset the segmenter to idle state.
    func reset() {
        currentState = .idle
        activeStartTime = nil
        restStartTime = nil
        lastActiveTime = nil
    }

    // MARK: - Helpers

    /// Extract acceleration magnitudes from fused frames, preferring foot sensors over watch.
    private func extractMagnitudes(from frames: [FusedSensorFrame]) -> [Double] {
        return frames.map { frame -> Double in
            // Average available foot sensors; fall back to watch
            var sum = 0.0
            var count = 0

            if let left = frame.leftFoot {
                sum += left.accelMagnitude
                count += 1
            }
            if let right = frame.rightFoot {
                sum += right.accelMagnitude
                count += 1
            }
            if count == 0, let watch = frame.watch {
                sum += watch.accelMagnitude
                count += 1
            }

            return count > 0 ? sum / Double(count) : 0.0
        }
    }
}

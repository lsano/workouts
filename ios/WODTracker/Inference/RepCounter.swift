import Foundation

// MARK: - Rep Count Result

/// The result of counting repetitions in a sensor data window.
struct RepCountResult {
    /// Number of reps detected.
    let count: Int
    /// Confidence in the rep count (0-1).
    let confidence: Double
    /// Timestamps of each detected rep peak.
    let repTimestamps: [TimeInterval]
    /// Average tempo in milliseconds per rep.
    let avgTempoMs: Int
    /// Tempo consistency: coefficient of variation of inter-rep intervals (0 = perfect, lower = better).
    let tempoConsistency: Double

    static let empty = RepCountResult(count: 0, confidence: 0, repTimestamps: [], avgTempoMs: 0, tempoConsistency: 0)
}

// MARK: - RepCounter

/// Counts exercise repetitions by detecting peaks in the appropriate
/// acceleration axis based on the exercise type.
final class RepCounter {

    // MARK: - Public API

    /// Count repetitions from sensor data for a given exercise type.
    ///
    /// - Parameters:
    ///   - source: Which sensor source produced this data.
    ///   - frames: Timestamped sensor readings ordered by time.
    ///   - exerciseType: The detected exercise type (affects which axis/strategy is used).
    /// - Returns: A `RepCountResult` with count, timestamps, tempo, and confidence.
    func countReps(
        source: SensorSource,
        frames: [(timestamp: TimeInterval, reading: SensorReading)],
        exerciseType: ExerciseType
    ) -> RepCountResult {
        guard frames.count >= 4 else { return .empty }

        // Select the appropriate signal based on exercise type
        let signal = selectSignal(frames: frames, exerciseType: exerciseType)
        guard signal.count >= 4 else { return .empty }

        // Estimate sample rate
        let duration = frames.last!.timestamp - frames.first!.timestamp
        let sampleRate = duration > 0 ? Double(frames.count - 1) / duration : 50.0

        // Apply low-pass filter to smooth noise
        let cutoffHz = cutoffFrequency(for: exerciseType)
        let filtered = SignalProcessing.lowPassFilter(
            samples: signal,
            cutoffHz: cutoffHz,
            sampleRateHz: sampleRate
        )

        // Compute adaptive threshold from rolling statistics
        let windowSize = max(Int(sampleRate * 0.5), 5)
        let rollingMean = SignalProcessing.rollingMean(signal: filtered, windowSize: windowSize)
        let rollingStd = SignalProcessing.rollingStdDev(signal: filtered, windowSize: windowSize)

        // Adaptive threshold: mean + 0.5 * stddev
        let adaptiveThreshold = zip(rollingMean, rollingStd).map { $0 + 0.5 * $1 }
        let minHeight = adaptiveThreshold.reduce(0, +) / Double(adaptiveThreshold.count)

        // Minimum distance between peaks based on expected frequency range
        let (minFreq, maxFreq) = frequencyRange(for: exerciseType)
        let expectedFreq = (minFreq + maxFreq) / 2.0
        let minDistanceSamples = expectedFreq > 0 ? max(Int(sampleRate / maxFreq * 0.7), 2) : 5

        // Find peaks
        let peakIndices = SignalProcessing.findPeaks(
            signal: filtered,
            minHeight: minHeight,
            minDistance: minDistanceSamples
        )

        // Convert peak indices to timestamps
        let repTimestamps = peakIndices.compactMap { idx -> TimeInterval? in
            guard idx < frames.count else { return nil }
            return frames[idx].timestamp
        }

        // Compute inter-rep intervals
        var intervals: [Double] = []
        for i in 1..<repTimestamps.count {
            intervals.append(repTimestamps[i] - repTimestamps[i - 1])
        }

        // Average tempo
        let avgIntervalMs: Int
        if !intervals.isEmpty {
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
            avgIntervalMs = Int(avgInterval * 1000)
        } else {
            avgIntervalMs = 0
        }

        // Tempo consistency (coefficient of variation)
        let tempoConsistency: Double
        if intervals.count >= 2 {
            let mean = intervals.reduce(0, +) / Double(intervals.count)
            let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
            let stdDev = sqrt(variance)
            tempoConsistency = mean > 0 ? stdDev / mean : 1.0
        } else {
            tempoConsistency = 0.0
        }

        // Determine rep count (for bilateral exercises, may need adjustment)
        let rawCount = repTimestamps.count
        let adjustedCount = adjustForBilateral(
            count: rawCount,
            exerciseType: exerciseType,
            source: source
        )

        // Confidence based on tempo consistency and peak count
        let confidence = computeConfidence(
            repCount: adjustedCount,
            tempoCV: tempoConsistency,
            exerciseType: exerciseType,
            peakCount: rawCount
        )

        return RepCountResult(
            count: adjustedCount,
            confidence: confidence,
            repTimestamps: repTimestamps,
            avgTempoMs: avgIntervalMs,
            tempoConsistency: tempoConsistency
        )
    }

    // MARK: - Signal Selection

    /// Select the appropriate signal axis/combination based on exercise type.
    private func selectSignal(
        frames: [(timestamp: TimeInterval, reading: SensorReading)],
        exerciseType: ExerciseType
    ) -> [Double] {
        switch exerciseType {
        case .jumpRope, .pogoHops, .boxJumps, .alternatingLunges, .stepUps:
            // Vertical-dominant: use Y-axis (assuming Y is up)
            return frames.map { $0.reading.ay }

        case .skaterHops:
            // Lateral-dominant: use X-axis
            return frames.map { $0.reading.ax }

        case .agilityLadder:
            // Total magnitude captures rapid footwork regardless of direction
            return frames.map { $0.reading.accelMagnitude }

        case .unknown:
            // Default to total acceleration magnitude
            return frames.map { $0.reading.accelMagnitude }
        }
    }

    /// Expected frequency range for each exercise type (Hz).
    private func frequencyRange(for exerciseType: ExerciseType) -> (Double, Double) {
        switch exerciseType {
        case .jumpRope:         return (2.0, 3.0)
        case .pogoHops:         return (1.0, 2.0)
        case .alternatingLunges: return (0.3, 0.7)
        case .stepUps:          return (0.5, 1.0)
        case .skaterHops:       return (0.5, 1.5)
        case .agilityLadder:    return (3.0, 6.0)
        case .boxJumps:         return (0.2, 0.5)
        case .unknown:          return (0.5, 2.0)
        }
    }

    /// Low-pass filter cutoff frequency tuned per exercise type.
    private func cutoffFrequency(for exerciseType: ExerciseType) -> Double {
        let (_, maxFreq) = frequencyRange(for: exerciseType)
        // Cutoff at 2x the max expected frequency to preserve the signal while removing noise
        return min(maxFreq * 2.0, 25.0)
    }

    // MARK: - Bilateral Adjustment

    /// For bilateral exercises (lunges, step-ups) counted from a single foot sensor,
    /// each foot contributes one peak per full rep. If we're counting from a single
    /// foot, the count already represents full reps on that side.
    private func adjustForBilateral(
        count: Int,
        exerciseType: ExerciseType,
        source: SensorSource
    ) -> Int {
        // Bilateral exercises where each foot = one side of the movement
        // If data comes from a single foot, each peak is one full bilateral rep
        // (left step + right step = 2 peaks across both, 1 per foot)
        // So single-foot counts are correct as-is.
        //
        // If we ever combine both feet into one signal, we'd divide by 2.
        return count
    }

    // MARK: - Confidence

    /// Compute confidence in the rep count based on tempo consistency and exercise characteristics.
    private func computeConfidence(
        repCount: Int,
        tempoCV: Double,
        exerciseType: ExerciseType,
        peakCount: Int
    ) -> Double {
        guard repCount > 0 else { return 0.0 }

        var confidence = 1.0

        // Penalize high tempo variability
        // CV < 0.1 is very consistent, > 0.5 is very inconsistent
        if tempoCV > 0.1 {
            confidence -= min(tempoCV * 0.5, 0.4)
        }

        // Very few reps are less reliable
        if repCount < 3 {
            confidence *= 0.7
        }

        // Very many reps without pauses are suspicious for slow exercises
        let (_, maxFreq) = frequencyRange(for: exerciseType)
        if exerciseType == .boxJumps && repCount > 20 {
            confidence *= 0.5
        } else if maxFreq < 1.0 && repCount > 40 {
            confidence *= 0.6
        }

        return max(min(confidence, 1.0), 0.0)
    }
}

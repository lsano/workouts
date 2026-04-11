import Foundation

// MARK: - Set Quality

/// Overall quality metrics for a completed set.
struct SetQuality {
    /// Average tempo in milliseconds per rep.
    let avgTempo: Double
    /// Tempo consistency score (0-1, higher = more consistent).
    let tempoConsistency: Double
    /// Left/right symmetry score (0-1, higher = more balanced).
    let symmetryScore: Double
    /// Depth proxy score (0-1, relative to baseline amplitude).
    let depthScore: Double
    /// Depth consistency score (0-1, higher = more consistent depth across reps).
    let depthConsistency: Double
    /// Weighted overall quality score (0-1).
    let overallQuality: Double

    func toDictionary() -> [String: Any] {
        return [
            "avgTempo": avgTempo,
            "tempoConsistency": tempoConsistency,
            "symmetryScore": symmetryScore,
            "depthScore": depthScore,
            "depthConsistency": depthConsistency,
            "overallQuality": overallQuality
        ]
    }
}

// MARK: - Rep Quality

/// Quality metrics for an individual rep within a set.
struct RepQuality {
    /// Tempo of this specific rep (ms).
    let tempoMs: Int
    /// Depth proxy score (0-1).
    let depthScore: Double
    /// Left/right symmetry for this rep (0-1).
    let symmetryScore: Double
    /// Stability score during the rep (0-1, lower variance = more stable).
    let stabilityScore: Double

    func toDictionary() -> [String: Any] {
        return [
            "tempoMs": tempoMs,
            "depthScore": depthScore,
            "symmetryScore": symmetryScore,
            "stabilityScore": stabilityScore
        ]
    }
}

// MARK: - QualityScorer

/// Scores movement quality for sets and individual reps by analyzing
/// acceleration patterns, L/R symmetry, and consistency metrics.
final class QualityScorer {

    /// Baseline peak acceleration per exercise type (g).
    /// Used as the reference for depth scoring. Can be updated per-user.
    private var depthBaselines: [ExerciseType: Double] = [
        .jumpRope: 1.8,
        .pogoHops: 3.0,
        .alternatingLunges: 2.5,
        .stepUps: 2.0,
        .skaterHops: 3.0,
        .agilityLadder: 2.0,
        .boxJumps: 5.0,
        .unknown: 2.0
    ]

    // MARK: - Weights

    /// Scoring weights per category for overall quality.
    private let tempoWeight = 0.25
    private let symmetryWeight = 0.25
    private let depthWeight = 0.25
    private let depthConsistencyWeight = 0.25

    // MARK: - Public API

    /// Update the depth baseline for a specific exercise type (e.g., from user history).
    func setDepthBaseline(_ baseline: Double, for exerciseType: ExerciseType) {
        depthBaselines[exerciseType] = baseline
    }

    /// Score a complete set using rep count results and raw sensor data from both feet.
    ///
    /// - Parameters:
    ///   - reps: The rep count result including timestamps and tempo.
    ///   - leftFootData: Raw timestamped readings from the left foot sensor.
    ///   - rightFootData: Raw timestamped readings from the right foot sensor.
    ///   - exerciseType: The detected exercise type.
    /// - Returns: A `SetQuality` with all scoring dimensions.
    func scoreSet(
        reps: RepCountResult,
        leftFootData: [(timestamp: TimeInterval, reading: SensorReading)],
        rightFootData: [(timestamp: TimeInterval, reading: SensorReading)],
        exerciseType: ExerciseType
    ) -> SetQuality {
        guard reps.count > 0 else {
            return SetQuality(
                avgTempo: 0, tempoConsistency: 0, symmetryScore: 0,
                depthScore: 0, depthConsistency: 0, overallQuality: 0
            )
        }

        // Tempo consistency: 1 - CV (clamped to 0-1)
        let tempoConsistency = max(1.0 - reps.tempoConsistency, 0.0)

        // Symmetry: compare left vs right peak amplitudes and timing
        let symmetryScore = computeSymmetry(
            repTimestamps: reps.repTimestamps,
            leftData: leftFootData,
            rightData: rightFootData
        )

        // Depth: compute per-rep peak accelerations and compare to baseline
        let repDepths = computeRepDepths(
            repTimestamps: reps.repTimestamps,
            leftData: leftFootData,
            rightData: rightFootData,
            exerciseType: exerciseType
        )

        let baseline = depthBaselines[exerciseType] ?? 2.0
        let depthScores = repDepths.map { min($0 / baseline, 1.0) }
        let depthScore = depthScores.isEmpty ? 0.0 : depthScores.reduce(0, +) / Double(depthScores.count)

        // Depth consistency: 1 - CV of depth scores
        let depthConsistency: Double
        if depthScores.count >= 2 {
            let mean = depthScores.reduce(0, +) / Double(depthScores.count)
            let variance = depthScores.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(depthScores.count)
            let cv = mean > 0 ? sqrt(variance) / mean : 1.0
            depthConsistency = max(1.0 - cv, 0.0)
        } else {
            depthConsistency = depthScore > 0 ? 0.8 : 0.0
        }

        // Weighted overall quality
        let overallQuality = tempoWeight * tempoConsistency
            + symmetryWeight * symmetryScore
            + depthWeight * depthScore
            + depthConsistencyWeight * depthConsistency

        return SetQuality(
            avgTempo: Double(reps.avgTempoMs),
            tempoConsistency: tempoConsistency,
            symmetryScore: symmetryScore,
            depthScore: depthScore,
            depthConsistency: depthConsistency,
            overallQuality: min(overallQuality, 1.0)
        )
    }

    /// Score an individual rep by examining sensor data around the rep's timestamp.
    ///
    /// - Parameters:
    ///   - repIndex: The index of the rep within the set.
    ///   - repTimestamps: All rep timestamps from the set.
    ///   - leftFootData: Left foot sensor data.
    ///   - rightFootData: Right foot sensor data.
    ///   - exerciseType: Detected exercise type.
    ///   - avgTempoMs: Average tempo of the set for comparison.
    /// - Returns: A `RepQuality` for this specific rep.
    func scoreRep(
        repIndex: Int,
        repTimestamps: [TimeInterval],
        leftFootData: [(timestamp: TimeInterval, reading: SensorReading)],
        rightFootData: [(timestamp: TimeInterval, reading: SensorReading)],
        exerciseType: ExerciseType,
        avgTempoMs: Int
    ) -> RepQuality {
        guard repIndex >= 0, repIndex < repTimestamps.count else {
            return RepQuality(tempoMs: 0, depthScore: 0, symmetryScore: 0, stabilityScore: 0)
        }

        let repTime = repTimestamps[repIndex]

        // Compute this rep's tempo
        let tempoMs: Int
        if repIndex > 0 {
            tempoMs = Int((repTime - repTimestamps[repIndex - 1]) * 1000)
        } else if repTimestamps.count > 1 {
            tempoMs = Int((repTimestamps[1] - repTimestamps[0]) * 1000)
        } else {
            tempoMs = avgTempoMs
        }

        // Window around the rep for analysis (half a rep period on each side)
        let halfPeriod = Double(avgTempoMs) / 1000.0 / 2.0
        let windowStart = repTime - halfPeriod
        let windowEnd = repTime + halfPeriod

        // Extract data in the rep window
        let leftWindow = leftFootData.filter { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
        let rightWindow = rightFootData.filter { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }

        // Depth score: peak acceleration in this window relative to baseline
        let baseline = depthBaselines[exerciseType] ?? 2.0
        let leftPeak = leftWindow.map { $0.reading.accelMagnitude }.max() ?? 0
        let rightPeak = rightWindow.map { $0.reading.accelMagnitude }.max() ?? 0
        let peakAccel = max(leftPeak, rightPeak)
        let depthScore = min(peakAccel / baseline, 1.0)

        // Symmetry for this rep: compare L/R peaks
        let symmetryScore: Double
        if leftPeak > 0 && rightPeak > 0 {
            let ratio = min(leftPeak, rightPeak) / max(leftPeak, rightPeak)
            symmetryScore = ratio
        } else if leftPeak > 0 || rightPeak > 0 {
            symmetryScore = 0.5  // Only one side available
        } else {
            symmetryScore = 0.0
        }

        // Stability: lower acceleration variance during the rep = more stable
        let combinedReadings = (leftWindow.map { $0.reading } + rightWindow.map { $0.reading })
        let magnitudes = combinedReadings.map { $0.accelMagnitude }
        let stabilityScore: Double
        if magnitudes.count >= 2 {
            let variance = SignalProcessing.variance(signal: magnitudes)
            // Normalize: variance of 0 = perfect stability, higher = worse
            // Use a sigmoid-like mapping: score = 1 / (1 + variance)
            stabilityScore = 1.0 / (1.0 + variance)
        } else {
            stabilityScore = 0.5
        }

        return RepQuality(
            tempoMs: tempoMs,
            depthScore: depthScore,
            symmetryScore: symmetryScore,
            stabilityScore: stabilityScore
        )
    }

    // MARK: - Internal Scoring

    /// Compute left/right symmetry across all reps.
    private func computeSymmetry(
        repTimestamps: [TimeInterval],
        leftData: [(timestamp: TimeInterval, reading: SensorReading)],
        rightData: [(timestamp: TimeInterval, reading: SensorReading)]
    ) -> Double {
        guard !repTimestamps.isEmpty, !leftData.isEmpty, !rightData.isEmpty else {
            // If only one foot sensor is available, assign neutral symmetry
            return (leftData.isEmpty && rightData.isEmpty) ? 0.0 : 0.5
        }

        var symmetryScores: [Double] = []

        for repTime in repTimestamps {
            // Find peak acceleration near this rep timestamp (within 200ms)
            let tolerance = 0.2

            let leftPeak = leftData
                .filter { abs($0.timestamp - repTime) <= tolerance }
                .map { $0.reading.accelMagnitude }
                .max() ?? 0

            let rightPeak = rightData
                .filter { abs($0.timestamp - repTime) <= tolerance }
                .map { $0.reading.accelMagnitude }
                .max() ?? 0

            if leftPeak > 0 && rightPeak > 0 {
                let ratio = min(leftPeak, rightPeak) / max(leftPeak, rightPeak)
                symmetryScores.append(ratio)
            }
        }

        guard !symmetryScores.isEmpty else { return 0.5 }
        return symmetryScores.reduce(0, +) / Double(symmetryScores.count)
    }

    /// Compute per-rep peak acceleration values as a depth proxy.
    private func computeRepDepths(
        repTimestamps: [TimeInterval],
        leftData: [(timestamp: TimeInterval, reading: SensorReading)],
        rightData: [(timestamp: TimeInterval, reading: SensorReading)],
        exerciseType: ExerciseType
    ) -> [Double] {
        let allData = leftData + rightData
        guard !allData.isEmpty else { return [] }

        return repTimestamps.map { repTime -> Double in
            let tolerance = 0.2
            let nearby = allData.filter { abs($0.timestamp - repTime) <= tolerance }
            return nearby.map { $0.reading.accelMagnitude }.max() ?? 0.0
        }
    }
}

import Foundation

// MARK: - Exercise Type

/// Supported exercise types for auto-detection.
enum ExerciseType: String, CaseIterable, Codable {
    case jumpRope
    case pogoHops
    case alternatingLunges
    case stepUps
    case skaterHops
    case agilityLadder
    case boxJumps
    case unknown
}

// MARK: - Classification Result

/// The result of classifying a movement window.
struct ClassificationResult {
    let exerciseType: ExerciseType
    let confidence: Double

    static let unknown = ClassificationResult(exerciseType: .unknown, confidence: 0.0)
}

// MARK: - Movement Features

/// Features extracted from a sensor data window for classification.
struct MovementFeatures {
    /// Dominant frequency of the movement pattern (Hz).
    let dominantFrequency: Double
    /// Peak acceleration magnitude (g).
    let peakAcceleration: Double
    /// Ratio of vertical (Y-axis) acceleration energy to total acceleration energy.
    let verticalDominance: Double
    /// Ratio of lateral (X-axis) acceleration energy to total acceleration energy.
    let lateralDominance: Double
    /// Left/right alternation score: 0 = simultaneous, 1 = perfectly alternating.
    let leftRightAlternation: Double
    /// Phase offset between left and right foot peaks (seconds).
    let leftRightPhaseOffset: Double
    /// Average peak-to-trough acceleration amplitude (g).
    let accelerationAmplitude: Double
    /// Average gyroscope magnitude (deg/s).
    let gyroMagnitude: Double
}

// MARK: - MovementClassifier

/// Rule-based exercise classifier that uses extracted motion features
/// to identify the type of exercise being performed.
final class MovementClassifier {

    // MARK: - Feature Extraction

    /// Extract movement features from the fusion engine's current data window.
    func extractFeatures(
        fusionEngine: SensorFusionEngine,
        windowSeconds: Double = 4.0
    ) -> MovementFeatures {
        let leftSamples = fusionEngine.getSourceWindow(source: .leftFoot, durationSeconds: windowSeconds)
        let rightSamples = fusionEngine.getSourceWindow(source: .rightFoot, durationSeconds: windowSeconds)
        let watchSamples = fusionEngine.getSourceWindow(source: .watch, durationSeconds: windowSeconds)

        // Use foot sensors as primary; fall back to watch
        let primarySamples: [(timestamp: TimeInterval, reading: SensorReading)]
        if leftSamples.count >= rightSamples.count && !leftSamples.isEmpty {
            primarySamples = leftSamples
        } else if !rightSamples.isEmpty {
            primarySamples = rightSamples
        } else {
            primarySamples = watchSamples
        }

        guard primarySamples.count >= 4 else {
            return MovementFeatures(
                dominantFrequency: 0, peakAcceleration: 0, verticalDominance: 0,
                lateralDominance: 0, leftRightAlternation: 0, leftRightPhaseOffset: 0,
                accelerationAmplitude: 0, gyroMagnitude: 0
            )
        }

        // Estimate sample rate from timestamps
        let duration = primarySamples.last!.timestamp - primarySamples.first!.timestamp
        let sampleRate = duration > 0 ? Double(primarySamples.count - 1) / duration : 50.0

        // Extract axis arrays
        let ax = primarySamples.map { $0.reading.ax }
        let ay = primarySamples.map { $0.reading.ay }
        let az = primarySamples.map { $0.reading.az }
        let magnitudes = SignalProcessing.magnitudeArray(ax: ax, ay: ay, az: az)

        // Dominant frequency from acceleration magnitude signal
        let dominantFreq = SignalProcessing.dominantFrequency(signal: magnitudes, sampleRateHz: sampleRate)

        // Peak acceleration
        let peakAccel = magnitudes.max() ?? 0.0

        // Axis dominance: energy ratios
        let axEnergy = ax.map { $0 * $0 }.reduce(0, +)
        let ayEnergy = ay.map { $0 * $0 }.reduce(0, +)
        let azEnergy = az.map { $0 * $0 }.reduce(0, +)
        let totalEnergy = axEnergy + ayEnergy + azEnergy
        let verticalDominance = totalEnergy > 0 ? ayEnergy / totalEnergy : 0.0
        let lateralDominance = totalEnergy > 0 ? axEnergy / totalEnergy : 0.0

        // Average peak-to-trough amplitude
        let minAccel = magnitudes.min() ?? 0.0
        let avgAmplitude = peakAccel - minAccel

        // Gyroscope magnitude
        let gyroMags = primarySamples.map { $0.reading.gyroMagnitude }
        let avgGyro = gyroMags.isEmpty ? 0.0 : gyroMags.reduce(0, +) / Double(gyroMags.count)

        // Left/right alternation and phase offset
        let (alternation, phaseOffset) = computeAlternation(
            leftSamples: leftSamples,
            rightSamples: rightSamples,
            sampleRate: sampleRate
        )

        return MovementFeatures(
            dominantFrequency: dominantFreq,
            peakAcceleration: peakAccel,
            verticalDominance: verticalDominance,
            lateralDominance: lateralDominance,
            leftRightAlternation: alternation,
            leftRightPhaseOffset: phaseOffset,
            accelerationAmplitude: avgAmplitude,
            gyroMagnitude: avgGyro
        )
    }

    // MARK: - Classification

    /// Classify the exercise type from extracted features using a rule-based system.
    func classify(features: MovementFeatures) -> ClassificationResult {
        var scores: [(ExerciseType, Double)] = []

        scores.append((.jumpRope, scoreJumpRope(features)))
        scores.append((.pogoHops, scorePogoHops(features)))
        scores.append((.alternatingLunges, scoreAlternatingLunges(features)))
        scores.append((.stepUps, scoreStepUps(features)))
        scores.append((.skaterHops, scoreSkaterHops(features)))
        scores.append((.agilityLadder, scoreAgilityLadder(features)))
        scores.append((.boxJumps, scoreBoxJumps(features)))

        // Pick the highest scoring exercise
        scores.sort { $0.1 > $1.1 }

        guard let best = scores.first, best.1 >= 0.4 else {
            return .unknown
        }

        return ClassificationResult(exerciseType: best.0, confidence: best.1)
    }

    // MARK: - Scoring Functions

    /// Jump rope: freq 2-3Hz, low amplitude (<2g), both feet simultaneous.
    private func scoreJumpRope(_ f: MovementFeatures) -> Double {
        var score = 0.0
        score += gaussian(f.dominantFrequency, center: 2.5, sigma: 0.5) * 0.30
        score += (f.peakAcceleration < 2.0 ? 1.0 : gaussian(f.peakAcceleration, center: 1.5, sigma: 0.5)) * 0.20
        score += (1.0 - f.leftRightAlternation) * 0.25  // Simultaneous feet
        score += f.verticalDominance * 0.15
        score += (f.gyroMagnitude > 50 ? 0.5 : 0.0) * 0.10  // Wrist rotation from rope
        return min(score, 1.0)
    }

    /// Pogo hops: freq 1-2Hz, moderate amplitude, both feet.
    private func scorePogoHops(_ f: MovementFeatures) -> Double {
        var score = 0.0
        score += gaussian(f.dominantFrequency, center: 1.5, sigma: 0.5) * 0.30
        score += gaussian(f.accelerationAmplitude, center: 2.5, sigma: 1.0) * 0.25
        score += (1.0 - f.leftRightAlternation) * 0.25
        score += f.verticalDominance * 0.20
        return min(score, 1.0)
    }

    /// Alternating lunges: freq 0.3-0.7Hz, high alternation, high vertical dominance.
    private func scoreAlternatingLunges(_ f: MovementFeatures) -> Double {
        var score = 0.0
        score += gaussian(f.dominantFrequency, center: 0.5, sigma: 0.2) * 0.25
        score += (f.leftRightAlternation > 0.7 ? f.leftRightAlternation : 0.0) * 0.30
        score += f.verticalDominance * 0.25
        score += gaussian(f.accelerationAmplitude, center: 2.0, sigma: 1.0) * 0.20
        return min(score, 1.0)
    }

    /// Step-ups: freq 0.5-1Hz, high alternation, moderate vertical.
    private func scoreStepUps(_ f: MovementFeatures) -> Double {
        var score = 0.0
        score += gaussian(f.dominantFrequency, center: 0.75, sigma: 0.25) * 0.25
        score += (f.leftRightAlternation > 0.6 ? f.leftRightAlternation : 0.0) * 0.30
        score += f.verticalDominance * 0.20
        score += gaussian(f.peakAcceleration, center: 2.0, sigma: 0.5) * 0.15
        score += gaussian(f.accelerationAmplitude, center: 1.5, sigma: 0.5) * 0.10
        return min(score, 1.0)
    }

    /// Skater hops: freq 0.5-1.5Hz, high lateral dominance, high alternation.
    private func scoreSkaterHops(_ f: MovementFeatures) -> Double {
        var score = 0.0
        score += gaussian(f.dominantFrequency, center: 1.0, sigma: 0.5) * 0.20
        score += f.lateralDominance * 0.30
        score += (f.leftRightAlternation > 0.6 ? f.leftRightAlternation : 0.0) * 0.25
        score += gaussian(f.accelerationAmplitude, center: 2.5, sigma: 1.0) * 0.15
        score += (1.0 - f.verticalDominance) * 0.10  // Not primarily vertical
        return min(score, 1.0)
    }

    /// Agility ladder: freq >3Hz, very rapid L/R, low amplitude.
    private func scoreAgilityLadder(_ f: MovementFeatures) -> Double {
        var score = 0.0
        score += (f.dominantFrequency > 3.0 ? min(f.dominantFrequency / 5.0, 1.0) : 0.0) * 0.35
        score += (f.leftRightAlternation > 0.5 ? f.leftRightAlternation : 0.0) * 0.25
        score += (f.accelerationAmplitude < 2.0 ? 1.0 - f.accelerationAmplitude / 2.0 : 0.0) * 0.20
        score += (f.peakAcceleration < 3.0 ? 1.0 : 0.0) * 0.20
        return min(score, 1.0)
    }

    /// Box jumps: freq 0.2-0.5Hz, very high peak accel (>4g on landing).
    private func scoreBoxJumps(_ f: MovementFeatures) -> Double {
        var score = 0.0
        score += gaussian(f.dominantFrequency, center: 0.35, sigma: 0.15) * 0.25
        score += (f.peakAcceleration > 4.0 ? min(f.peakAcceleration / 6.0, 1.0) : 0.0) * 0.35
        score += f.verticalDominance * 0.20
        score += (1.0 - f.leftRightAlternation) * 0.10  // Both feet
        score += gaussian(f.accelerationAmplitude, center: 4.0, sigma: 1.5) * 0.10
        return min(score, 1.0)
    }

    // MARK: - Alternation Analysis

    /// Compute left/right alternation score and phase offset from foot sensor data.
    private func computeAlternation(
        leftSamples: [(timestamp: TimeInterval, reading: SensorReading)],
        rightSamples: [(timestamp: TimeInterval, reading: SensorReading)],
        sampleRate: Double
    ) -> (alternation: Double, phaseOffset: Double) {
        guard leftSamples.count >= 4, rightSamples.count >= 4 else {
            return (0.0, 0.0)
        }

        // Compute magnitude signals
        let leftMag = leftSamples.map { $0.reading.accelMagnitude }
        let rightMag = rightSamples.map { $0.reading.accelMagnitude }

        // Find peaks in each
        let leftMean = leftMag.reduce(0, +) / Double(leftMag.count)
        let rightMean = rightMag.reduce(0, +) / Double(rightMag.count)
        let minDist = max(Int(sampleRate * 0.15), 2)  // At least 150ms between peaks

        let leftPeaks = SignalProcessing.findPeaks(signal: leftMag, minHeight: leftMean * 1.2, minDistance: minDist)
        let rightPeaks = SignalProcessing.findPeaks(signal: rightMag, minHeight: rightMean * 1.2, minDistance: minDist)

        guard !leftPeaks.isEmpty, !rightPeaks.isEmpty else {
            return (0.0, 0.0)
        }

        // Convert peak indices to timestamps
        let leftPeakTimes = leftPeaks.compactMap { idx -> TimeInterval? in
            guard idx < leftSamples.count else { return nil }
            return leftSamples[idx].timestamp
        }
        let rightPeakTimes = rightPeaks.compactMap { idx -> TimeInterval? in
            guard idx < rightSamples.count else { return nil }
            return rightSamples[idx].timestamp
        }

        // Compute average phase offset: for each left peak, find the nearest right peak
        var offsets: [Double] = []
        for lt in leftPeakTimes {
            var bestOffset = Double.greatestFiniteMagnitude
            for rt in rightPeakTimes {
                let offset = abs(lt - rt)
                if offset < abs(bestOffset) {
                    bestOffset = lt - rt
                }
            }
            if abs(bestOffset) < Double.greatestFiniteMagnitude {
                offsets.append(bestOffset)
            }
        }

        guard !offsets.isEmpty else { return (0.0, 0.0) }

        let avgOffset = offsets.map { abs($0) }.reduce(0, +) / Double(offsets.count)

        // Estimate the expected half-period from dominant frequency
        let combinedMag = leftMag.count >= rightMag.count ? leftMag : rightMag
        let domFreq = SignalProcessing.dominantFrequency(signal: combinedMag, sampleRateHz: sampleRate)
        let halfPeriod = domFreq > 0 ? 0.5 / domFreq : 0.5

        // Alternation score: if the average offset is close to half the period, it's alternating
        // If close to 0, it's simultaneous
        let alternation: Double
        if halfPeriod > 0 {
            alternation = min(avgOffset / halfPeriod, 1.0)
        } else {
            alternation = 0.0
        }

        return (alternation, avgOffset)
    }

    // MARK: - Utility

    /// Gaussian function for smooth scoring around a center value.
    private func gaussian(_ value: Double, center: Double, sigma: Double) -> Double {
        let diff = value - center
        return exp(-(diff * diff) / (2.0 * sigma * sigma))
    }
}

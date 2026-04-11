import Foundation
import Combine

// MARK: - Alert Severity

enum AlertSeverity: String {
    case info
    case warning
    case error
}

// MARK: - FormAlert

struct FormAlert {
    let message: String
    let severity: AlertSeverity
}

// MARK: - DetectedSetResult

struct DetectedSetResult {
    let exerciseType: ExerciseType
    let detectedType: ExerciseType
    let confidence: Double
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let repCount: Int
    let detectedRepCount: Int
    let durationSeconds: Double?
    let quality: SetQuality?
    let userCorrectedType: ExerciseType?
    let userCorrectedReps: Int?
}

// MARK: - Detected Set (internal)

/// Tracks a detected exercise set with its metadata during a session.
private struct DetectedSet {
    var exerciseType: ExerciseType
    var confidence: Double
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var repCount: Int
    var quality: SetQuality?
    var userCorrectedType: ExerciseType?
    var userCorrectedReps: Int?

    var effectiveType: ExerciseType {
        return userCorrectedType ?? exerciseType
    }

    var effectiveReps: Int {
        return userCorrectedReps ?? repCount
    }

    func toResult(index: Int) -> DetectedSetResult {
        return DetectedSetResult(
            exerciseType: effectiveType,
            detectedType: exerciseType,
            confidence: confidence,
            startTime: startTime,
            endTime: endTime,
            repCount: effectiveReps,
            detectedRepCount: repCount,
            durationSeconds: endTime.map { $0 - startTime },
            quality: quality,
            userCorrectedType: userCorrectedType,
            userCorrectedReps: userCorrectedReps
        )
    }
}

// MARK: - InferenceEngine

final class InferenceEngine: ObservableObject {

    // MARK: - Published Properties

    @Published var currentRepCount = 0
    @Published var currentExercise: ExerciseType = .unknown
    @Published var currentConfidence: Double = 0
    @Published var movementState: MovementState = .idle
    @Published var formAlert: FormAlert?
    @Published var detectedSets: [DetectedSetResult] = []

    // MARK: - Pipeline Components

    private let fusionEngine = SensorFusionEngine()
    private let segmenter = SetSegmenter()
    private let classifier = MovementClassifier()
    private let repCounter = RepCounter()
    private let qualityScorer = QualityScorer()

    // MARK: - State

    private var processingQueue = DispatchQueue(label: "com.wod.inferenceengine", qos: .userInitiated)
    private var processingTimer: DispatchSourceTimer?
    private var isProcessing = false

    /// All sets detected during this session.
    private var completedSets: [DetectedSet] = []

    /// The current set being tracked (not yet completed).
    private var currentSet: DetectedSet?

    /// Last known rep count for detecting new reps.
    private var lastRepCount = 0

    /// Last emitted movement state, to avoid redundant updates.
    private var lastEmittedState: MovementState = .idle

    /// Window duration (seconds) for the processing loop.
    private let analysisWindowSeconds: Double = 4.0

    /// Processing loop interval (seconds).
    private let processingIntervalSeconds: Double = 0.2

    // MARK: - Public Methods

    /// Start the background inference processing loop.
    func startProcessing() {
        guard !isProcessing else { return }

        isProcessing = true
        lastRepCount = 0
        lastEmittedState = .idle
        segmenter.reset()

        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(
            deadline: .now(),
            repeating: processingIntervalSeconds,
            leeway: .milliseconds(10)
        )
        timer.setEventHandler { [weak self] in
            self?.runProcessingLoop()
        }
        timer.resume()
        processingTimer = timer
    }

    /// Stop the background inference processing loop.
    func stopProcessing() {
        isProcessing = false
        processingTimer?.cancel()
        processingTimer = nil

        // If there's an active set, finalize it
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            if var current = self.currentSet {
                if let latestTime = self.fusionEngine.latestTimestamp() {
                    current.endTime = latestTime
                }
                self.completedSets.append(current)
                self.currentSet = nil
                self.publishDetectedSets()
            }
        }
    }

    /// Receive sensor samples from a given source and feed them into the fusion engine.
    func ingestSamples(source: SensorSource, samples: [SensorSample]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            for sample in samples {
                let reading = SensorReading(
                    ax: sample.ax, ay: sample.ay, az: sample.az,
                    gx: sample.gx, gy: sample.gy, gz: sample.gz
                )
                self.fusionEngine.addSample(source: source, timestamp: sample.timestamp, reading: reading)
            }
        }
    }

    /// User correction: override the detected exercise type for a specific set.
    func correctExercise(setIndex: Int, type: ExerciseType) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            if setIndex < self.completedSets.count {
                self.completedSets[setIndex].userCorrectedType = type
                self.publishDetectedSets()
            } else if self.currentSet != nil && setIndex == self.completedSets.count {
                self.currentSet?.userCorrectedType = type
                self.publishDetectedSets()
            }
        }
    }

    /// User correction: override the detected rep count for a specific set.
    func correctRepCount(setIndex: Int, count: Int) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            if setIndex < self.completedSets.count {
                self.completedSets[setIndex].userCorrectedReps = count
                self.publishDetectedSets()
            } else if self.currentSet != nil && setIndex == self.completedSets.count {
                self.currentSet?.userCorrectedReps = count
                self.publishDetectedSets()
            }
        }
    }

    // MARK: - Processing Loop

    /// Main inference loop, called every ~200ms on the processing queue.
    private func runProcessingLoop() {
        guard isProcessing else { return }

        // Step 1: Get the latest window from the fusion engine
        let frames = fusionEngine.getWindow(durationSeconds: analysisWindowSeconds)
        guard !frames.isEmpty else { return }

        // Step 2: Run set segmenter
        let segmentState = segmenter.processWindow(frames: frames)
        emitMovementStateChange(segmentState)

        // Step 3: Process based on segment state
        switch segmentState {
        case .idle:
            break

        case .active(let startTime):
            processActiveState(startTime: startTime)

        case .resting:
            break

        case .setComplete(let startTime, let endTime):
            finalizeSet(startTime: startTime, endTime: endTime)
        }
    }

    /// Process sensor data during an active exercise period.
    private func processActiveState(startTime: TimeInterval) {
        // Classify the exercise
        let features = classifier.extractFeatures(
            fusionEngine: fusionEngine,
            windowSeconds: analysisWindowSeconds
        )
        let classification = classifier.classify(features: features)

        // Initialize current set if needed
        if currentSet == nil {
            currentSet = DetectedSet(
                exerciseType: classification.exerciseType,
                confidence: classification.confidence,
                startTime: startTime,
                endTime: nil,
                repCount: 0,
                quality: nil
            )
        } else {
            // Update classification if confidence improves
            if classification.confidence > (currentSet?.confidence ?? 0) {
                currentSet?.exerciseType = classification.exerciseType
                currentSet?.confidence = classification.confidence
            }
        }

        // Count reps from the primary foot sensor
        let exerciseType = currentSet?.effectiveType ?? classification.exerciseType

        let leftData = fusionEngine.getSourceWindow(source: .leftFoot, durationSeconds: analysisWindowSeconds)
        let rightData = fusionEngine.getSourceWindow(source: .rightFoot, durationSeconds: analysisWindowSeconds)
        let watchData = fusionEngine.getSourceWindow(source: .watch, durationSeconds: analysisWindowSeconds)

        let repResult: RepCountResult
        if !leftData.isEmpty {
            repResult = repCounter.countReps(source: .leftFoot, frames: leftData, exerciseType: exerciseType)
        } else if !rightData.isEmpty {
            repResult = repCounter.countReps(source: .rightFoot, frames: rightData, exerciseType: exerciseType)
        } else if !watchData.isEmpty {
            repResult = repCounter.countReps(source: .watch, frames: watchData, exerciseType: exerciseType)
        } else {
            return
        }

        // Update rep count
        if repResult.count > lastRepCount {
            currentSet?.repCount = repResult.count
            lastRepCount = repResult.count

            DispatchQueue.main.async { [weak self] in
                self?.currentRepCount = repResult.count
                self?.currentExercise = exerciseType
                self?.currentConfidence = repResult.confidence
            }
        }

        // Score quality and check for form alerts
        let quality = qualityScorer.scoreSet(
            reps: repResult,
            leftFootData: leftData,
            rightFootData: rightData,
            exerciseType: exerciseType
        )

        checkFormAlerts(quality: quality, exerciseType: exerciseType)
    }

    /// Finalize a completed set.
    private func finalizeSet(startTime: TimeInterval, endTime: TimeInterval) {
        guard var set = currentSet else { return }

        set.endTime = endTime

        let exerciseType = set.effectiveType
        let setDuration = endTime - startTime + 1.0
        let leftData = fusionEngine.getSourceWindow(source: .leftFoot, durationSeconds: setDuration)
        let rightData = fusionEngine.getSourceWindow(source: .rightFoot, durationSeconds: setDuration)
        let watchData = fusionEngine.getSourceWindow(source: .watch, durationSeconds: setDuration)

        let repResult: RepCountResult
        if !leftData.isEmpty {
            repResult = repCounter.countReps(source: .leftFoot, frames: leftData, exerciseType: exerciseType)
        } else if !rightData.isEmpty {
            repResult = repCounter.countReps(source: .rightFoot, frames: rightData, exerciseType: exerciseType)
        } else if !watchData.isEmpty {
            repResult = repCounter.countReps(source: .watch, frames: watchData, exerciseType: exerciseType)
        } else {
            repResult = .empty
        }

        set.repCount = repResult.count

        let quality = qualityScorer.scoreSet(
            reps: repResult,
            leftFootData: leftData,
            rightFootData: rightData,
            exerciseType: exerciseType
        )
        set.quality = quality

        completedSets.append(set)
        currentSet = nil
        lastRepCount = 0

        DispatchQueue.main.async { [weak self] in
            self?.currentRepCount = 0
            self?.currentExercise = .unknown
            self?.currentConfidence = 0
        }

        publishDetectedSets()
    }

    // MARK: - State Publishing

    private func publishDetectedSets() {
        var allSets = completedSets.enumerated().map { (idx, set) in
            set.toResult(index: idx)
        }

        if let current = currentSet {
            allSets.append(current.toResult(index: allSets.count))
        }

        DispatchQueue.main.async { [weak self] in
            self?.detectedSets = allSets
        }
    }

    private func emitMovementStateChange(_ state: SegmentState) {
        let newState: MovementState
        switch state {
        case .idle, .setComplete:
            newState = .idle
        case .active:
            newState = .active
        case .resting:
            newState = .resting
        }

        guard newState != lastEmittedState else { return }
        lastEmittedState = newState

        DispatchQueue.main.async { [weak self] in
            self?.movementState = newState
        }
    }

    // MARK: - Form Alerts

    /// Check quality metrics and emit form alerts when movement quality degrades.
    private func checkFormAlerts(quality: SetQuality, exerciseType: ExerciseType) {
        // Depth alert
        if quality.depthScore < 0.8 && quality.depthScore > 0 {
            let alert: FormAlert
            if quality.depthScore < 0.5 {
                alert = FormAlert(message: "Go deeper! Depth is well below target.", severity: .warning)
            } else {
                alert = FormAlert(message: "Try to go a bit deeper.", severity: .info)
            }
            DispatchQueue.main.async { [weak self] in
                self?.formAlert = alert
            }
        }

        // Tempo consistency alert
        if quality.tempoConsistency < 0.6 && quality.tempoConsistency > 0 {
            let alert = FormAlert(message: "Keep a steady rhythm.", severity: .info)
            DispatchQueue.main.async { [weak self] in
                self?.formAlert = alert
            }
        }

        // Symmetry alert (for bilateral exercises)
        let bilateralTypes: Set<ExerciseType> = [.alternatingLunges, .stepUps, .skaterHops]
        if bilateralTypes.contains(exerciseType) && quality.symmetryScore < 0.7 && quality.symmetryScore > 0 {
            let alert: FormAlert
            if quality.symmetryScore < 0.5 {
                alert = FormAlert(message: "Significant left/right imbalance detected.", severity: .warning)
            } else {
                alert = FormAlert(message: "Slight left/right imbalance. Focus on even effort.", severity: .info)
            }
            DispatchQueue.main.async { [weak self] in
                self?.formAlert = alert
            }
        }
    }
}

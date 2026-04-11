import Foundation
import Capacitor

// MARK: - Detected Set

/// Tracks a detected exercise set with its metadata.
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

    func toDictionary(index: Int) -> [String: Any] {
        var dict: [String: Any] = [
            "setIndex": index,
            "exerciseType": effectiveType.rawValue,
            "detectedType": exerciseType.rawValue,
            "confidence": confidence,
            "startTime": startTime,
            "repCount": effectiveReps,
            "detectedRepCount": repCount
        ]
        if let end = endTime {
            dict["endTime"] = end
            dict["durationSeconds"] = end - startTime
        }
        if let q = quality {
            dict["quality"] = q.toDictionary()
        }
        if userCorrectedType != nil {
            dict["userCorrected"] = true
        }
        return dict
    }
}

// MARK: - SensorEnginePlugin

/// Capacitor plugin that orchestrates the sensor inference pipeline.
/// Receives raw sensor data from the BLE plugin, processes it through
/// fusion, segmentation, classification, rep counting, and quality scoring,
/// then emits events to the web UI layer.
@objc(SensorEnginePlugin)
public class SensorEnginePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SensorEnginePlugin"
    public let jsName = "SensorEngine"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startProcessing", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopProcessing", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "ingestSamples", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSessionSummary", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "correctExerciseType", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "correctRepCount", returnType: CAPPluginReturnPromise),
    ]

    // MARK: - Pipeline Components

    private let fusionEngine = SensorFusionEngine()
    private let segmenter = SetSegmenter()
    private let classifier = MovementClassifier()
    private let repCounter = RepCounter()
    private let qualityScorer = QualityScorer()

    // MARK: - State

    private var processingQueue = DispatchQueue(label: "com.wod.sensorengine", qos: .userInitiated)
    private var processingTimer: DispatchSourceTimer?
    private var isProcessing = false

    /// All sets detected during this session.
    private var detectedSets: [DetectedSet] = []

    /// The current set being tracked (not yet completed).
    private var currentSet: DetectedSet?

    /// Last known rep count for detecting new reps.
    private var lastRepCount = 0

    /// Last emitted movement state, to avoid redundant events.
    private var lastEmittedState: String = "idle"

    /// Window duration (seconds) for the processing loop.
    private let analysisWindowSeconds: Double = 4.0

    /// Processing loop interval (seconds).
    private let processingIntervalSeconds: Double = 0.2

    // MARK: - Plugin Methods

    /// Start the background inference processing loop.
    @objc func startProcessing(_ call: CAPPluginCall) {
        guard !isProcessing else {
            call.resolve(["status": "already_running"])
            return
        }

        isProcessing = true
        lastRepCount = 0
        lastEmittedState = "idle"
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

        call.resolve(["status": "started"])
    }

    /// Stop the background inference processing loop.
    @objc func stopProcessing(_ call: CAPPluginCall) {
        isProcessing = false
        processingTimer?.cancel()
        processingTimer = nil

        // If there's an active set, finalize it
        if var current = currentSet {
            if let latestTime = fusionEngine.latestTimestamp() {
                current.endTime = latestTime
            }
            detectedSets.append(current)
            currentSet = nil
        }

        call.resolve(["status": "stopped"])
    }

    /// Receive sensor samples from the BLE plugin or watch and feed them into the fusion engine.
    /// Expected payload:
    ///   - source: "leftFoot" | "rightFoot" | "watch"
    ///   - samples: [{ timestamp, ax, ay, az, gx, gy, gz }]
    @objc func ingestSamples(_ call: CAPPluginCall) {
        guard let sourceStr = call.getString("source"),
              let source = SensorSource(rawValue: sourceStr) else {
            call.reject("Invalid or missing 'source'. Must be 'leftFoot', 'rightFoot', or 'watch'.")
            return
        }

        guard let samplesArray = call.getArray("samples") as? [[String: Any]] else {
            call.reject("Missing or invalid 'samples' array.")
            return
        }

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            for sampleDict in samplesArray {
                guard let timestamp = sampleDict["timestamp"] as? Double,
                      let ax = sampleDict["ax"] as? Double,
                      let ay = sampleDict["ay"] as? Double,
                      let az = sampleDict["az"] as? Double else {
                    continue
                }

                let gx = sampleDict["gx"] as? Double ?? 0.0
                let gy = sampleDict["gy"] as? Double ?? 0.0
                let gz = sampleDict["gz"] as? Double ?? 0.0

                let reading = SensorReading(ax: ax, ay: ay, az: az, gx: gx, gy: gy, gz: gz)
                self.fusionEngine.addSample(source: source, timestamp: timestamp, reading: reading)
            }
        }

        call.resolve(["ingested": samplesArray.count])
    }

    /// Return a summary of all detected sets for the current session.
    @objc func getSessionSummary(_ call: CAPPluginCall) {
        processingQueue.async { [weak self] in
            guard let self = self else {
                call.resolve(["sets": []])
                return
            }

            var allSets = self.detectedSets.enumerated().map { (idx, set) in
                set.toDictionary(index: idx)
            }

            // Include the current active set if one exists
            if let current = self.currentSet {
                allSets.append(current.toDictionary(index: allSets.count))
            }

            DispatchQueue.main.async {
                call.resolve([
                    "sets": allSets,
                    "totalSets": allSets.count,
                    "isActive": self.isProcessing
                ])
            }
        }
    }

    /// User correction: override the detected exercise type for a specific set.
    /// Payload: { setIndex: Int, exerciseType: String }
    @objc func correctExerciseType(_ call: CAPPluginCall) {
        guard let setIndex = call.getInt("setIndex"),
              let typeStr = call.getString("exerciseType"),
              let correctedType = ExerciseType(rawValue: typeStr) else {
            call.reject("Missing 'setIndex' or valid 'exerciseType'.")
            return
        }

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            if setIndex < self.detectedSets.count {
                self.detectedSets[setIndex].userCorrectedType = correctedType
                DispatchQueue.main.async {
                    call.resolve(["corrected": true, "setIndex": setIndex, "exerciseType": typeStr])
                }
            } else if let _ = self.currentSet, setIndex == self.detectedSets.count {
                self.currentSet?.userCorrectedType = correctedType
                DispatchQueue.main.async {
                    call.resolve(["corrected": true, "setIndex": setIndex, "exerciseType": typeStr])
                }
            } else {
                DispatchQueue.main.async {
                    call.reject("Set index \(setIndex) out of range.")
                }
            }
        }
    }

    /// User correction: override the detected rep count for a specific set.
    /// Payload: { setIndex: Int, repCount: Int }
    @objc func correctRepCount(_ call: CAPPluginCall) {
        guard let setIndex = call.getInt("setIndex"),
              let correctedCount = call.getInt("repCount") else {
            call.reject("Missing 'setIndex' or 'repCount'.")
            return
        }

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            if setIndex < self.detectedSets.count {
                self.detectedSets[setIndex].userCorrectedReps = correctedCount
                DispatchQueue.main.async {
                    call.resolve(["corrected": true, "setIndex": setIndex, "repCount": correctedCount])
                }
            } else if let _ = self.currentSet, setIndex == self.detectedSets.count {
                self.currentSet?.userCorrectedReps = correctedCount
                DispatchQueue.main.async {
                    call.resolve(["corrected": true, "setIndex": setIndex, "repCount": correctedCount])
                }
            } else {
                DispatchQueue.main.async {
                    call.reject("Set index \(setIndex) out of range.")
                }
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
            // Nothing to do
            break

        case .active(let startTime):
            processActiveState(startTime: startTime)

        case .resting:
            // Keep the current set alive but don't update reps
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
            emitSetStarted(classification: classification, startTime: startTime)
        } else {
            // Update classification if confidence improves
            if classification.confidence > (currentSet?.confidence ?? 0) {
                currentSet?.exerciseType = classification.exerciseType
                currentSet?.confidence = classification.confidence
            }
        }

        // Count reps from the primary foot sensor
        let exerciseType = currentSet?.effectiveType ?? classification.exerciseType

        // Try left foot first, then right, then watch
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

        // Update rep count and emit events for new reps
        if repResult.count > lastRepCount {
            currentSet?.repCount = repResult.count
            lastRepCount = repResult.count

            emitRepDetected(
                repCount: repResult.count,
                exerciseType: exerciseType,
                confidence: repResult.confidence
            )
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

    /// Finalize a completed set and emit the completion event.
    private func finalizeSet(startTime: TimeInterval, endTime: TimeInterval) {
        guard var set = currentSet else { return }

        set.endTime = endTime

        // Final rep count and quality scoring
        let exerciseType = set.effectiveType
        let leftData = fusionEngine.getSourceWindow(source: .leftFoot, durationSeconds: endTime - startTime + 1.0)
        let rightData = fusionEngine.getSourceWindow(source: .rightFoot, durationSeconds: endTime - startTime + 1.0)
        let watchData = fusionEngine.getSourceWindow(source: .watch, durationSeconds: endTime - startTime + 1.0)

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

        let setIndex = detectedSets.count
        detectedSets.append(set)
        currentSet = nil
        lastRepCount = 0

        emitSetCompleted(set: set, setIndex: setIndex, quality: quality)
    }

    // MARK: - Event Emission

    private func emitRepDetected(repCount: Int, exerciseType: ExerciseType, confidence: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyListeners("repDetected", data: [
                "repCount": repCount,
                "exerciseName": exerciseType.rawValue,
                "confidence": confidence,
                "setIndex": (self?.detectedSets.count ?? 0)
            ])
        }
    }

    private func emitSetStarted(classification: ClassificationResult, startTime: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyListeners("setStarted", data: [
                "exerciseType": classification.exerciseType.rawValue,
                "confidence": classification.confidence,
                "startTime": startTime
            ])
        }
    }

    private func emitSetCompleted(set: DetectedSet, setIndex: Int, quality: SetQuality) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyListeners("setCompleted", data: [
                "exerciseType": set.effectiveType.rawValue,
                "reps": set.effectiveReps,
                "duration": (set.endTime ?? set.startTime) - set.startTime,
                "quality": quality.toDictionary(),
                "setIndex": setIndex
            ])
        }
    }

    private func emitMovementStateChange(_ state: SegmentState) {
        let stateString: String
        switch state {
        case .idle, .setComplete:
            stateString = "idle"
        case .active:
            stateString = "active"
        case .resting:
            stateString = "resting"
        }

        guard stateString != lastEmittedState else { return }
        lastEmittedState = stateString

        DispatchQueue.main.async { [weak self] in
            self?.notifyListeners("movementStateChanged", data: [
                "state": stateString
            ])
        }
    }

    private func emitFormAlert(message: String, severity: String) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyListeners("formAlert", data: [
                "message": message,
                "severity": severity
            ])
        }
    }

    // MARK: - Form Alerts

    /// Check quality metrics and emit form alerts when movement quality degrades.
    private func checkFormAlerts(quality: SetQuality, exerciseType: ExerciseType) {
        // Depth alert: if depth drops below 80% of expected
        if quality.depthScore < 0.8 && quality.depthScore > 0 {
            if quality.depthScore < 0.5 {
                emitFormAlert(message: "Go deeper! Depth is well below target.", severity: "warning")
            } else {
                emitFormAlert(message: "Try to go a bit deeper.", severity: "info")
            }
        }

        // Tempo consistency alert
        if quality.tempoConsistency < 0.6 && quality.tempoConsistency > 0 {
            emitFormAlert(message: "Keep a steady rhythm.", severity: "info")
        }

        // Symmetry alert (for bilateral exercises)
        let bilateralTypes: Set<ExerciseType> = [.alternatingLunges, .stepUps, .skaterHops]
        if bilateralTypes.contains(exerciseType) && quality.symmetryScore < 0.7 && quality.symmetryScore > 0 {
            if quality.symmetryScore < 0.5 {
                emitFormAlert(message: "Significant left/right imbalance detected.", severity: "warning")
            } else {
                emitFormAlert(message: "Slight left/right imbalance. Focus on even effort.", severity: "info")
            }
        }
    }
}

import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - Workout Phase

enum WorkoutPhase: String, Sendable {
    case idle
    case preWorkout
    case active
    case summary
}

// MARK: - WorkoutManager

@Observable
final class WorkoutManager {
    // MARK: State

    var phase: WorkoutPhase = .idle
    var currentSession: WorkoutSession?
    var elapsedSeconds: Int = 0
    var completedSets: [DetectedExerciseSet] = []

    // MARK: Private

    private var timerCancellable: AnyCancellable?
    private var healthKit = HealthKitService()
    private var inferenceObservation: AnyCancellable?

    // MARK: - Workout Lifecycle

    /// Begin a new workout session.
    func startWorkout(modelContext: ModelContext, sensorManager: SensorManager) {
        // Create a fresh session
        let session = WorkoutSession()
        session.sensorConfig = sensorManager.sensorConfig
        modelContext.insert(session)
        currentSession = session

        // Reset state
        completedSets = []
        elapsedSeconds = 0
        phase = .active

        // Start subsystems
        sensorManager.startSensorStream()
        healthKit.startWorkoutSession()

        // Start elapsed-time timer
        startTimer()
    }

    /// End the current workout, compute summaries, persist, and update trends.
    func endWorkout(modelContext: ModelContext, sensorManager: SensorManager) {
        // Stop subsystems
        sensorManager.stopSensorStream()
        healthKit.endWorkoutSession()
        stopTimer()

        guard let session = currentSession else {
            phase = .idle
            return
        }

        // Finalize session
        session.completedAt = Date()
        session.status = "completed"

        // Persist any remaining completed sets
        persistCompletedSets(session: session, modelContext: modelContext)

        // Compute overall confidence
        if !session.sets.isEmpty {
            let totalConfidence = session.sets.reduce(0.0) { $0 + $1.classifierConfidence }
            session.overallConfidence = totalConfidence / Double(session.sets.count)
        }

        // Generate summaries and update trends
        TrendService.generateSummaries(for: session, context: modelContext)
        TrendService.updateTrends(for: session, context: modelContext)

        // Save
        try? modelContext.save()

        phase = .summary
    }

    // MARK: - Corrections

    /// Correct the exercise type for a detected set.
    func correctExercise(setIndex: Int, newType: ExerciseType) {
        guard setIndex >= 0, setIndex < completedSets.count else { return }
        let set = completedSets[setIndex]
        set.exerciseType = newType.rawValue
        set.userCorrectedType = newType.rawValue
        set.wasUserCorrected = true
    }

    /// Adjust the rep count for a detected set.
    func correctRepCount(setIndex: Int, delta: Int) {
        guard setIndex >= 0, setIndex < completedSets.count else { return }
        let set = completedSets[setIndex]
        let current = set.repCountCorrected ?? set.repCountDetected
        let corrected = max(0, current + delta)
        set.repCountCorrected = corrected
        set.wasUserCorrected = true
    }

    /// Remove a set entirely.
    func deleteSet(setIndex: Int) {
        guard setIndex >= 0, setIndex < completedSets.count else { return }
        completedSets.remove(at: setIndex)
    }

    // MARK: - Inference Observation

    /// Call periodically or from a change handler to capture newly completed sets
    /// from the inference engine.
    func captureCompletedSets(from sensorManager: SensorManager) {
        let results = sensorManager.inferenceEngine.detectedSets
        for (index, result) in results.enumerated() {
            // Avoid duplicates by comparing sort order
            guard !completedSets.contains(where: { $0.sortOrder == index }) else { continue }

            let exerciseSet = DetectedExerciseSet(
                exerciseType: result.exerciseType,
                confidence: result.confidence,
                startTime: Date(timeIntervalSince1970: result.startTime),
                endTime: Date(timeIntervalSince1970: result.endTime ?? result.startTime),
                repCount: result.repCount,
                sortOrder: index
            )

            // Apply any user corrections from the inference engine
            if let correctedType = result.userCorrectedType {
                exerciseSet.userCorrectedType = correctedType.rawValue
                exerciseSet.wasUserCorrected = true
            }
            if let correctedReps = result.userCorrectedReps {
                exerciseSet.repCountCorrected = correctedReps
                exerciseSet.wasUserCorrected = true
            }

            completedSets.append(exerciseSet)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.elapsedSeconds += 1
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Persistence Helpers

    /// Attach all locally-tracked completed sets to the session and insert into the context.
    private func persistCompletedSets(session: WorkoutSession, modelContext: ModelContext) {
        for set in completedSets {
            set.session = session
            if !session.sets.contains(where: { $0.id == set.id }) {
                session.sets.append(set)
                modelContext.insert(set)
            }
        }
    }

    // MARK: - Formatted Time

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

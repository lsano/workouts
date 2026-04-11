import Foundation
import Combine

// MARK: - SensorManager

/// Coordinates the BLE sensor subsystem, watch connectivity, and inference engine.
/// Owns the data flow: sensors → inference → watch display.
@Observable
final class SensorManager {
    // MARK: Subsystems

    private(set) var bleManager = BLEManager()
    private(set) var watchConnector = WatchConnector()
    private(set) var inferenceEngine = InferenceEngine()

    // MARK: Convenience state (aggregated from subsystems)

    var leftFootConnected: Bool { bleManager.leftFoot?.connected ?? false }
    var rightFootConnected: Bool { bleManager.rightFoot?.connected ?? false }
    var watchConnected: Bool { watchConnector.isWatchReachable }
    var isScanning: Bool { bleManager.isScanning }
    var discoveredDevices: [DiscoveredDevice] { bleManager.discoveredDevices }

    // MARK: Computed

    var sensorConfig: SensorConfig {
        SensorConfig(
            leftFootConnected: leftFootConnected,
            rightFootConnected: rightFootConnected,
            watchConnected: watchConnected,
            leftFootDeviceId: bleManager.leftFoot?.id,
            rightFootDeviceId: bleManager.rightFoot?.id,
            sampleRateHz: 50
        )
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    init() {
        wireDataFlow()
    }

    // MARK: Scanning

    func startScanning() {
        bleManager.startScanning()
    }

    func stopScanning() {
        bleManager.stopScanning()
    }

    // MARK: Connection

    func connectDevice(id: String, side: SensorSide) {
        bleManager.connectDevice(id: id, side: side)
    }

    func disconnectDevice(id: String) {
        bleManager.disconnectDevice(id: id)
    }

    // MARK: Sensor Stream

    func startSensorStream() {
        bleManager.startSensorStream()
        inferenceEngine.startProcessing()
        watchConnector.performTimeSync()
    }

    func stopSensorStream() {
        bleManager.stopSensorStream()
        inferenceEngine.stopProcessing()
    }

    // MARK: Internal

    /// Wire callbacks so data flows:
    ///   BLE sensor data → InferenceEngine (via SensorSource mapping)
    ///   Watch sensor batch → InferenceEngine
    ///   Inference state changes → Watch for display
    private func wireDataFlow() {
        // BLE foot sensor data → inference engine
        bleManager.onSensorData = { [weak self] side, samples in
            let source: SensorSource = (side == .left) ? .leftFoot : .rightFoot
            self?.inferenceEngine.ingestSamples(source: source, samples: samples)
        }

        // Watch sensor data → inference engine
        watchConnector.onWatchSensorBatch = { [weak self] samples in
            self?.inferenceEngine.ingestSamples(source: .watch, samples: samples)
        }

        // Watch user actions → inference corrections
        watchConnector.onWatchAction = { [weak self] action, payload in
            self?.handleWatchAction(action, payload: payload)
        }

        // Inference state → watch display (observe Published properties)
        inferenceEngine.$currentRepCount
            .combineLatest(inferenceEngine.$currentExercise, inferenceEngine.$currentConfidence)
            .sink { [weak self] repCount, exercise, confidence in
                self?.watchConnector.sendRepUpdate(
                    repCount: repCount,
                    exerciseName: exercise.displayName,
                    confidence: confidence
                )
            }
            .store(in: &cancellables)

        inferenceEngine.$movementState
            .removeDuplicates()
            .sink { [weak self] state in
                self?.watchConnector.sendMovementState(state.rawValue)
            }
            .store(in: &cancellables)

        inferenceEngine.$formAlert
            .compactMap { $0 }
            .sink { [weak self] alert in
                self?.watchConnector.sendFormAlert(
                    message: alert.message,
                    severity: alert.severity.rawValue
                )
            }
            .store(in: &cancellables)
    }

    private func handleWatchAction(_ action: String, payload: [String: Any]?) {
        switch action {
        case "correctExercise":
            guard let typeName = payload?["exerciseType"] as? String,
                  let type = ExerciseType(rawValue: typeName),
                  let setIndex = payload?["setIndex"] as? Int else { return }
            inferenceEngine.correctExercise(setIndex: setIndex, type: type)
        case "adjustReps":
            guard let delta = payload?["delta"] as? Int,
                  let setIndex = payload?["setIndex"] as? Int else { return }
            let currentCount = inferenceEngine.currentRepCount
            inferenceEngine.correctRepCount(setIndex: setIndex, count: currentCount + delta)
        case "endWorkout":
            stopSensorStream()
        default:
            break
        }
    }
}

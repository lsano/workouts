import Foundation
import HealthKit
import WatchConnectivity
import CoreMotion

/// Exercise entry received from the iPhone for plan display and data entry.
struct WatchExerciseEntry: Identifiable {
    let id: String
    let name: String
    let notes: String?
    let sectionName: String
    var setsTotal: Int
    var setsCompleted: Int
    var lastReps: Int?
    var lastWeight: Int?
}

/// Manages workout state on the Apple Watch.
/// Receives updates from the iPhone app and runs the HealthKit workout session
/// locally on the watch for heart rate monitoring.
class WatchWorkoutManager: NSObject, ObservableObject, WCSessionDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {

    // MARK: - Published State

    @Published var isWorkoutActive = false
    @Published var workoutName: String = ""
    @Published var currentExercise: String = ""
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 0
    @Published var totalSets: Int = 0
    @Published var timerPhase: String = "idle" // "work", "rest", "idle"
    @Published var timeRemaining: Int = 0
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var elapsedSeconds: Int = 0
    @Published var exercises: [WatchExerciseEntry] = []

    // MARK: - Auto-Detection Published State

    @Published var autoRepCount: Int = 0
    @Published var autoExerciseName: String = ""
    @Published var autoConfidence: Double = 0
    @Published var formAlertMessage: String = ""
    @Published var formAlertVisible: Bool = false
    @Published var isAutoMode: Bool = false
    @Published var movementState: String = "idle" // idle, active, resting

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var workoutStartDate: Date?

    // MARK: - Motion Capture

    private let motionManager = CMMotionManager()
    private var sensorBuffer: [[String: Any]] = []
    private var sensorTimer: Timer?

    // MARK: - Init

    override init() {
        super.init()
        setupWatchConnectivity()
        requestHealthKitPermissions()
    }

    // MARK: - HealthKit Permissions

    private func requestHealthKitPermissions() {
        let typesToShare: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKWorkoutType.workoutType(),
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("[WODWatch] HealthKit auth error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    /// Receive workout state from the iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            if let isActive = message["isActive"] as? Bool {
                if isActive && !self.isWorkoutActive {
                    self.startWorkout()
                } else if !isActive && self.isWorkoutActive {
                    self.endWorkout()
                }
                self.isWorkoutActive = isActive
            }

            if let name = message["workoutName"] as? String { self.workoutName = name }
            if let exercise = message["currentExercise"] as? String { self.currentExercise = exercise }
            if let idx = message["currentExerciseIndex"] as? Int { self.currentExerciseIndex = idx }
            if let set = message["currentSet"] as? Int { self.currentSet = set }
            if let total = message["totalSets"] as? Int { self.totalSets = total }
            if let phase = message["timerPhase"] as? String { self.timerPhase = phase }
            if let time = message["timeRemaining"] as? Int { self.timeRemaining = time }

            // Parse exercise list if present
            if let exerciseList = message["exercises"] as? [[String: Any]] {
                self.exercises = exerciseList.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let name = dict["name"] as? String,
                          let sectionName = dict["sectionName"] as? String,
                          let setsTotal = dict["setsTotal"] as? Int,
                          let setsCompleted = dict["setsCompleted"] as? Int
                    else { return nil }
                    return WatchExerciseEntry(
                        id: id,
                        name: name,
                        notes: dict["notes"] as? String,
                        sectionName: sectionName,
                        setsTotal: setsTotal,
                        setsCompleted: setsCompleted,
                        lastReps: dict["lastReps"] as? Int,
                        lastWeight: dict["lastWeight"] as? Int
                    )
                }
            }

            // MARK: Auto-Detection Messages

            if let isAutoMode = message["isAutoMode"] as? Bool {
                self.isAutoMode = isAutoMode
            }

            if let messageType = message["type"] as? String {
                switch messageType {
                case "repUpdate":
                    if let reps = message["repCount"] as? Int { self.autoRepCount = reps }
                    if let name = message["exerciseName"] as? String { self.autoExerciseName = name }
                    if let confidence = message["confidence"] as? Double { self.autoConfidence = confidence }

                case "formAlert":
                    if let alertMsg = message["message"] as? String {
                        self.formAlertMessage = alertMsg
                        self.formAlertVisible = true
                        WKInterfaceDevice.current().play(.notification)
                        // Auto-hide after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            self?.formAlertVisible = false
                        }
                    }

                case "setTransition":
                    if let transitionType = message["transition"] as? String {
                        switch transitionType {
                        case "rest":
                            WKInterfaceDevice.current().play(.directionUp)
                        case "setStart":
                            WKInterfaceDevice.current().play(.start)
                        default:
                            WKInterfaceDevice.current().play(.click)
                        }
                    }

                case "movementState":
                    if let state = message["state"] as? String { self.movementState = state }

                default:
                    break
                }
            }
        }
    }

    /// Send actions back to the iPhone (set completed, pause, etc.)
    func sendAction(_ action: String, payload: [String: Any]? = nil) {
        guard WCSession.default.isReachable else { return }
        var message: [String: Any] = ["action": action]
        if let payload = payload { message["payload"] = payload }
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("[WODWatch] Send error: \(error.localizedDescription)")
        }
    }

    // MARK: - HealthKit Workout Session

    private func startWorkout() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder
            workoutStartDate = Date()

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }

            startTimer()
            startMotionCapture()
        } catch {
            print("[WODWatch] Failed to start workout: \(error.localizedDescription)")
        }
    }

    private func endWorkout() {
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.workoutBuilder?.finishWorkout { _, _ in }
        }
        workoutSession = nil
        workoutBuilder = nil
        stopTimer()
        stopMotionCapture()

        DispatchQueue.main.async {
            self.heartRate = 0
            self.activeCalories = 0
            self.elapsedSeconds = 0
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.workoutStartDate else { return }
            DispatchQueue.main.async {
                self.elapsedSeconds = Int(Date().timeIntervalSince(start))
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        // State tracking handled by WCSession messages
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[WODWatch] Workout session error: \(error.localizedDescription)")
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            let statistics = workoutBuilder.statistics(for: quantityType)

            DispatchQueue.main.async {
                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                    self.heartRate = statistics?.mostRecentQuantity()?.doubleValue(for: heartRateUnit) ?? 0

                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    let energyUnit = HKUnit.kilocalorie()
                    self.activeCalories = statistics?.sumQuantity()?.doubleValue(for: energyUnit) ?? 0

                default:
                    break
                }
            }
        }
    }

    // MARK: - Motion Capture

    private func startMotionCapture() {
        guard motionManager.isDeviceMotionAvailable else {
            print("[WODWatch] Device motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 0.01 // 100Hz
        let motionQueue = OperationQueue()
        motionQueue.name = "com.wod.motionCapture"
        motionQueue.maxConcurrentOperationCount = 1

        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            let sample: [String: Any] = [
                "timestamp": motion.timestamp,
                "ax": motion.userAcceleration.x,
                "ay": motion.userAcceleration.y,
                "az": motion.userAcceleration.z,
                "gx": motion.rotationRate.x,
                "gy": motion.rotationRate.y,
                "gz": motion.rotationRate.z,
            ]
            self.sensorBuffer.append(sample)
        }

        sensorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.flushSensorBuffer()
        }
    }

    private func stopMotionCapture() {
        motionManager.stopDeviceMotionUpdates()
        sensorTimer?.invalidate()
        sensorTimer = nil
        sensorBuffer.removeAll()
    }

    private func flushSensorBuffer() {
        guard !sensorBuffer.isEmpty else { return }
        guard WCSession.default.isReachable else { return }

        let batch = sensorBuffer
        sensorBuffer.removeAll()

        WCSession.default.sendMessage(["sensorBatch": batch], replyHandler: nil) { error in
            print("[WODWatch] Sensor send error: \(error.localizedDescription)")
        }
    }

    // MARK: - Form Alert

    func dismissFormAlert() {
        formAlertVisible = false
        formAlertMessage = ""
    }

    // MARK: - Helpers

    func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

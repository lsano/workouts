import Foundation
import HealthKit
import WatchConnectivity

/// Manages workout state on the Apple Watch.
/// Receives updates from the iPhone app and runs the HealthKit workout session
/// locally on the watch for heart rate monitoring.
class WatchWorkoutManager: NSObject, ObservableObject, WCSessionDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {

    // MARK: - Published State

    @Published var isWorkoutActive = false
    @Published var workoutName: String = ""
    @Published var currentExercise: String = ""
    @Published var currentSet: Int = 0
    @Published var totalSets: Int = 0
    @Published var timerPhase: String = "idle" // "work", "rest", "idle"
    @Published var timeRemaining: Int = 0
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var elapsedSeconds: Int = 0

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var workoutStartDate: Date?

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
            if let set = message["currentSet"] as? Int { self.currentSet = set }
            if let total = message["totalSets"] as? Int { self.totalSets = total }
            if let phase = message["timerPhase"] as? String { self.timerPhase = phase }
            if let time = message["timeRemaining"] as? Int { self.timeRemaining = time }
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

    // MARK: - Helpers

    func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

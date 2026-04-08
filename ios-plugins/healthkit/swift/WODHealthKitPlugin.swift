import Foundation
import Capacitor
import HealthKit
import WatchConnectivity

/// Capacitor plugin bridging HealthKit and WatchConnectivity to the web layer.
/// Register in AppDelegate or via Capacitor's plugin registration.
@objc(WODHealthKitPlugin)
public class WODHealthKitPlugin: CAPPlugin, CAPBridgedPlugin, WCSessionDelegate {
    public let identifier = "WODHealthKitPlugin"
    public let jsName = "WODHealthKit"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveWorkout", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startWorkoutSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endWorkoutSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getHeartRateSamples", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getRestingHeartRate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getHealthSummary", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendWorkoutStateToWatch", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isWatchAvailable", returnType: CAPPluginReturnPromise),
    ]

    private let healthStore = HKHealthStore()
    private var activeWorkoutSession: HKWorkoutSession?
    private var activeWorkoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartDate: Date?
    private var wcSession: WCSession?

    // MARK: - Plugin Lifecycle

    override public func load() {
        setupWatchConnectivity()
    }

    // MARK: - Availability

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["available": HKHealthStore.isHealthDataAvailable()])
    }

    // MARK: - Permissions

    @objc func requestPermissions(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.resolve(["granted": false])
            return
        }

        let readTypes = parseDataTypes(call.getArray("read", String.self) ?? [])
        let writeTypes = parseDataTypes(call.getArray("write", String.self) ?? [])

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            if let error = error {
                print("[WODHealthKit] Permission error: \(error.localizedDescription)")
            }
            call.resolve(["granted": success])
        }
    }

    @objc func checkPermissions(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.resolve(["granted": false])
            return
        }

        // HealthKit doesn't expose a direct "are all these granted" API,
        // so we check authorization status for each write type.
        let writeTypes = parseDataTypes(call.getArray("write", String.self) ?? [])
        let allGranted = writeTypes.allSatisfy { type in
            healthStore.authorizationStatus(for: type) == .sharingAuthorized
        }
        call.resolve(["granted": allGranted])
    }

    // MARK: - Save Completed Workout

    @objc func saveWorkout(_ call: CAPPluginCall) {
        guard let activityTypeStr = call.getString("activityType"),
              let startDateStr = call.getString("startDate"),
              let endDateStr = call.getString("endDate"),
              let startDate = ISO8601DateFormatter().date(from: startDateStr),
              let endDate = ISO8601DateFormatter().date(from: endDateStr) else {
            call.reject("Missing required workout fields")
            return
        }

        let activityType = mapActivityType(activityTypeStr)
        let totalEnergy = call.getDouble("totalEnergyBurned") ?? 0
        let metadata = call.getObject("metadata") as? [String: String] ?? [:]

        let energyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: totalEnergy)

        let workout = HKWorkout(
            activityType: activityType,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: totalEnergy > 0 ? energyBurned : nil,
            totalDistance: nil,
            metadata: metadata.isEmpty ? nil : metadata
        )

        healthStore.save(workout) { success, error in
            if let error = error {
                print("[WODHealthKit] Save workout error: \(error.localizedDescription)")
                call.resolve(["success": false])
            } else {
                call.resolve([
                    "success": success,
                    "workoutId": workout.uuid.uuidString
                ])
            }
        }
    }

    // MARK: - Live Workout Session (enables Apple Watch heart rate streaming)

    @objc func startWorkoutSession(_ call: CAPPluginCall) {
        guard let activityTypeStr = call.getString("activityType") else {
            call.reject("activityType is required")
            return
        }

        let activityType = mapActivityType(activityTypeStr)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            activeWorkoutSession = session
            activeWorkoutBuilder = builder
            workoutStartDate = Date()

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { success, error in
                if let error = error {
                    print("[WODHealthKit] Begin collection error: \(error.localizedDescription)")
                    call.reject("Failed to start workout session")
                } else {
                    call.resolve(["sessionId": session.currentActivity.uuid.uuidString])
                }
            }
        } catch {
            call.reject("Failed to create workout session: \(error.localizedDescription)")
        }
    }

    @objc func endWorkoutSession(_ call: CAPPluginCall) {
        guard let session = activeWorkoutSession, let builder = activeWorkoutBuilder else {
            call.reject("No active workout session")
            return
        }

        session.end()
        builder.endCollection(withEnd: Date()) { success, error in
            guard success else {
                call.reject("Failed to end collection: \(error?.localizedDescription ?? "unknown")")
                return
            }

            builder.finishWorkout { workout, error in
                self.activeWorkoutSession = nil
                self.activeWorkoutBuilder = nil
                self.workoutStartDate = nil

                if let error = error {
                    call.reject("Failed to finish workout: \(error.localizedDescription)")
                    return
                }

                var result: [String: Any] = ["success": true]
                if let workout = workout {
                    if let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
                        result["totalCalories"] = calories
                    }
                }
                call.resolve(result)
            }
        }
    }

    // MARK: - Heart Rate

    @objc func getHeartRateSamples(_ call: CAPPluginCall) {
        guard let startDateStr = call.getString("startDate"),
              let startDate = ISO8601DateFormatter().date(from: startDateStr) else {
            call.reject("startDate is required")
            return
        }

        let endDate: Date
        if let endStr = call.getString("endDate"),
           let parsed = ISO8601DateFormatter().date(from: endStr) {
            endDate = parsed
        } else {
            endDate = Date()
        }

        let limit = call.getInt("limit") ?? 100
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: limit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                print("[WODHealthKit] Heart rate query error: \(error.localizedDescription)")
                call.resolve(["samples": []])
                return
            }

            let results = (samples as? [HKQuantitySample] ?? []).map { sample -> [String: Any] in
                return [
                    "value": sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                    "timestamp": ISO8601DateFormatter().string(from: sample.startDate)
                ]
            }
            call.resolve(["samples": results])
        }

        healthStore.execute(query)
    }

    @objc func getRestingHeartRate(_ call: CAPPluginCall) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                call.resolve(["value": NSNull()])
                return
            }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            call.resolve(["value": bpm])
        }

        healthStore.execute(query)
    }

    // MARK: - Health Summary

    @objc func getHealthSummary(_ call: CAPPluginCall) {
        var summary: [String: Any] = [:]
        let group = DispatchGroup()

        // Active calories today
        group.enter()
        queryTodaySum(for: .activeEnergyBurned, unit: .kilocalorie()) { value in
            if let value = value { summary["activeCaloriesToday"] = value }
            group.leave()
        }

        // Workouts this week
        group.enter()
        queryWeekWorkoutCount { count in
            summary["workoutsThisWeek"] = count
            group.leave()
        }

        // Resting heart rate (latest)
        group.enter()
        let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let hrSort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let hrQuery = HKSampleQuery(sampleType: hrType, predicate: nil, limit: 1, sortDescriptors: [hrSort]) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                summary["restingHeartRate"] = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            group.leave()
        }
        healthStore.execute(hrQuery)

        // Body mass (latest)
        group.enter()
        let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let massSort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let massQuery = HKSampleQuery(sampleType: massType, predicate: nil, limit: 1, sortDescriptors: [massSort]) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                summary["bodyMass"] = sample.quantity.doubleValue(for: .pound())
            }
            group.leave()
        }
        healthStore.execute(massQuery)

        group.notify(queue: .main) {
            call.resolve(summary)
        }
    }

    // MARK: - Watch Connectivity

    @objc func sendWorkoutStateToWatch(_ call: CAPPluginCall) {
        guard let session = wcSession, session.isReachable else {
            call.resolve(["delivered": false])
            return
        }

        var state: [String: Any] = [:]
        if let isActive = call.getBool("isActive") { state["isActive"] = isActive }
        if let name = call.getString("workoutName") { state["workoutName"] = name }
        if let exercise = call.getString("currentExercise") { state["currentExercise"] = exercise }
        if let set = call.getInt("currentSet") { state["currentSet"] = set }
        if let total = call.getInt("totalSets") { state["totalSets"] = total }
        if let phase = call.getString("timerPhase") { state["timerPhase"] = phase }
        if let time = call.getInt("timeRemaining") { state["timeRemaining"] = time }

        session.sendMessage(state, replyHandler: { _ in
            call.resolve(["delivered": true])
        }, errorHandler: { error in
            print("[WODHealthKit] Watch send error: \(error.localizedDescription)")
            call.resolve(["delivered": false])
        })
    }

    @objc func isWatchAvailable(_ call: CAPPluginCall) {
        let supported = WCSession.isSupported()
        let paired = wcSession?.isPaired ?? false
        let reachable = wcSession?.isReachable ?? false
        call.resolve([
            "available": supported,
            "paired": paired,
            "reachable": reachable
        ])
    }

    // MARK: - WCSessionDelegate

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WODHealthKit] WCSession activation error: \(error.localizedDescription)")
        }
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Receive messages from the Apple Watch companion app
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        var payload: [String: Any] = ["action": action]
        if let data = message["payload"] as? [String: Any] {
            payload["payload"] = data
        }
        notifyListeners("watchMessage", data: payload)
    }

    // MARK: - Helpers

    private func parseDataTypes(_ types: [String]) -> Set<HKSampleType> {
        var result = Set<HKSampleType>()
        for type in types {
            switch type {
            case "activeEnergyBurned":
                if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { result.insert(t) }
            case "heartRate":
                if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { result.insert(t) }
            case "restingHeartRate":
                if let t = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { result.insert(t) }
            case "workout":
                result.insert(HKWorkoutType.workoutType())
            case "bodyMass":
                if let t = HKQuantityType.quantityType(forIdentifier: .bodyMass) { result.insert(t) }
            case "stepCount":
                if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { result.insert(t) }
            default:
                break
            }
        }
        return result
    }

    private func mapActivityType(_ str: String) -> HKWorkoutActivityType {
        switch str {
        case "traditionalStrengthTraining": return .traditionalStrengthTraining
        case "functionalStrengthTraining": return .functionalStrengthTraining
        case "highIntensityIntervalTraining": return .highIntensityIntervalTraining
        case "coreTraining": return .coreTraining
        case "flexibility": return .flexibility
        case "mixedCardio": return .mixedCardio
        default: return .other
        }
    }

    private func queryTodaySum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping (Double?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
            let value = statistics?.sumQuantity()?.doubleValue(for: unit)
            completion(value)
        }
        healthStore.execute(query)
    }

    private func queryWeekWorkoutCount(completion: @escaping (Int) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else {
            completion(0)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: now, options: .strictStartDate)
        let query = HKSampleQuery(
            sampleType: HKWorkoutType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            completion(samples?.count ?? 0)
        }
        healthStore.execute(query)
    }
}

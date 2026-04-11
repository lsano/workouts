import Foundation
import HealthKit
import Combine

// MARK: - HealthKitService

final class HealthKitService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var isSessionActive = false

    // MARK: - Private State

    private let healthStore = HKHealthStore()
    private var activeWorkoutSession: HKWorkoutSession?
    private var activeWorkoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartDate: Date?
    private var heartRateQuery: HKAnchoredObjectQuery?

    // MARK: - Public Methods

    /// Request authorization for the HealthKit data types used by this app.
    func requestPermissions(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?(false)
            return
        }

        var readTypes = Set<HKObjectType>()
        var writeTypes = Set<HKSampleType>()

        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(hr)
        }
        if let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            readTypes.insert(rhr)
        }
        if let cal = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(cal)
            writeTypes.insert(cal)
        }
        readTypes.insert(HKWorkoutType.workoutType())
        writeTypes.insert(HKWorkoutType.workoutType())

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            if let error = error {
                print("[HealthKitService] Permission error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }

    /// Start a live workout session for heart rate streaming and calorie tracking.
    func startWorkoutSession(
        activityType: HKWorkoutActivityType = .traditionalStrengthTraining,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            activeWorkoutSession = session
            activeWorkoutBuilder = builder
            workoutStartDate = Date()

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.isSessionActive = true
                        self?.startHeartRateStream()
                    }
                    completion?(success, error)
                }
            }
        } catch {
            completion?(false, error)
        }
    }

    /// End the active workout session and finalize the data.
    func endWorkoutSession(completion: ((Bool, HKWorkout?, Error?) -> Void)? = nil) {
        guard let session = activeWorkoutSession, let builder = activeWorkoutBuilder else {
            completion?(false, nil, nil)
            return
        }

        stopHeartRateStream()
        session.end()

        builder.endCollection(withEnd: Date()) { success, error in
            guard success else {
                DispatchQueue.main.async {
                    completion?(false, nil, error)
                }
                return
            }

            builder.finishWorkout { [weak self] workout, error in
                DispatchQueue.main.async {
                    self?.activeWorkoutSession = nil
                    self?.activeWorkoutBuilder = nil
                    self?.workoutStartDate = nil
                    self?.isSessionActive = false
                    self?.heartRate = 0
                    self?.activeCalories = 0

                    if let error = error {
                        completion?(false, nil, error)
                    } else {
                        completion?(true, workout, nil)
                    }
                }
            }
        }
    }

    /// Save a completed workout to HealthKit (for workouts tracked outside a live session).
    func saveWorkout(
        activityType: HKWorkoutActivityType,
        startDate: Date,
        endDate: Date,
        totalEnergyBurned: Double?,
        metadata: [String: String]? = nil,
        completion: ((Bool, String?) -> Void)? = nil
    ) {
        var energyBurned: HKQuantity?
        if let cal = totalEnergyBurned, cal > 0 {
            energyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: cal)
        }

        let workout = HKWorkout(
            activityType: activityType,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: energyBurned,
            totalDistance: nil,
            metadata: metadata
        )

        healthStore.save(workout) { success, error in
            if let error = error {
                print("[HealthKitService] Save workout error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion?(success, success ? workout.uuid.uuidString : nil)
            }
        }
    }

    // MARK: - Heart Rate Streaming

    private func startHeartRateStream() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let predicate = HKQuery.predicateForSamples(
            withStart: workoutStartDate ?? Date(),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }

        heartRateQuery = query
        healthStore.execute(query)
    }

    private func stopHeartRateStream() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latest = quantitySamples.last else { return }

        let bpm = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

        DispatchQueue.main.async { [weak self] in
            self?.heartRate = bpm
        }
    }

    // MARK: - Query Helpers

    /// Query today's total active calories burned.
    func queryTodayActiveCalories(completion: @escaping (Double?) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(nil)
            return
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, _ in
            let value = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
            DispatchQueue.main.async {
                completion(value)
            }
        }
        healthStore.execute(query)
    }

    /// Query the most recent resting heart rate.
    func queryRestingHeartRate(completion: @escaping (Double?) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            completion(nil)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(nil)
                return
            }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            DispatchQueue.main.async {
                completion(bpm)
            }
        }
        healthStore.execute(query)
    }

    /// Query the number of workouts recorded in the past 7 days.
    func queryWeekWorkoutCount(completion: @escaping (Int) -> Void) {
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
            DispatchQueue.main.async {
                completion(samples?.count ?? 0)
            }
        }
        healthStore.execute(query)
    }

    /// Map a string activity type to HKWorkoutActivityType.
    static func mapActivityType(_ str: String) -> HKWorkoutActivityType {
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
}

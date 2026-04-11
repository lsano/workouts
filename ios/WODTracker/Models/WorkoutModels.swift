import Foundation
import SwiftData

// MARK: - Exercise Catalog

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case jumpRope = "jump_rope"
    case pogoHops = "pogo_hops"
    case alternatingLunges = "alternating_lunges"
    case stepUps = "step_ups"
    case skaterHops = "skater_hops"
    case agilityLadder = "agility_ladder"
    case boxJumps = "box_jumps"
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jumpRope: return "Jump Rope"
        case .pogoHops: return "Pogo Hops"
        case .alternatingLunges: return "Alternating Lunges"
        case .stepUps: return "Step-Ups"
        case .skaterHops: return "Skater Hops"
        case .agilityLadder: return "Agility Ladder"
        case .boxJumps: return "Box Jumps"
        case .unknown: return "Unknown"
        }
    }

    var tier: Int {
        switch self {
        case .jumpRope, .pogoHops, .alternatingLunges, .stepUps: return 1
        case .skaterHops, .agilityLadder, .boxJumps: return 2
        case .unknown: return 0
        }
    }

    var isBilateral: Bool {
        switch self {
        case .alternatingLunges, .stepUps, .skaterHops: return true
        default: return false
        }
    }
}

enum MovementState: String, Codable {
    case idle, active, resting
}

enum ConfidenceLevel {
    case high, medium, low

    init(score: Double) {
        if score >= 0.8 { self = .high }
        else if score >= 0.5 { self = .medium }
        else { self = .low }
    }
}

// MARK: - Sensor Configuration

struct SensorConfig: Codable {
    var leftFootConnected: Bool
    var rightFootConnected: Bool
    var watchConnected: Bool
    var leftFootDeviceId: String?
    var rightFootDeviceId: String?
    var sampleRateHz: Int

    static let disconnected = SensorConfig(
        leftFootConnected: false,
        rightFootConnected: false,
        watchConnected: false,
        sampleRateHz: 50
    )
}

// MARK: - Quality Metrics

struct SetQualityMetrics: Codable {
    var avgTempo: Double           // ms per rep
    var tempoConsistency: Double   // 0-1
    var symmetryScore: Double      // 0-1
    var depthScore: Double         // 0-1
    var depthConsistency: Double   // 0-1
    var overallQuality: Double     // 0-1 weighted average
}

struct RepQualityMetrics: Codable {
    var tempoMs: Int
    var depthScore: Double
    var symmetryScore: Double
    var stabilityScore: Double
}

// MARK: - SwiftData Models

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var completedAt: Date?
    var status: String  // "active", "paused", "completed"
    var sensorConfigData: Data?  // Encoded SensorConfig
    var overallConfidence: Double?
    var notes: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \DetectedExerciseSet.session)
    var sets: [DetectedExerciseSet]

    @Relationship(deleteRule: .cascade, inverse: \SensorRecording.session)
    var recordings: [SensorRecording]

    init() {
        self.id = UUID()
        self.startedAt = Date()
        self.status = "active"
        self.createdAt = Date()
        self.sets = []
        self.recordings = []
    }

    var sensorConfig: SensorConfig {
        get {
            guard let data = sensorConfigData else { return .disconnected }
            return (try? JSONDecoder().decode(SensorConfig.self, from: data)) ?? .disconnected
        }
        set {
            sensorConfigData = try? JSONEncoder().encode(newValue)
        }
    }

    var duration: TimeInterval {
        let end = completedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    var totalReps: Int {
        sets.reduce(0) { $0 + ($1.repCountCorrected ?? $1.repCountDetected) }
    }

    var totalSets: Int { sets.count }
}

@Model
final class DetectedExerciseSet {
    @Attribute(.unique) var id: UUID
    var session: WorkoutSession?
    var exerciseType: String        // ExerciseType.rawValue
    var detectedType: String?       // Original classifier output
    var classifierConfidence: Double
    var startTime: Date
    var endTime: Date
    var durationSeconds: Double
    var repCountDetected: Int
    var repCountCorrected: Int?
    var wasUserCorrected: Bool
    var userCorrectedType: String?
    var sourceMode: String          // "wearables_only" or "wearables_plus_camera"
    var qualityData: Data?          // Encoded SetQualityMetrics
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \RepEvent.exerciseSet)
    var reps: [RepEvent]

    init(
        exerciseType: ExerciseType,
        confidence: Double,
        startTime: Date,
        endTime: Date,
        repCount: Int,
        sortOrder: Int
    ) {
        self.id = UUID()
        self.exerciseType = exerciseType.rawValue
        self.detectedType = exerciseType.rawValue
        self.classifierConfidence = confidence
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = endTime.timeIntervalSince(startTime)
        self.repCountDetected = repCount
        self.wasUserCorrected = false
        self.sourceMode = "wearables_only"
        self.sortOrder = sortOrder
        self.reps = []
    }

    var exercise: ExerciseType {
        ExerciseType(rawValue: exerciseType) ?? .unknown
    }

    var quality: SetQualityMetrics? {
        get {
            guard let data = qualityData else { return nil }
            return try? JSONDecoder().decode(SetQualityMetrics.self, from: data)
        }
        set {
            qualityData = try? JSONEncoder().encode(newValue)
        }
    }

    var effectiveRepCount: Int {
        repCountCorrected ?? repCountDetected
    }
}

@Model
final class RepEvent {
    @Attribute(.unique) var id: UUID
    var exerciseSet: DetectedExerciseSet?
    var repIndex: Int
    var timestamp: Date
    var durationMs: Int?
    var repConfidence: Double
    var leftRightPattern: String?   // "left", "right", "both"
    var tempoMs: Int?
    var qualityScore: Double?
    var symmetryScore: Double?
    var depthScore: Double?
    var stabilityScore: Double?

    init(repIndex: Int, timestamp: Date) {
        self.id = UUID()
        self.repIndex = repIndex
        self.timestamp = timestamp
        self.repConfidence = 1.0
    }
}

@Model
final class SensorDevice {
    @Attribute(.unique) var id: UUID
    var type: String            // "foot_sensor", "watch"
    var side: String?           // "left", "right"
    var name: String
    var firmware: String?
    var peripheralId: String?   // BLE peripheral UUID
    var lastSeenAt: Date?

    init(name: String, type: String, side: String? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.side = side
    }
}

@Model
final class SensorRecording {
    @Attribute(.unique) var id: UUID
    var session: WorkoutSession?
    var source: String          // "left_foot", "right_foot", "watch"
    var startTime: Date
    var sampleRateHz: Int
    var sampleCount: Int
    var data: Data?             // Compressed binary sensor data

    init(source: String, sampleRateHz: Int) {
        self.id = UUID()
        self.source = source
        self.startTime = Date()
        self.sampleRateHz = sampleRateHz
        self.sampleCount = 0
    }
}

@Model
final class TrendAggregate {
    @Attribute(.unique) var id: UUID
    var exerciseType: String
    var dateBucket: String      // ISO date "2026-04-11"
    var totalSessions: Int
    var totalSets: Int
    var totalReps: Int
    var avgRepsPerSet: Double?
    var avgTempo: Double?
    var avgSymmetry: Double?
    var avgQuality: Double?
    var avgFatigueDropoff: Double?
    var updatedAt: Date

    init(exerciseType: ExerciseType, dateBucket: String) {
        self.id = UUID()
        self.exerciseType = exerciseType.rawValue
        self.dateBucket = dateBucket
        self.totalSessions = 0
        self.totalSets = 0
        self.totalReps = 0
        self.updatedAt = Date()
    }
}

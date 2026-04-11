import Foundation
import SwiftData

// MARK: - Trend Period

enum TrendPeriod: String, CaseIterable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }

    var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}

// MARK: - TrendService

enum TrendService {

    // MARK: - Generate Summaries

    /// Compute and store per-set quality summaries after a workout completes.
    static func generateSummaries(for session: WorkoutSession, context: ModelContext) {
        for set in session.sets {
            guard !set.reps.isEmpty else { continue }

            let reps = set.reps.sorted { $0.repIndex < $1.repIndex }

            // Compute average tempo
            let tempos = reps.compactMap { $0.tempoMs }
            let avgTempo: Double = tempos.isEmpty ? 0 : Double(tempos.reduce(0, +)) / Double(tempos.count)

            // Tempo consistency: 1 - (stddev / mean), clamped to [0,1]
            let tempoConsistency: Double = {
                guard tempos.count > 1, avgTempo > 0 else { return 0 }
                let mean = avgTempo
                let variance = tempos.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(tempos.count)
                let stddev = sqrt(variance)
                return max(0, min(1, 1.0 - (stddev / mean)))
            }()

            // Average symmetry
            let symmetryScores = reps.compactMap { $0.symmetryScore }
            let avgSymmetry: Double = symmetryScores.isEmpty
                ? 1.0
                : symmetryScores.reduce(0, +) / Double(symmetryScores.count)

            // Average depth
            let depthScores = reps.compactMap { $0.depthScore }
            let avgDepth: Double = depthScores.isEmpty
                ? 1.0
                : depthScores.reduce(0, +) / Double(depthScores.count)

            // Depth consistency
            let depthConsistency: Double = {
                guard depthScores.count > 1, avgDepth > 0 else { return 0 }
                let variance = depthScores.map { pow($0 - avgDepth, 2) }.reduce(0, +) / Double(depthScores.count)
                let stddev = sqrt(variance)
                return max(0, min(1, 1.0 - (stddev / avgDepth)))
            }()

            // Weighted overall quality
            let overall = 0.3 * tempoConsistency + 0.25 * avgSymmetry + 0.25 * avgDepth + 0.2 * depthConsistency

            let metrics = SetQualityMetrics(
                avgTempo: avgTempo,
                tempoConsistency: tempoConsistency,
                symmetryScore: avgSymmetry,
                depthScore: avgDepth,
                depthConsistency: depthConsistency,
                overallQuality: overall
            )
            set.quality = metrics
        }
    }

    // MARK: - Update Trends

    /// Aggregate session data into per-exercise, per-day trend buckets.
    static func updateTrends(for session: WorkoutSession, context: ModelContext) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateBucket = dateFormatter.string(from: session.startedAt)

        // Group sets by exercise type
        var grouped: [ExerciseType: [DetectedExerciseSet]] = [:]
        for set in session.sets {
            let type = set.exercise
            grouped[type, default: []].append(set)
        }

        for (exerciseType, sets) in grouped {
            // Try to find an existing aggregate for this exercise + date
            let typeRaw = exerciseType.rawValue
            var descriptor = FetchDescriptor<TrendAggregate>(
                predicate: #Predicate<TrendAggregate> {
                    $0.exerciseType == typeRaw && $0.dateBucket == dateBucket
                }
            )
            descriptor.fetchLimit = 1

            let existing = (try? context.fetch(descriptor))?.first

            let aggregate: TrendAggregate
            if let existing {
                aggregate = existing
            } else {
                aggregate = TrendAggregate(exerciseType: exerciseType, dateBucket: dateBucket)
                context.insert(aggregate)
            }

            // Accumulate
            aggregate.totalSessions += 1
            aggregate.totalSets += sets.count
            let reps = sets.reduce(0) { $0 + $1.effectiveRepCount }
            aggregate.totalReps += reps

            if aggregate.totalSets > 0 {
                aggregate.avgRepsPerSet = Double(aggregate.totalReps) / Double(aggregate.totalSets)
            }

            // Average quality metrics across sets that have them
            let qualities = sets.compactMap { $0.quality }
            if !qualities.isEmpty {
                let count = Double(qualities.count)
                aggregate.avgTempo = qualities.map(\.avgTempo).reduce(0, +) / count
                aggregate.avgSymmetry = qualities.map(\.symmetryScore).reduce(0, +) / count
                aggregate.avgQuality = qualities.map(\.overallQuality).reduce(0, +) / count
            }

            aggregate.updatedAt = Date()
        }
    }

    // MARK: - Fetch Trends

    /// Fetch trend aggregates for a specific exercise type within a time period.
    static func fetchTrends(
        exerciseType: ExerciseType?,
        period: TrendPeriod,
        context: ModelContext
    ) -> [TrendAggregate] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let cutoffString = dateFormatter.string(from: period.startDate)

        var descriptor: FetchDescriptor<TrendAggregate>

        if let exerciseType {
            let typeRaw = exerciseType.rawValue
            descriptor = FetchDescriptor<TrendAggregate>(
                predicate: #Predicate<TrendAggregate> {
                    $0.exerciseType == typeRaw && $0.dateBucket >= cutoffString
                },
                sortBy: [SortDescriptor(\.dateBucket, order: .forward)]
            )
        } else {
            descriptor = FetchDescriptor<TrendAggregate>(
                predicate: #Predicate<TrendAggregate> {
                    $0.dateBucket >= cutoffString
                },
                sortBy: [SortDescriptor(\.dateBucket, order: .forward)]
            )
        }

        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch trends for all exercise types, grouped into a dictionary.
    static func fetchAllExerciseTrends(
        period: TrendPeriod,
        context: ModelContext
    ) -> [ExerciseType: [TrendAggregate]] {
        let all = fetchTrends(exerciseType: nil, period: period, context: context)
        var result: [ExerciseType: [TrendAggregate]] = [:]
        for aggregate in all {
            let type = ExerciseType(rawValue: aggregate.exerciseType) ?? .unknown
            result[type, default: []].append(aggregate)
        }
        return result
    }
}

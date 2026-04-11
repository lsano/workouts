import Foundation
import SwiftData

enum PersistenceController {

    /// Fetch the most recent completed workout sessions, ordered by start date descending.
    static func recentWorkouts(limit: Int, context: ModelContext) -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Count how many workouts were started within the current calendar week.
    static func workoutsThisWeek(context: ModelContext) -> Int {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return 0
        }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> {
                $0.startedAt >= weekStart
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Total number of workout sessions ever recorded.
    static func totalWorkouts(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<WorkoutSession>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Number of workout sessions with status "completed".
    static func completedWorkouts(context: ModelContext) -> Int {
        let completedStatus = "completed"
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> {
                $0.status == completedStatus
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}

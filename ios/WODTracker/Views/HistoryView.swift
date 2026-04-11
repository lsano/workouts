import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                quickStatsRow
                workoutList
            }
            .padding()
        }
        .navigationTitle("History")
        .overlay {
            if sessions.isEmpty {
                emptyState
            }
        }
    }

    // MARK: - Quick Stats

    private var quickStatsRow: some View {
        HStack(spacing: 12) {
            quickStat(value: "\(sessions.count)", label: "Total", icon: "number")
            quickStat(
                value: "\(sessions.filter { $0.status == "completed" }.count)",
                label: "Completed",
                icon: "checkmark.circle"
            )
            quickStat(value: "\(thisWeekCount)", label: "This Week", icon: "calendar")
        }
    }

    private func quickStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.accentColor)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Workout List

    private var workoutList: some View {
        let grouped = groupedSessions

        return LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
            ForEach(grouped.keys.sorted().reversed(), id: \.self) { dateKey in
                Section {
                    ForEach(grouped[dateKey] ?? []) { session in
                        NavigationLink {
                            WorkoutDetailView(session: session)
                        } label: {
                            workoutCard(session)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(sectionHeader(for: dateKey))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func workoutCard(_ session: WorkoutSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Workout")
                        .font(.headline)
                    statusBadge(session.status)
                }

                HStack(spacing: 12) {
                    Label("\(session.totalSets) sets", systemImage: "number")
                    Label("\(session.totalReps) reps", systemImage: "arrow.up.arrow.down")
                    Label(formatDuration(session.duration), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "completed": .green
        case "active": .blue
        case "paused": .yellow
        default: .gray
        }

        return Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Workouts Yet")
                .font(.title3)
                .fontWeight(.medium)
            Text("Complete your first workout to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink {
                LiveWorkoutView()
            } label: {
                Text("Start a Workout")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.accentColor)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private var thisWeekCount: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return sessions.filter { $0.startedAt >= startOfWeek }.count
    }

    private var groupedSessions: [String: [WorkoutSession]] {
        Dictionary(grouping: sessions) { session in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: session.startedAt)
        }
    }

    private func sectionHeader(for dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateKey) else { return dateKey }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: WorkoutSession.self, inMemory: true)
}

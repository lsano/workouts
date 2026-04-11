import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    var sensorConfig: SensorConfig = .disconnected

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    startWorkoutButton
                    sensorStatusRow
                    recentWorkoutCard
                    navigationGrid
                }
                .padding()
            }
            .navigationTitle("WOD Tracker")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Auto-detect exercises, count reps, track progress")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Start Workout

    private var startWorkoutButton: some View {
        NavigationLink {
            LiveWorkoutView()
        } label: {
            Label("Start Workout", systemImage: "figure.run")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
    }

    // MARK: - Sensor Status

    private var sensorStatusRow: some View {
        HStack(spacing: 20) {
            sensorIndicator(
                label: "Left Foot",
                systemImage: "shoe.fill",
                connected: sensorConfig.leftFootConnected
            )
            sensorIndicator(
                label: "Right Foot",
                systemImage: "shoe.fill",
                connected: sensorConfig.rightFootConnected
            )
            sensorIndicator(
                label: "Watch",
                systemImage: "applewatch",
                connected: sensorConfig.watchConnected
            )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sensorIndicator(label: String, systemImage: String, connected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(connected ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(connected ? .green : .gray)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Circle()
                .fill(connected ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent Workout

    private var recentWorkoutCard: some View {
        Group {
            if let last = sessions.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text("Last Workout")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(last.startedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 20) {
                        statItem(value: "\(last.totalSets)", label: "Sets")
                        statItem(value: "\(last.totalReps)", label: "Reps")
                        statItem(
                            value: formatDuration(last.duration),
                            label: "Duration"
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Navigation Grid

    private var navigationGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            NavigationLink {
                TrendsView()
            } label: {
                navCard(title: "Trends", systemImage: "chart.line.uptrend.xyaxis", color: .blue)
            }

            NavigationLink {
                HistoryView()
            } label: {
                navCard(title: "History", systemImage: "calendar", color: .purple)
            }

            NavigationLink {
                SensorDebugView()
            } label: {
                navCard(title: "Sensors", systemImage: "sensor.fill", color: .orange)
            }
        }
    }

    private func navCard(title: String, systemImage: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}

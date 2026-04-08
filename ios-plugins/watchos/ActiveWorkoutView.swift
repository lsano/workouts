import SwiftUI

/// The main workout view displayed on Apple Watch during an active session.
/// Shows timer, current exercise, heart rate, and set logging controls.
struct ActiveWorkoutView: View {
    @ObservedObject var manager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Timer / Phase indicator
                timerSection

                Divider()

                // Current exercise
                exerciseSection

                Divider()

                // Heart rate & calories
                metricsSection

                Divider()

                // Quick actions
                actionsSection
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("WOD")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Timer

    private var timerSection: some View {
        VStack(spacing: 4) {
            Text(phaseLabel)
                .font(.caption2)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundColor(phaseColor)

            if manager.timeRemaining > 0 {
                Text("\(manager.timeRemaining)")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(phaseColor)
            }

            Text(manager.formatTime(manager.elapsedSeconds))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var phaseLabel: String {
        switch manager.timerPhase {
        case "work": return "Work"
        case "rest": return "Rest"
        default: return "Active"
        }
    }

    private var phaseColor: Color {
        switch manager.timerPhase {
        case "work": return .red
        case "rest": return .green
        default: return .blue
        }
    }

    // MARK: - Exercise

    private var exerciseSection: some View {
        VStack(spacing: 2) {
            Text(manager.currentExercise.isEmpty ? "Ready" : manager.currentExercise)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if manager.totalSets > 0 {
                Text("Set \(manager.currentSet) / \(manager.totalSets)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        HStack(spacing: 16) {
            // Heart rate
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.caption2)
                    Text("\(Int(manager.heartRate))")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Text("BPM")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Calories
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("\(Int(manager.activeCalories))")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Text("CAL")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 8) {
            // Complete set button (big, easy to tap)
            Button(action: {
                WKInterfaceDevice.current().play(.click)
                manager.sendAction("completeSet")
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Set Done")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // End workout
            Button(action: {
                manager.sendAction("endWorkout")
            }) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("End")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}

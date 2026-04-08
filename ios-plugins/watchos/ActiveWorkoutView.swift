import SwiftUI

/// The main workout view displayed on Apple Watch during an active session.
/// Shows timer, current exercise, heart rate, and set logging controls.
/// Tap the exercise name to open set input. Tap "Plan" to see all exercises.
struct ActiveWorkoutView: View {
    @ObservedObject var manager: WatchWorkoutManager
    @State private var showingSetInput = false
    @State private var showingPlan = false

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
        .sheet(isPresented: $showingSetInput) {
            SetInputView(manager: manager, exerciseIndex: manager.currentExerciseIndex)
        }
        .sheet(isPresented: $showingPlan) {
            NavigationStack {
                WorkoutPlanView(manager: manager)
            }
        }
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
            // Tappable exercise name — opens set input
            Button(action: { showingSetInput = true }) {
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

                    Text("Tap to log reps")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)

            // Exercise navigation
            if manager.exercises.count > 1 {
                HStack(spacing: 16) {
                    Button(action: {
                        let prev = max(0, manager.currentExerciseIndex - 1)
                        manager.sendAction("navigateExercise", payload: ["index": prev])
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.currentExerciseIndex <= 0)
                    .opacity(manager.currentExerciseIndex <= 0 ? 0.3 : 1)

                    Text("\(manager.currentExerciseIndex + 1)/\(manager.exercises.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button(action: {
                        let next = min(manager.exercises.count - 1, manager.currentExerciseIndex + 1)
                        manager.sendAction("navigateExercise", payload: ["index": next])
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.currentExerciseIndex >= manager.exercises.count - 1)
                    .opacity(manager.currentExerciseIndex >= manager.exercises.count - 1 ? 0.3 : 1)
                }
                .padding(.top, 4)
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
            // Log set with data (opens input sheet)
            Button(action: {
                WKInterfaceDevice.current().play(.click)
                showingSetInput = true
            }) {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                    Text("Log Set")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // Quick complete (no data entry)
            Button(action: {
                WKInterfaceDevice.current().play(.click)
                manager.sendAction("completeSet", payload: [
                    "exerciseIndex": manager.currentExerciseIndex,
                ])
            }) {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("Quick Done")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            HStack(spacing: 8) {
                // View full plan
                Button(action: { showingPlan = true }) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Plan")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

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
}

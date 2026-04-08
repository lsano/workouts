import SwiftUI

/// Allows the user to log reps and weight for a set directly on Apple Watch.
/// Uses the Digital Crown for quick number input and large tap targets.
struct SetInputView: View {
    @ObservedObject var manager: WatchWorkoutManager
    let exerciseIndex: Int
    @Environment(\.dismiss) private var dismiss

    @State private var reps: Int = 10
    @State private var weight: Int = 0
    @State private var editingField: Field = .reps

    enum Field {
        case reps, weight
    }

    private var exercise: WatchExerciseEntry? {
        guard exerciseIndex >= 0 && exerciseIndex < manager.exercises.count else { return nil }
        return manager.exercises[exerciseIndex]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Exercise name
                Text(exercise?.name ?? "Exercise")
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let ex = exercise {
                    Text("Set \(ex.setsCompleted + 1) of \(ex.setsTotal)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Reps input
                VStack(spacing: 4) {
                    Text("REPS")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button(action: { if reps > 0 { reps -= 1 } }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)

                        Text("\(reps)")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .frame(minWidth: 50)
                            .foregroundColor(editingField == .reps ? .blue : .primary)

                        Button(action: { reps += 1 }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .focusable(editingField == .reps)
                    .digitalCrownRotation(
                        Binding(
                            get: { Double(reps) },
                            set: { reps = max(0, Int($0)) }
                        ),
                        from: 0, through: 100, by: 1,
                        sensitivity: .medium
                    )
                    .onTapGesture { editingField = .reps }
                }

                Divider()

                // Weight input
                VStack(spacing: 4) {
                    Text("WEIGHT (lbs)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button(action: { if weight >= 5 { weight -= 5 } }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)

                        Text("\(weight)")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .frame(minWidth: 50)
                            .foregroundColor(editingField == .weight ? .blue : .primary)

                        Button(action: { weight += 5 }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .focusable(editingField == .weight)
                    .digitalCrownRotation(
                        Binding(
                            get: { Double(weight) },
                            set: { weight = max(0, Int($0)) }
                        ),
                        from: 0, through: 500, by: 5,
                        sensitivity: .medium
                    )
                    .onTapGesture { editingField = .weight }
                }

                Divider()

                // Log set button
                Button(action: {
                    WKInterfaceDevice.current().play(.click)
                    manager.sendAction("logSet", payload: [
                        "exerciseIndex": exerciseIndex,
                        "reps": reps,
                        "weight": weight,
                    ])
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log Set")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                // Skip (complete without data)
                Button(action: {
                    manager.sendAction("completeSet", payload: [
                        "exerciseIndex": exerciseIndex,
                    ])
                    dismiss()
                }) {
                    Text("Skip / No Weight")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Log Set")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Pre-fill with last known values
            if let ex = exercise {
                if let lastReps = ex.lastReps { reps = lastReps }
                if let lastWeight = ex.lastWeight { weight = lastWeight }
            }
        }
    }
}

import SwiftUI

/// Shows the full workout plan on the Apple Watch.
/// Exercises are grouped by section with completion status.
/// Tapping an exercise navigates to the set input view.
struct WorkoutPlanView: View {
    @ObservedObject var manager: WatchWorkoutManager

    var body: some View {
        List {
            ForEach(groupedExercises, id: \.sectionName) { group in
                Section(header: Text(group.sectionName).font(.caption2)) {
                    ForEach(group.exercises.indices, id: \.self) { idx in
                        let entry = group.exercises[idx]
                        let globalIdx = globalIndex(for: entry)

                        NavigationLink(destination: SetInputView(manager: manager, exerciseIndex: globalIdx)) {
                            HStack(spacing: 8) {
                                // Completion indicator
                                if entry.setsCompleted >= entry.setsTotal {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                } else if entry.setsCompleted > 0 {
                                    Image(systemName: "circle.lefthalf.filled")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.caption)
                                        .lineLimit(2)

                                    Text("\(entry.setsCompleted)/\(entry.setsTotal) sets")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                // Current exercise indicator
                                if globalIdx == manager.currentExerciseIndex {
                                    Image(systemName: "arrowtriangle.right.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Group exercises by section
    private var groupedExercises: [ExerciseGroup] {
        var groups: [ExerciseGroup] = []
        var currentSection = ""

        for entry in manager.exercises {
            if entry.sectionName != currentSection {
                currentSection = entry.sectionName
                groups.append(ExerciseGroup(sectionName: currentSection, exercises: []))
            }
            groups[groups.count - 1].exercises.append(entry)
        }

        return groups
    }

    private func globalIndex(for entry: WatchExerciseEntry) -> Int {
        return manager.exercises.firstIndex(where: { $0.id == entry.id }) ?? 0
    }
}

struct ExerciseGroup {
    let sectionName: String
    var exercises: [WatchExerciseEntry]
}

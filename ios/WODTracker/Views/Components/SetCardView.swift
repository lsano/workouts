import SwiftUI
import SwiftData

struct SetCardView: View {
    let exerciseSet: DetectedExerciseSet
    @Binding var isEditing: Bool
    var onDelete: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack {
                confidenceDot(for: exerciseSet.classifierConfidence)
                Text(exerciseSet.exercise.displayName)
                    .font(.headline)
                Spacer()
                Text("\(exerciseSet.effectiveRepCount) reps")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(formatDuration(exerciseSet.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Quality metrics row
            if let quality = exerciseSet.quality {
                HStack(spacing: 16) {
                    metricPill(label: "Tempo", value: "\(Int(quality.avgTempo))ms")
                    metricPill(label: "Symmetry", value: "\(Int(quality.symmetryScore * 100))%")
                    metricPill(label: "Quality", value: "\(Int(quality.overallQuality * 100))%")
                }
            }

            // Expandable edit mode
            if isEditing {
                Divider()
                editControls
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isEditing.toggle()
            }
        }
    }

    // MARK: - Edit Controls

    private var editControls: some View {
        VStack(spacing: 12) {
            // Exercise type picker
            HStack {
                Text("Exercise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Exercise", selection: exerciseTypeBinding) {
                    ForEach(ExerciseType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .tint(.accentColor)
            }

            // Rep count adjuster
            HStack {
                Text("Reps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    adjustReps(by: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("\(exerciseSet.effectiveRepCount)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(minWidth: 36)

                Button {
                    adjustReps(by: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                }
                .buttonStyle(.plain)
            }

            // Quality bars
            if let quality = exerciseSet.quality {
                VStack(spacing: 6) {
                    qualityBar(label: "Tempo Consistency", value: quality.tempoConsistency)
                    qualityBar(label: "Symmetry", value: quality.symmetryScore)
                    qualityBar(label: "Depth", value: quality.depthScore)
                    qualityBar(label: "Overall", value: quality.overallQuality)
                }
            }

            // Delete button
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Set", systemImage: "trash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    // MARK: - Helpers

    private var exerciseTypeBinding: Binding<ExerciseType> {
        Binding(
            get: { exerciseSet.exercise },
            set: { newType in
                exerciseSet.exerciseType = newType.rawValue
                exerciseSet.userCorrectedType = newType.rawValue
                exerciseSet.wasUserCorrected = true
            }
        )
    }

    private func adjustReps(by delta: Int) {
        let current = exerciseSet.effectiveRepCount
        let newCount = max(0, current + delta)
        exerciseSet.repCountCorrected = newCount
        exerciseSet.wasUserCorrected = true
    }

    private func confidenceDot(for confidence: Double) -> some View {
        let level = ConfidenceLevel(score: confidence)
        let color: Color = switch level {
        case .high: .green
        case .medium: .yellow
        case .low: .red
        }
        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func qualityBar(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                    Capsule()
                        .fill(qualityColor(for: value))
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 4)
        }
    }

    private func qualityColor(for value: Double) -> Color {
        if value >= 0.8 { return .green }
        if value >= 0.5 { return .yellow }
        return .red
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var editing = false
        var body: some View {
            let exerciseSet = DetectedExerciseSet(
                exerciseType: .jumpRope,
                confidence: 0.92,
                startTime: Date().addingTimeInterval(-120),
                endTime: Date(),
                repCount: 45,
                sortOrder: 0
            )
            SetCardView(exerciseSet: exerciseSet, isEditing: $editing)
                .padding()
        }
    }
    return PreviewWrapper()
}

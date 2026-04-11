import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @State private var editingSetId: UUID?
    @State private var notes: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                statsGrid
                exerciseBreakdown
                setsList
                notesSection
            }
            .padding()
        }
        .navigationTitle("Workout Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notes = session.notes ?? ""
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(session.startedAt, format: .dateTime.weekday(.wide).month().day().year())
                .font(.headline)

            HStack(spacing: 16) {
                Label(formatDuration(session.duration), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let confidence = session.overallConfidence {
                    HStack(spacing: 4) {
                        confidenceDot(for: confidence)
                        Text("\(Int(confidence * 100))% confidence")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            statCard(value: "\(session.totalSets)", label: "Sets", icon: "number")
            statCard(value: "\(session.totalReps)", label: "Reps", icon: "arrow.up.arrow.down")
            statCard(value: qualityLabel, label: "Quality", icon: "star.fill")
        }
    }

    private var qualityLabel: String {
        let qualities = session.sets.compactMap { $0.quality?.overallQuality }
        guard !qualities.isEmpty else { return "--" }
        let avg = qualities.reduce(0, +) / Double(qualities.count)
        return "\(Int(avg * 100))%"
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.accentColor)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Exercise Breakdown

    private var exerciseBreakdown: some View {
        let grouped = Dictionary(grouping: session.sets, by: { $0.exerciseType })

        return VStack(alignment: .leading, spacing: 8) {
            Text("Exercises")
                .font(.headline)

            ForEach(grouped.keys.sorted(), id: \.self) { key in
                if let sets = grouped[key] {
                    let exerciseName = ExerciseType(rawValue: key)?.displayName ?? key
                    let totalReps = sets.reduce(0) { $0 + $1.effectiveRepCount }
                    let avgQuality = averageQuality(for: sets)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exerciseName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(sets.count) sets  \u{00B7}  \(totalReps) reps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let quality = avgQuality {
                            Text("\(Int(quality * 100))%")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(qualityColor(for: quality))
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Sets List

    private var setsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sets")
                .font(.headline)

            ForEach(session.sets.sorted(by: { $0.sortOrder < $1.sortOrder })) { set in
                SetCardView(
                    exerciseSet: set,
                    isEditing: Binding(
                        get: { editingSetId == set.id },
                        set: { editing in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                editingSetId = editing ? set.id : nil
                            }
                        }
                    ),
                    onDelete: {
                        withAnimation {
                            modelContext.delete(set)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            TextField("Add notes about this workout...", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .lineLimit(3...8)
                .onChange(of: notes) { _, newValue in
                    session.notes = newValue.isEmpty ? nil : newValue
                }
        }
    }

    // MARK: - Helpers

    private func confidenceDot(for confidence: Double) -> some View {
        let level = ConfidenceLevel(score: confidence)
        let color: Color = switch level {
        case .high: .green
        case .medium: .yellow
        case .low: .red
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func averageQuality(for sets: [DetectedExerciseSet]) -> Double? {
        let qualities = sets.compactMap { $0.quality?.overallQuality }
        guard !qualities.isEmpty else { return nil }
        return qualities.reduce(0, +) / Double(qualities.count)
    }

    private func qualityColor(for value: Double) -> Color {
        if value >= 0.8 { return .green }
        if value >= 0.5 { return .yellow }
        return .red
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(session: WorkoutSession())
    }
    .modelContainer(for: WorkoutSession.self, inMemory: true)
}

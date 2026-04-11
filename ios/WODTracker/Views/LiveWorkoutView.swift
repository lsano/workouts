import SwiftUI
import SwiftData

// MARK: - Workout Phase

enum WorkoutPhase {
    case preWorkout
    case active
    case summary
}

struct LiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var workoutPhase: WorkoutPhase = .preWorkout
    @State private var session: WorkoutSession?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var repCount: Int = 0
    @State private var currentExercise: ExerciseType = .unknown
    @State private var currentConfidence: Double = 0.0
    @State private var movementState: MovementState = .idle
    @State private var showFormAlert: Bool = false
    @State private var formAlertMessage: String = ""
    @State private var editingSetId: UUID?
    @State private var sensorConfig: SensorConfig = .disconnected

    var body: some View {
        Group {
            switch workoutPhase {
            case .preWorkout:
                preWorkoutView
            case .active:
                activeView
            case .summary:
                summaryView
            }
        }
        .navigationBarBackButtonHidden(workoutPhase == .active)
    }

    // MARK: - Pre-Workout Phase

    private var preWorkoutView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating)

            Text("Ready to Workout")
                .font(.title)
                .fontWeight(.bold)

            // Sensor status
            VStack(spacing: 12) {
                Text("Sensor Status")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    sensorRow(name: "Left Foot", systemImage: "shoe.fill", connected: sensorConfig.leftFootConnected)
                    sensorRow(name: "Right Foot", systemImage: "shoe.fill", connected: sensorConfig.rightFootConnected)
                    sensorRow(name: "Apple Watch", systemImage: "applewatch", connected: sensorConfig.watchConnected)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                startWorkout()
            } label: {
                Text("Start Workout")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.green, in: RoundedRectangle(cornerRadius: 14))
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: workoutPhase)

            NavigationLink("Sensor Debug") {
                SensorDebugView()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func sensorRow(name: String, systemImage: String, connected: Bool) -> some View {
        HStack {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(connected ? .green : .gray)
            Text(name)
                .font(.subheadline)
            Spacer()
            Circle()
                .fill(connected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(connected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(connected ? .green : .secondary)
        }
    }

    // MARK: - Active Phase

    private var activeView: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text(formattedElapsedTime)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    SensorStatusBar(
                        leftFootConnected: sensorConfig.leftFootConnected,
                        rightFootConnected: sensorConfig.rightFootConnected,
                        watchConnected: sensorConfig.watchConnected
                    )
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 24) {
                        // Rep counter
                        VStack(spacing: 8) {
                            Text("\(repCount)")
                                .font(.system(size: 96, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(repCountColor)

                            HStack(spacing: 6) {
                                confidenceDot(for: currentConfidence)
                                Text(currentExercise.displayName)
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }

                            Text(movementState.rawValue.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(movementStateBadgeColor.opacity(0.2), in: Capsule())
                        }
                        .padding(.top, 32)

                        // Completed sets
                        if let session, !session.sets.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Completed Sets")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)

                                ForEach(session.sets.sorted(by: { $0.sortOrder < $1.sortOrder })) { set in
                                    SetCardView(
                                        exerciseSet: set,
                                        isEditing: Binding(
                                            get: { editingSetId == set.id },
                                            set: { editing in editingSetId = editing ? set.id : nil }
                                        )
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 100) // room for button
                }
            }

            // Form alert banner
            if showFormAlert {
                formAlertBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                endWorkout()
            } label: {
                Text("End Workout")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.red, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
            .background(.ultraThinMaterial)
            .sensoryFeedback(.impact(weight: .medium), trigger: workoutPhase)
        }
        .animation(.easeInOut(duration: 0.3), value: showFormAlert)
    }

    private var formAlertBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(formAlertMessage)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var repCountColor: Color {
        switch movementState {
        case .active: .white
        case .resting: .blue
        case .idle: .gray
        }
    }

    private var movementStateBadgeColor: Color {
        switch movementState {
        case .active: .green
        case .resting: .blue
        case .idle: .gray
        }
    }

    private var formattedElapsedTime: String {
        let mins = Int(elapsedTime) / 60
        let secs = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Summary Phase

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Trophy header
                VStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.yellow)
                    Text("Workout Complete")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.top, 32)

                // Stats grid
                if let session {
                    statsGrid(for: session)

                    // Exercise breakdown
                    exerciseBreakdown(for: session)

                    // Editable set cards
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sets")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(session.sets.sorted(by: { $0.sortOrder < $1.sortOrder })) { set in
                            SetCardView(
                                exerciseSet: set,
                                isEditing: Binding(
                                    get: { editingSetId == set.id },
                                    set: { editing in editingSetId = editing ? set.id : nil }
                                ),
                                onDelete: {
                                    modelContext.delete(set)
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                }

                // Navigation buttons
                VStack(spacing: 12) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Text("View History")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func statsGrid(for session: WorkoutSession) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            summaryStatCard(value: "\(session.totalSets)", label: "Sets", icon: "number")
            summaryStatCard(value: "\(session.totalReps)", label: "Total Reps", icon: "arrow.up.arrow.down")
            summaryStatCard(
                value: session.overallConfidence.map { "\(Int($0 * 100))%" } ?? "--",
                label: "Quality",
                icon: "star.fill"
            )
            summaryStatCard(value: formatDuration(session.duration), label: "Duration", icon: "clock")
        }
        .padding(.horizontal)
    }

    private func summaryStatCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
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

    private func exerciseBreakdown(for session: WorkoutSession) -> some View {
        let grouped = Dictionary(grouping: session.sets, by: { $0.exerciseType })

        return VStack(alignment: .leading, spacing: 8) {
            Text("Exercise Breakdown")
                .font(.headline)
                .padding(.horizontal)

            ForEach(grouped.keys.sorted(), id: \.self) { key in
                if let sets = grouped[key] {
                    let exerciseName = ExerciseType(rawValue: key)?.displayName ?? key
                    let totalReps = sets.reduce(0) { $0 + $1.effectiveRepCount }
                    HStack {
                        Text(exerciseName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(sets.count) sets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(totalReps) reps")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.accentColor)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Actions

    private func startWorkout() {
        let newSession = WorkoutSession()
        modelContext.insert(newSession)
        session = newSession
        workoutPhase = .active
        startTimer()
    }

    private func endWorkout() {
        stopTimer()
        session?.status = "completed"
        session?.completedAt = Date()
        workoutPhase = .summary
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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
            .frame(width: 10, height: 10)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        LiveWorkoutView()
    }
    .modelContainer(for: WorkoutSession.self, inMemory: true)
}

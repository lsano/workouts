import SwiftUI
import SwiftData

struct TrendsView: View {
    @Query(sort: \TrendAggregate.dateBucket, order: .reverse)
    private var allTrends: [TrendAggregate]

    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var selectedPeriod: TrendPeriod = .thirtyDays
    @State private var selectedExercise: ExerciseType?

    enum TrendPeriod: String, CaseIterable, Identifiable {
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case ninetyDays = "90d"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .sevenDays: 7
            case .thirtyDays: 30
            case .ninetyDays: 90
            }
        }
    }

    private var filteredTrends: [TrendAggregate] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: Date()) ?? Date()
        let cutoffStr = isoDateString(from: cutoff)
        return allTrends.filter { $0.dateBucket >= cutoffStr }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                periodPicker
                overallStats
                exerciseList
            }
            .padding()
        }
        .navigationTitle("Trends")
        .sheet(item: $selectedExercise) { exercise in
            NavigationStack {
                ExerciseDetailTrendView(
                    exerciseType: exercise,
                    trends: filteredTrends.filter { $0.exerciseType == exercise.rawValue }
                )
            }
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(TrendPeriod.allCases) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Overall Stats

    private var overallStats: some View {
        let trends = filteredTrends

        let workouts = Set(trends.map { $0.dateBucket }).count
        let sets = trends.reduce(0) { $0 + $1.totalSets }
        let reps = trends.reduce(0) { $0 + $1.totalReps }

        return HStack(spacing: 12) {
            overallStatCard(value: "\(workouts)", label: "Workouts", icon: "figure.run")
            overallStatCard(value: "\(sets)", label: "Sets", icon: "number")
            overallStatCard(value: "\(reps)", label: "Reps", icon: "arrow.up.arrow.down")
        }
    }

    private func overallStatCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
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

    // MARK: - Exercise List

    private var exerciseList: some View {
        let exerciseGroups = Dictionary(grouping: filteredTrends, by: { $0.exerciseType })

        return VStack(alignment: .leading, spacing: 8) {
            Text("Exercises")
                .font(.headline)

            if exerciseGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No data for this period")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(exerciseGroups.keys.sorted(), id: \.self) { key in
                    if let trends = exerciseGroups[key] {
                        let exercise = ExerciseType(rawValue: key) ?? .unknown
                        let totalSets = trends.reduce(0) { $0 + $1.totalSets }
                        let totalReps = trends.reduce(0) { $0 + $1.totalReps }
                        let sparklineData = trends
                            .sorted(by: { $0.dateBucket < $1.dateBucket })
                            .suffix(7)
                            .map { Double($0.totalReps) }

                        Button {
                            selectedExercise = exercise
                        } label: {
                            exerciseRow(
                                name: exercise.displayName,
                                sets: totalSets,
                                reps: totalReps,
                                sparkline: sparklineData
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func exerciseRow(name: String, sets: Int, reps: Int, sparkline: [Double]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text("\(sets) sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(reps) reps")
                        .font(.caption)
                        .foregroundStyle(.accentColor)
                }
            }

            Spacer()

            // Mini sparkline
            Canvas { context, size in
                guard sparkline.count >= 2 else { return }
                let maxVal = sparkline.max() ?? 1
                let minVal = sparkline.min() ?? 0
                let range = max(maxVal - minVal, 1)
                let step = size.width / CGFloat(sparkline.count - 1)

                var path = Path()
                for (i, val) in sparkline.enumerated() {
                    let x = step * CGFloat(i)
                    let y = size.height - (size.height * (val - minVal) / range)
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
            }
            .frame(width: 60, height: 28)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Exercise Detail Trend View

struct ExerciseDetailTrendView: View {
    let exerciseType: ExerciseType
    let trends: [TrendAggregate]

    @Environment(\.dismiss) private var dismiss

    private var sortedTrends: [TrendAggregate] {
        trends.sorted(by: { $0.dateBucket < $1.dateBucket })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Volume chart
                TrendChartView(
                    dataPoints: sortedTrends.map { trend in
                        TrendDataPoint(
                            date: dateFromBucket(trend.dateBucket),
                            value: Double(trend.totalReps)
                        )
                    },
                    color: .blue,
                    title: "Volume (Reps)"
                )

                // Tempo trend
                if sortedTrends.contains(where: { $0.avgTempo != nil }) {
                    TrendChartView(
                        dataPoints: sortedTrends.compactMap { trend in
                            guard let tempo = trend.avgTempo else { return nil }
                            return TrendDataPoint(
                                date: dateFromBucket(trend.dateBucket),
                                value: tempo
                            )
                        },
                        color: .orange,
                        title: "Avg Tempo (ms)"
                    )
                }

                // Symmetry trend
                if sortedTrends.contains(where: { $0.avgSymmetry != nil }) {
                    TrendChartView(
                        dataPoints: sortedTrends.compactMap { trend in
                            guard let sym = trend.avgSymmetry else { return nil }
                            return TrendDataPoint(
                                date: dateFromBucket(trend.dateBucket),
                                value: sym * 100
                            )
                        },
                        color: .green,
                        title: "Symmetry (%)"
                    )
                }

                // Quality trend
                if sortedTrends.contains(where: { $0.avgQuality != nil }) {
                    TrendChartView(
                        dataPoints: sortedTrends.compactMap { trend in
                            guard let quality = trend.avgQuality else { return nil }
                            return TrendDataPoint(
                                date: dateFromBucket(trend.dateBucket),
                                value: quality * 100
                            )
                        },
                        color: .purple,
                        title: "Quality (%)"
                    )
                }

                // Insights
                insightsSection
            }
            .padding()
        }
        .navigationTitle(exerciseType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(generateInsights(), id: \.self) { insight in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(insight)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func generateInsights() -> [String] {
        var insights: [String] = []
        let sorted = sortedTrends

        guard sorted.count >= 2 else {
            insights.append("Not enough data yet. Keep working out to see trends.")
            return insights
        }

        // Volume trend
        let firstHalf = sorted.prefix(sorted.count / 2)
        let secondHalf = sorted.suffix(sorted.count / 2)
        let firstAvg = Double(firstHalf.reduce(0) { $0 + $1.totalReps }) / Double(max(firstHalf.count, 1))
        let secondAvg = Double(secondHalf.reduce(0) { $0 + $1.totalReps }) / Double(max(secondHalf.count, 1))

        if secondAvg > firstAvg * 1.1 {
            insights.append("Your volume is trending up. Great progress on \(exerciseType.displayName).")
        } else if secondAvg < firstAvg * 0.9 {
            insights.append("Volume has decreased recently. Consider increasing sets or reps.")
        } else {
            insights.append("Volume is steady. Try progressive overload to keep improving.")
        }

        // Quality insight
        let qualities = sorted.compactMap { $0.avgQuality }
        if let latest = qualities.last, latest >= 0.8 {
            insights.append("Quality is excellent at \(Int(latest * 100))%. Maintain your form.")
        } else if let latest = qualities.last, latest < 0.5 {
            insights.append("Quality score is low. Focus on controlled movement and proper form.")
        }

        // Symmetry insight
        if exerciseType.isBilateral {
            let symmetries = sorted.compactMap { $0.avgSymmetry }
            if let latest = symmetries.last, latest < 0.8 {
                insights.append("Symmetry needs attention. Consider unilateral drills to balance sides.")
            }
        }

        return insights
    }

    private func dateFromBucket(_ bucket: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: bucket) ?? Date()
    }
}

#Preview {
    NavigationStack {
        TrendsView()
    }
    .modelContainer(for: [WorkoutSession.self, TrendAggregate.self], inMemory: true)
}

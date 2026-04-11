import SwiftUI

/// Dedicated view for the auto-detection workout experience on Apple Watch.
/// Optimized for glanceable information: large rep count, exercise name,
/// form alerts, and minimal controls. Shown when isAutoMode is true.
struct AutoWorkoutView: View {
    @ObservedObject var manager: WatchWorkoutManager

    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            VStack(spacing: 0) {
                Spacer().frame(height: 8)

                // Elapsed time at top edge
                Text(manager.formatTime(manager.elapsedSeconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer().frame(height: 4)

                // Hero: massive rep count
                Text("\(manager.autoRepCount)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // Exercise name + confidence dot
                HStack(spacing: 6) {
                    Text(manager.autoExerciseName.isEmpty ? "Detecting..." : manager.autoExerciseName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(manager.autoExerciseName.isEmpty ? .secondary : .primary)

                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 8, height: 8)
                }

                Spacer().frame(height: 8)

                // Heart rate + movement state row
                HStack(spacing: 16) {
                    // Heart rate
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.caption2)
                        Text("\(Int(manager.heartRate))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }

                    // Movement state
                    HStack(spacing: 3) {
                        Circle()
                            .fill(movementStateColor)
                            .frame(width: 6, height: 6)
                        Text(movementStateLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(movementStateColor)
                    }
                }

                Spacer().frame(height: 12)

                // Minimal controls
                HStack(spacing: 8) {
                    // Correction button
                    Button(action: {
                        WKInterfaceDevice.current().play(.click)
                        manager.sendAction("correctExercise")
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    // End button
                    Button(action: {
                        manager.sendAction("endWorkout")
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.caption2)
                            Text("End")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal, 4)

                Spacer().frame(height: 4)
            }
            .padding(.horizontal, 4)

            // Form alert banner — slides down from top
            if manager.formAlertVisible {
                formAlertBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: manager.formAlertVisible)
        .navigationTitle("Auto")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Form Alert Banner

    private var formAlertBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(manager.formAlertMessage)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red)
        )
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .onTapGesture { manager.dismissFormAlert() }
    }

    // MARK: - Computed Properties

    private var confidenceColor: Color {
        if manager.autoConfidence > 0.8 { return .green }
        if manager.autoConfidence > 0.5 { return .yellow }
        return .red
    }

    private var movementStateLabel: String {
        switch manager.movementState {
        case "active": return "Active"
        case "resting": return "Resting"
        default: return "Idle"
        }
    }

    private var movementStateColor: Color {
        switch manager.movementState {
        case "active": return .green
        case "resting": return .blue
        default: return .gray
        }
    }
}

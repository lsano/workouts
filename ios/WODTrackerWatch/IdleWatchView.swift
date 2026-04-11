import SwiftUI

/// Displayed when no workout is active.
/// Shows health summary and prompts user to start a workout from the iPhone.
struct IdleWatchView: View {
    @ObservedObject var manager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text("WOD Tracker")
                    .font(.headline)

                Text("Start a workout on your\niPhone to begin tracking")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Divider()

                // Quick start from watch
                Button(action: {
                    manager.sendAction("quickStart", payload: ["type": "freeform"])
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Quick Start")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding()
        }
        .navigationTitle("WOD")
    }
}

import SwiftUI

/// Entry point for the WOD Tracker watchOS companion app.
/// This app receives workout state from the iPhone via WatchConnectivity
/// and displays a live workout view with timer, current exercise, and heart rate.
@main
struct WODWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if workoutManager.isWorkoutActive {
                    ActiveWorkoutView(manager: workoutManager)
                } else {
                    IdleWatchView(manager: workoutManager)
                }
            }
        }
    }
}

import SwiftUI
import SwiftData

@main
struct WODTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            WorkoutSession.self,
            DetectedExerciseSet.self,
            RepEvent.self,
            SensorDevice.self,
            SensorRecording.self,
            TrendAggregate.self,
        ])
    }
}

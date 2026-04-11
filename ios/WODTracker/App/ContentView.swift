import SwiftUI

struct ContentView: View {
    @State private var sensorManager = SensorManager()

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .environment(sensorManager)
    }
}

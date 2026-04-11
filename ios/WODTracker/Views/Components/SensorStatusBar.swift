import SwiftUI

struct SensorStatusBar: View {
    var leftFootConnected: Bool
    var rightFootConnected: Bool
    var watchConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            sensorDot(label: "L", connected: leftFootConnected)
            sensorDot(label: "R", connected: rightFootConnected)
            sensorDot(label: "W", connected: watchConnected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func sensorDot(label: String, connected: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(connected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SensorStatusBar(
        leftFootConnected: true,
        rightFootConnected: false,
        watchConnected: true
    )
    .padding()
    .background(Color.black)
}

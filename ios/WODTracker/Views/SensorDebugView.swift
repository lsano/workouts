import SwiftUI

struct SensorDebugView: View {
    @State private var sensorConfig: SensorConfig = .disconnected
    @State private var selectedSource: SensorSource = .leftFoot
    @State private var isScanning: Bool = false
    @State private var isRecording: Bool = false
    @State private var discoveredDevices: [DiscoveredDevice] = []
    @State private var leftFootSamples: Int = 0
    @State private var rightFootSamples: Int = 0
    @State private var watchSamples: Int = 0

    enum SensorSource: String, CaseIterable, Identifiable {
        case leftFoot = "Left Foot"
        case rightFoot = "Right Foot"
        case watch = "Watch"
        var id: String { rawValue }
    }

    struct DiscoveredDevice: Identifiable {
        let id = UUID()
        let name: String
        let rssi: Int
        let peripheralId: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                connectionStatusSection
                scanSection
                discoveredDevicesSection
                sourceSelector
                canvasSection
                bufferCountsSection
                recordingSection
            }
            .padding()
        }
        .navigationTitle("Sensor Debug")
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Status")
                .font(.headline)

            HStack(spacing: 16) {
                connectionTile(label: "Left Foot", connected: sensorConfig.leftFootConnected)
                connectionTile(label: "Right Foot", connected: sensorConfig.rightFootConnected)
                connectionTile(label: "Watch", connected: sensorConfig.watchConnected)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func connectionTile(label: String, connected: Bool) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.gray)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scan

    private var scanSection: some View {
        Button {
            scanForSensors()
        } label: {
            HStack {
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(isScanning ? "Scanning..." : "Scan for Sensors")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.blue, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }
        .disabled(isScanning)
    }

    // MARK: - Discovered Devices

    private var discoveredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovered Devices")
                .font(.headline)

            if discoveredDevices.isEmpty {
                Text("No devices found. Tap scan to search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(discoveredDevices) { device in
                    deviceRow(device)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("RSSI: \(device.rssi) dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Connect as Left") {
                    connectDevice(device, side: .leftFoot)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.blue)

                Button("Connect as Right") {
                    connectDevice(device, side: .rightFoot)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Source Selector

    private var sourceSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Source")
                .font(.headline)

            Picker("Source", selection: $selectedSource) {
                ForEach(SensorSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Canvas Visualization

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Signal Preview")
                    .font(.headline)
                Spacer()
                Text("Real-time chart renders in Canvas")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Canvas { context, size in
                // Placeholder sine wave visualization
                let midY = size.height / 2
                let amplitude = size.height * 0.35
                let frequency = 3.0
                let step: CGFloat = 2

                var path = Path()
                for x in stride(from: 0, through: size.width, by: step) {
                    let normalizedX = x / size.width
                    let y = midY + amplitude * sin(normalizedX * frequency * .pi * 2)
                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                let lineColor: Color = switch selectedSource {
                case .leftFoot: .blue
                case .rightFoot: .green
                case .watch: .orange
                }

                context.stroke(path, with: .color(lineColor), lineWidth: 2)

                // Center line
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: midY))
                centerLine.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(centerLine, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
            }
            .frame(height: 180)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Buffer Counts

    private var bufferCountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sample Buffers")
                .font(.headline)

            HStack(spacing: 16) {
                bufferCount(label: "Left Foot", count: leftFootSamples, color: .blue)
                bufferCount(label: "Right Foot", count: rightFootSamples, color: .green)
                bufferCount(label: "Watch", count: watchSamples, color: .orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func bufferCount(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recording Controls

    private var recordingSection: some View {
        HStack(spacing: 12) {
            Button {
                isRecording.toggle()
            } label: {
                Label(
                    isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: isRecording ? "stop.circle.fill" : "record.circle"
                )
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isRecording ? Color.red : Color.green, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }

            Button {
                exportRecording()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .fontWeight(.medium)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Actions

    private func scanForSensors() {
        isScanning = true
        // Scanning would be handled by a BLE ViewModel
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isScanning = false
        }
    }

    private func connectDevice(_ device: DiscoveredDevice, side: SensorSource) {
        // Connection would be handled by a BLE ViewModel
    }

    private func exportRecording() {
        // Export would be handled by a recording ViewModel
    }
}

#Preview {
    NavigationStack {
        SensorDebugView()
    }
}

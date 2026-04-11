import Foundation
import CoreBluetooth
import Combine

// MARK: - Constants

/// Stryd pods advertise Running Speed and Cadence (0x1814) plus custom services.
/// These placeholder UUIDs should be updated after real device testing.
private let STRYD_SERVICE_UUID = CBUUID(string: "00001814-0000-1000-8000-00805F9B34FB")
private let STRYD_IMU_CHARACTERISTIC_UUID = CBUUID(string: "00002A53-0000-1000-8000-00805F9B34FB")

/// Standard Battery Service UUIDs
private let BATTERY_SERVICE_UUID = CBUUID(string: "180F")
private let BATTERY_LEVEL_CHARACTERISTIC_UUID = CBUUID(string: "2A19")

// MARK: - SensorSample

struct SensorSample {
    let timestamp: TimeInterval
    let ax: Double
    let ay: Double
    let az: Double
    let gx: Double
    let gy: Double
    let gz: Double
}

// MARK: - SensorSide

enum SensorSide: String {
    case left
    case right
}

// MARK: - DiscoveredDevice

struct DiscoveredDevice: Identifiable {
    let id: String
    let name: String
    let rssi: Int
}

// MARK: - ConnectedSensor

struct ConnectedSensor {
    let id: String
    let name: String
    let side: SensorSide
    let connected: Bool
    let batteryLevel: Int?
}

// MARK: - FootSensor (internal)

/// Tracks state for a single foot-mounted sensor peripheral.
private class FootSensor {
    let side: SensorSide
    var peripheral: CBPeripheral
    var name: String
    var batteryLevel: Int?
    var imuCharacteristic: CBCharacteristic?
    var batteryCharacteristic: CBCharacteristic?
    var sampleBuffer: [SensorSample] = []
    var lastFlushTime: Date = Date()

    init(peripheral: CBPeripheral, side: SensorSide) {
        self.peripheral = peripheral
        self.side = side
        self.name = peripheral.name ?? "Unknown"
    }

    func toConnectedSensor() -> ConnectedSensor {
        return ConnectedSensor(
            id: peripheral.identifier.uuidString,
            name: name,
            side: side,
            connected: peripheral.state == .connected,
            batteryLevel: batteryLevel
        )
    }
}

// MARK: - BLEManager

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: - Published Properties

    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var leftFoot: ConnectedSensor?
    @Published var rightFoot: ConnectedSensor?
    @Published var isScanning = false

    // MARK: - Sensor Data Callback

    /// Called on the main queue when a batch of sensor samples is ready for a given side.
    var onSensorData: ((SensorSide, [SensorSample]) -> Void)?

    // MARK: - Private State

    private var centralManager: CBCentralManager?
    private var connectedSensors: [UUID: FootSensor] = [:]
    private var streamActive: Bool = false
    private var flushTimer: Timer?

    /// How often buffered samples are flushed (seconds).
    private let flushInterval: TimeInterval = 0.1

    // MARK: - Initializer

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods

    func startScanning() {
        guard let manager = centralManager, manager.state == .poweredOn else {
            isScanning = true  // will start when powered on
            return
        }

        isScanning = true
        discoveredDevices = []
        manager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        isScanning = false
        centralManager?.stopScan()
    }

    func connectDevice(id: String, side: SensorSide) {
        guard let uuid = UUID(uuidString: id),
              let manager = centralManager, manager.state == .poweredOn else {
            return
        }

        // Check if already connected
        if let existing = connectedSensors[uuid], existing.peripheral.state == .connected {
            publishSensorState(for: existing)
            return
        }

        let peripherals = manager.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else { return }

        peripheral.delegate = self
        // Store the side temporarily; will be used in didConnect
        let sensor = FootSensor(peripheral: peripheral, side: side)
        connectedSensors[uuid] = sensor
        manager.connect(peripheral, options: nil)
    }

    func disconnectDevice(id: String) {
        guard let uuid = UUID(uuidString: id),
              let sensor = connectedSensors[uuid] else { return }

        centralManager?.cancelPeripheralConnection(sensor.peripheral)
    }

    func startSensorStream() {
        streamActive = true

        // Subscribe to IMU notifications on all connected sensors
        for sensor in connectedSensors.values {
            if let characteristic = sensor.imuCharacteristic {
                sensor.peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        startFlushTimer()
    }

    func stopSensorStream() {
        streamActive = false

        // Unsubscribe from IMU notifications on all connected sensors
        for sensor in connectedSensors.values {
            if let characteristic = sensor.imuCharacteristic {
                sensor.peripheral.setNotifyValue(false, for: characteristic)
            }
        }

        stopFlushTimer()

        // Flush any remaining buffered samples
        flushAllSensorBuffers()
    }

    // MARK: - Flush Timer

    private func startFlushTimer() {
        stopFlushTimer()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.flushAllSensorBuffers()
        }
    }

    private func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    private func flushAllSensorBuffers() {
        for sensor in connectedSensors.values {
            guard !sensor.sampleBuffer.isEmpty else { continue }

            let samples = sensor.sampleBuffer
            sensor.sampleBuffer.removeAll()
            sensor.lastFlushTime = Date()

            DispatchQueue.main.async { [weak self] in
                self?.onSensorData?(sensor.side, samples)
            }
        }
    }

    // MARK: - Published State Helpers

    private func publishSensorState(for sensor: FootSensor) {
        let connected = sensor.toConnectedSensor()
        DispatchQueue.main.async { [weak self] in
            switch sensor.side {
            case .left:
                self?.leftFoot = connected
            case .right:
                self?.rightFoot = connected
            }
        }
    }

    private func clearSensorState(for sensor: FootSensor) {
        DispatchQueue.main.async { [weak self] in
            switch sensor.side {
            case .left:
                self?.leftFoot = nil
            case .right:
                self?.rightFoot = nil
            }
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLEManager] Bluetooth powered on")
            if isScanning {
                central.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ])
            }
        case .poweredOff:
            print("[BLEManager] Bluetooth powered off")
        case .unauthorized:
            print("[BLEManager] Bluetooth unauthorized")
        case .unsupported:
            print("[BLEManager] Bluetooth unsupported on this device")
        case .resetting:
            print("[BLEManager] Bluetooth resetting")
        case .unknown:
            print("[BLEManager] Bluetooth state unknown")
        @unknown default:
            print("[BLEManager] Bluetooth state unhandled: \(central.state.rawValue)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let deviceName = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"

        let device = DiscoveredDevice(
            id: peripheral.identifier.uuidString,
            name: deviceName,
            rssi: RSSI.intValue
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Avoid duplicates by id
            if !self.discoveredDevices.contains(where: { $0.id == device.id }) {
                self.discoveredDevices.append(device)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier

        if let sensor = connectedSensors[uuid] {
            peripheral.delegate = self
            publishSensorState(for: sensor)

            // Discover all services to find IMU and battery characteristics
            peripheral.discoverServices(nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let uuid = peripheral.identifier
        let errorMessage = error?.localizedDescription ?? "Unknown connection failure"
        print("[BLEManager] Failed to connect to \(uuid): \(errorMessage)")

        if let sensor = connectedSensors.removeValue(forKey: uuid) {
            clearSensorState(for: sensor)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let uuid = peripheral.identifier

        if let sensor = connectedSensors[uuid] {
            // If the disconnection was unexpected (error is non-nil), attempt to reconnect
            if error != nil {
                print("[BLEManager] Unexpected disconnect from \(sensor.name) (\(sensor.side.rawValue)). Attempting reconnect...")
                publishSensorState(for: sensor)  // update connected=false
                central.connect(peripheral, options: nil)
            } else {
                connectedSensors.removeValue(forKey: uuid)
                clearSensorState(for: sensor)
            }
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[BLEManager] Service discovery error: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            print("[BLEManager] Characteristic discovery error: \(error.localizedDescription)")
            return
        }

        let uuid = peripheral.identifier
        guard let sensor = connectedSensors[uuid] else { return }
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            // Check for IMU data characteristic
            if characteristic.uuid == STRYD_IMU_CHARACTERISTIC_UUID {
                sensor.imuCharacteristic = characteristic

                // If streaming is already active, subscribe immediately
                if streamActive {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }

            // Check for battery level characteristic
            if characteristic.uuid == BATTERY_LEVEL_CHARACTERISTIC_UUID {
                sensor.batteryCharacteristic = characteristic
                // Read battery level once
                peripheral.readValue(for: characteristic)
                // Subscribe to battery notifications if supported
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BLEManager] Characteristic update error: \(error.localizedDescription)")
            return
        }

        let uuid = peripheral.identifier
        guard let sensor = connectedSensors[uuid] else { return }

        if characteristic.uuid == BATTERY_LEVEL_CHARACTERISTIC_UUID {
            handleBatteryUpdate(sensor: sensor, data: characteristic.value)
        } else if characteristic.uuid == STRYD_IMU_CHARACTERISTIC_UUID {
            handleIMUData(sensor: sensor, data: characteristic.value)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BLEManager] Notification state error for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        let state = characteristic.isNotifying ? "enabled" : "disabled"
        print("[BLEManager] Notifications \(state) for \(characteristic.uuid) on \(peripheral.name ?? "unknown")")
    }

    // MARK: - Data Parsing

    /// Parse battery level from characteristic data.
    private func handleBatteryUpdate(sensor: FootSensor, data: Data?) {
        guard let data = data, !data.isEmpty else { return }

        let level = Int(data[0])
        sensor.batteryLevel = level
        publishSensorState(for: sensor)
    }

    /// Parse IMU data from the Stryd characteristic.
    /// The exact format depends on the Stryd firmware; this implementation assumes
    /// a 12-byte payload: 6 x Int16 (little-endian) for ax, ay, az, gx, gy, gz.
    /// Accelerometer values are scaled from raw to g (divide by 2048).
    /// Gyroscope values are scaled from raw to deg/s (divide by 16.4).
    /// Adjust scaling factors after real device testing.
    private func handleIMUData(sensor: FootSensor, data: Data?) {
        guard let data = data, data.count >= 12 else { return }

        let timestamp = Date().timeIntervalSince1970

        // Parse 6 signed 16-bit integers (little-endian)
        let rawAx = data.readInt16LE(at: 0)
        let rawAy = data.readInt16LE(at: 2)
        let rawAz = data.readInt16LE(at: 4)
        let rawGx = data.readInt16LE(at: 6)
        let rawGy = data.readInt16LE(at: 8)
        let rawGz = data.readInt16LE(at: 10)

        // Scale factors (adjust after real device testing)
        let accelScale: Double = 2048.0  // LSB/g for +/-16g range
        let gyroScale: Double = 16.4     // LSB/(deg/s) for +/-2000 deg/s range

        let sample = SensorSample(
            timestamp: timestamp,
            ax: Double(rawAx) / accelScale,
            ay: Double(rawAy) / accelScale,
            az: Double(rawAz) / accelScale,
            gx: Double(rawGx) / gyroScale,
            gy: Double(rawGy) / gyroScale,
            gz: Double(rawGz) / gyroScale
        )

        sensor.sampleBuffer.append(sample)
    }
}

// MARK: - Data Extension

private extension Data {
    /// Read a little-endian signed 16-bit integer at the given byte offset.
    func readInt16LE(at offset: Int) -> Int16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: offset)
            return base.loadUnaligned(as: Int16.self)
        }
    }
}

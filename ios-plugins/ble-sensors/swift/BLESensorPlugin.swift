import Foundation
import Capacitor
import CoreBluetooth

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

    func toDictionary() -> [String: Any] {
        return [
            "timestamp": timestamp,
            "ax": ax, "ay": ay, "az": az,
            "gx": gx, "gy": gy, "gz": gz
        ]
    }
}

// MARK: - FootSensor

/// Tracks state for a single foot-mounted sensor peripheral.
private class FootSensor {
    let side: String
    var peripheral: CBPeripheral
    var name: String
    var batteryLevel: Int?
    var imuCharacteristic: CBCharacteristic?
    var batteryCharacteristic: CBCharacteristic?
    var sampleBuffer: [SensorSample] = []
    var lastFlushTime: Date = Date()

    init(peripheral: CBPeripheral, side: String) {
        self.peripheral = peripheral
        self.side = side
        self.name = peripheral.name ?? "Unknown"
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": peripheral.identifier.uuidString,
            "side": side,
            "name": name,
            "connected": peripheral.state == .connected
        ]
        if let battery = batteryLevel {
            dict["batteryLevel"] = battery
        }
        return dict
    }
}

// MARK: - BLESensorPlugin

@objc(BLESensorPlugin)
public class BLESensorPlugin: CAPPlugin, CAPBridgedPlugin, CBCentralManagerDelegate, CBPeripheralDelegate {
    public let identifier = "BLESensorPlugin"
    public let jsName = "BLESensors"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startScanning", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopScanning", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "connectDevice", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnectDevice", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getConnectedDevices", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startSensorStream", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopSensorStream", returnType: CAPPluginReturnPromise),
    ]

    private var centralManager: CBCentralManager?
    private var connectedSensors: [UUID: FootSensor] = [:]
    private var pendingConnections: [UUID: (call: CAPPluginCall, side: String)] = [:]
    private var scanRequested: Bool = false
    private var streamActive: Bool = false
    private var flushTimer: Timer?

    /// How often buffered samples are flushed to JS listeners (seconds).
    private let flushInterval: TimeInterval = 0.1

    // MARK: - Plugin Lifecycle

    override public func load() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Plugin Methods

    @objc func startScanning(_ call: CAPPluginCall) {
        guard let manager = centralManager else {
            call.reject("Bluetooth not initialized")
            return
        }

        scanRequested = true

        if manager.state == .poweredOn {
            manager.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        }
        // If not powered on yet, scanning will begin in centralManagerDidUpdateState

        call.resolve()
    }

    @objc func stopScanning(_ call: CAPPluginCall) {
        scanRequested = false
        centralManager?.stopScan()
        call.resolve()
    }

    @objc func connectDevice(_ call: CAPPluginCall) {
        guard let idString = call.getString("id"),
              let uuid = UUID(uuidString: idString) else {
            call.reject("Valid device id is required")
            return
        }

        guard let side = call.getString("side"), side == "left" || side == "right" else {
            call.reject("side must be 'left' or 'right'")
            return
        }

        guard let manager = centralManager, manager.state == .poweredOn else {
            call.reject("Bluetooth is not available")
            return
        }

        // Check if already connected
        if let existing = connectedSensors[uuid], existing.peripheral.state == .connected {
            call.resolve(["connected": true])
            return
        }

        // Retrieve the peripheral by its identifier
        let peripherals = manager.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else {
            call.reject("Peripheral not found. Ensure the device was discovered via scanning.")
            return
        }

        peripheral.delegate = self
        pendingConnections[uuid] = (call: call, side: side)
        manager.connect(peripheral, options: nil)
    }

    @objc func disconnectDevice(_ call: CAPPluginCall) {
        guard let idString = call.getString("id"),
              let uuid = UUID(uuidString: idString) else {
            call.reject("Valid device id is required")
            return
        }

        guard let sensor = connectedSensors[uuid] else {
            call.resolve()
            return
        }

        centralManager?.cancelPeripheralConnection(sensor.peripheral)
        call.resolve()
    }

    @objc func getConnectedDevices(_ call: CAPPluginCall) {
        let devices = connectedSensors.values.map { $0.toDictionary() }
        call.resolve(["devices": devices])
    }

    @objc func startSensorStream(_ call: CAPPluginCall) {
        streamActive = true

        // Subscribe to IMU notifications on all connected sensors
        for sensor in connectedSensors.values {
            if let characteristic = sensor.imuCharacteristic {
                sensor.peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        startFlushTimer()
        call.resolve()
    }

    @objc func stopSensorStream(_ call: CAPPluginCall) {
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

        call.resolve()
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

            let payload: [String: Any] = [
                "side": sensor.side,
                "samples": samples.map { $0.toDictionary() }
            ]
            notifyListeners("sensorData", data: payload)
        }
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLESensors] Bluetooth powered on")
            if scanRequested {
                central.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ])
            }
        case .poweredOff:
            print("[BLESensors] Bluetooth powered off")
        case .unauthorized:
            print("[BLESensors] Bluetooth unauthorized")
        case .unsupported:
            print("[BLESensors] Bluetooth unsupported on this device")
        case .resetting:
            print("[BLESensors] Bluetooth resetting")
        case .unknown:
            print("[BLESensors] Bluetooth state unknown")
        @unknown default:
            print("[BLESensors] Bluetooth state unhandled: \(central.state.rawValue)")
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let deviceName = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"

        notifyListeners("deviceDiscovered", data: [
            "id": peripheral.identifier.uuidString,
            "name": deviceName,
            "rssi": RSSI.intValue
        ])
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier

        if let pending = pendingConnections.removeValue(forKey: uuid) {
            let sensor = FootSensor(peripheral: peripheral, side: pending.side)
            connectedSensors[uuid] = sensor

            notifyListeners("deviceConnected", data: [
                "id": uuid.uuidString,
                "side": pending.side,
                "name": sensor.name
            ])

            // Discover all services to find IMU and battery characteristics
            peripheral.discoverServices(nil)

            pending.call.resolve(["connected": true])
        } else {
            // Reconnection scenario: sensor was already tracked
            if let sensor = connectedSensors[uuid] {
                notifyListeners("deviceConnected", data: [
                    "id": uuid.uuidString,
                    "side": sensor.side,
                    "name": sensor.name
                ])
                peripheral.discoverServices(nil)
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let uuid = peripheral.identifier
        let errorMessage = error?.localizedDescription ?? "Unknown connection failure"

        if let pending = pendingConnections.removeValue(forKey: uuid) {
            pending.call.reject("Failed to connect: \(errorMessage)")
        }

        print("[BLESensors] Failed to connect to \(uuid): \(errorMessage)")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let uuid = peripheral.identifier
        let reason = error?.localizedDescription ?? "Disconnected"

        if let sensor = connectedSensors[uuid] {
            notifyListeners("deviceDisconnected", data: [
                "id": uuid.uuidString,
                "side": sensor.side,
                "reason": reason
            ])

            // If the disconnection was unexpected (error is non-nil), attempt to reconnect
            if error != nil {
                print("[BLESensors] Unexpected disconnect from \(sensor.name) (\(sensor.side)). Attempting reconnect...")
                central.connect(peripheral, options: nil)
            } else {
                connectedSensors.removeValue(forKey: uuid)
            }
        }
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[BLESensors] Service discovery error: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            // Discover all characteristics for each service
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            print("[BLESensors] Characteristic discovery error: \(error.localizedDescription)")
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

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BLESensors] Characteristic update error: \(error.localizedDescription)")
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

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BLESensors] Notification state error for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        let state = characteristic.isNotifying ? "enabled" : "disabled"
        print("[BLESensors] Notifications \(state) for \(characteristic.uuid) on \(peripheral.name ?? "unknown")")
    }

    // MARK: - Data Parsing

    /// Parse battery level from characteristic data.
    private func handleBatteryUpdate(sensor: FootSensor, data: Data?) {
        guard let data = data, !data.isEmpty else { return }

        let level = Int(data[0])
        sensor.batteryLevel = level

        notifyListeners("batteryUpdate", data: [
            "id": sensor.peripheral.identifier.uuidString,
            "side": sensor.side,
            "level": level
        ])
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

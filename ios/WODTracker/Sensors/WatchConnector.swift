import Foundation
import WatchConnectivity
import Combine

// MARK: - WatchConnector

final class WatchConnector: NSObject, ObservableObject, WCSessionDelegate {

    // MARK: - Published Properties

    @Published var isWatchReachable = false
    @Published var isWatchPaired = false

    // MARK: - Callbacks

    /// Called when a batch of sensor samples arrives from the watch.
    var onWatchSensorBatch: (([SensorSample]) -> Void)?

    /// Called when the watch sends an action (e.g., "startSet", "pauseWorkout").
    /// Parameters: action name, optional payload dictionary.
    var onWatchAction: ((String, [String: Any]?) -> Void)?

    // MARK: - Time Sync

    /// Offset in seconds: watchTime + offset = phoneTime.
    /// Computed during the time sync handshake at session start.
    private(set) var clockOffset: TimeInterval = 0

    // MARK: - Private State

    private var wcSession: WCSession?

    // MARK: - Initializer

    override init() {
        super.init()
        setupWatchConnectivity()
    }

    // MARK: - Setup

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    // MARK: - Public Methods

    /// Send the current rep count and exercise info to the watch for display.
    func sendRepUpdate(repCount: Int, exerciseName: String, confidence: Double) {
        sendMessage([
            "type": "repUpdate",
            "repCount": repCount,
            "exerciseName": exerciseName,
            "confidence": confidence
        ])
    }

    /// Send a form alert to the watch (e.g., haptic + visual warning).
    func sendFormAlert(message: String, severity: String) {
        sendMessage([
            "type": "formAlert",
            "message": message,
            "severity": severity
        ])
    }

    /// Send a set transition event to the watch.
    /// `type` should be one of: "setStart", "restStart", "setEnd".
    func sendSetTransition(type: String) {
        sendMessage([
            "type": "setTransition",
            "transition": type
        ])
    }

    /// Send the current movement state to the watch.
    func sendMovementState(_ state: String) {
        sendMessage([
            "type": "movementState",
            "state": state
        ])
    }

    /// Initiate the time sync handshake. Sends the phone's current time
    /// and expects the watch to reply with its own timestamp.
    func performTimeSync() {
        let phoneSendTime = Date().timeIntervalSince1970

        wcSession?.sendMessage(
            ["type": "timeSync", "phoneSendTime": phoneSendTime],
            replyHandler: { [weak self] reply in
                guard let watchTime = reply["watchTime"] as? TimeInterval else { return }
                let phoneReceiveTime = Date().timeIntervalSince1970
                let roundTrip = phoneReceiveTime - phoneSendTime
                let estimatedWatchNow = watchTime + roundTrip / 2.0
                let offset = phoneReceiveTime - estimatedWatchNow
                self?.clockOffset = offset
                print("[WatchConnector] Time sync complete. Offset: \(offset)s, RTT: \(roundTrip)s")
            },
            errorHandler: { error in
                print("[WatchConnector] Time sync error: \(error.localizedDescription)")
            }
        )
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("[WatchConnector] WCSession activation error: \(error.localizedDescription)")
        }
        DispatchQueue.main.async { [weak self] in
            self?.isWatchPaired = session.isPaired
            self?.isWatchReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isWatchReachable = session.isReachable
        }
    }

    /// Receive messages from the Apple Watch companion app.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // Handle time sync requests from the watch
        if let type = message["type"] as? String, type == "timeSync" {
            replyHandler(["phoneTime": Date().timeIntervalSince1970])
            return
        }

        handleIncomingMessage(message)
        replyHandler([:])
    }

    // MARK: - Message Handling

    private func handleIncomingMessage(_ message: [String: Any]) {
        // Handle sensor data batches from the watch
        if let type = message["type"] as? String, type == "sensorBatch",
           let samplesArray = message["samples"] as? [[String: Any]] {
            let samples = samplesArray.compactMap { dict -> SensorSample? in
                guard let timestamp = dict["timestamp"] as? Double,
                      let ax = dict["ax"] as? Double,
                      let ay = dict["ay"] as? Double,
                      let az = dict["az"] as? Double else {
                    return nil
                }
                let gx = dict["gx"] as? Double ?? 0.0
                let gy = dict["gy"] as? Double ?? 0.0
                let gz = dict["gz"] as? Double ?? 0.0

                // Apply clock offset to align timestamps
                return SensorSample(
                    timestamp: timestamp + clockOffset,
                    ax: ax, ay: ay, az: az,
                    gx: gx, gy: gy, gz: gz
                )
            }
            if !samples.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onWatchSensorBatch?(samples)
                }
            }
            return
        }

        // Handle generic actions from the watch
        if let action = message["action"] as? String {
            let payload = message["payload"] as? [String: Any]
            DispatchQueue.main.async { [weak self] in
                self?.onWatchAction?(action, payload)
            }
        }
    }

    // MARK: - Helpers

    private func sendMessage(_ message: [String: Any]) {
        guard let session = wcSession, session.isReachable else { return }

        session.sendMessage(message, replyHandler: nil) { error in
            print("[WatchConnector] Send error: \(error.localizedDescription)")
        }
    }
}

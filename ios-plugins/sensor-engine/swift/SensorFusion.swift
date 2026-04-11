import Foundation

// MARK: - Data Types

/// Identifies which sensor source produced a reading.
enum SensorSource: String, CaseIterable {
    case leftFoot
    case rightFoot
    case watch
}

/// A single IMU reading: 3-axis accelerometer + 3-axis gyroscope.
struct SensorReading {
    let ax: Double
    let ay: Double
    let az: Double
    let gx: Double
    let gy: Double
    let gz: Double

    /// Accelerometer magnitude in g.
    var accelMagnitude: Double {
        return SignalProcessing.magnitude(x: ax, y: ay, z: az)
    }

    /// Gyroscope magnitude in deg/s.
    var gyroMagnitude: Double {
        return SignalProcessing.magnitude(x: gx, y: gy, z: gz)
    }

    func toDictionary() -> [String: Double] {
        return ["ax": ax, "ay": ay, "az": az, "gx": gx, "gy": gy, "gz": gz]
    }
}

/// A time-aligned frame that may contain readings from multiple sensor sources.
struct FusedSensorFrame {
    let timestamp: TimeInterval
    var leftFoot: SensorReading?
    var rightFoot: SensorReading?
    var watch: SensorReading?

    /// Returns the reading for the given source, if present.
    func reading(for source: SensorSource) -> SensorReading? {
        switch source {
        case .leftFoot: return leftFoot
        case .rightFoot: return rightFoot
        case .watch: return watch
        }
    }
}

// MARK: - Ring Buffer

/// Fixed-capacity ring buffer for timestamped sensor readings.
/// Overwrites oldest entries when full.
private struct SensorRingBuffer {
    private var buffer: [(timestamp: TimeInterval, reading: SensorReading)]
    private var head: Int = 0
    private var isFull: Bool = false
    let capacity: Int

    var count: Int {
        return isFull ? capacity : head
    }

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }

    mutating func append(timestamp: TimeInterval, reading: SensorReading) {
        if buffer.count < capacity {
            buffer.append((timestamp: timestamp, reading: reading))
            head = buffer.count
            if head == capacity {
                isFull = true
                head = 0
            }
        } else {
            buffer[head] = (timestamp: timestamp, reading: reading)
            head = (head + 1) % capacity
            isFull = true
        }
    }

    /// Returns all stored samples ordered by timestamp (oldest first).
    func orderedSamples() -> [(timestamp: TimeInterval, reading: SensorReading)] {
        guard count > 0 else { return [] }
        if !isFull {
            return Array(buffer[0..<head])
        }
        // Ring buffer is full: elements from head..end then 0..<head
        return Array(buffer[head..<capacity]) + Array(buffer[0..<head])
    }

    /// Returns samples within the last `duration` seconds from the newest sample.
    func samplesInWindow(durationSeconds: Double) -> [(timestamp: TimeInterval, reading: SensorReading)] {
        let ordered = orderedSamples()
        guard let latest = ordered.last else { return [] }
        let cutoff = latest.timestamp - durationSeconds
        return ordered.filter { $0.timestamp >= cutoff }
    }

    /// Returns the most recent sample, if any.
    func latestSample() -> (timestamp: TimeInterval, reading: SensorReading)? {
        guard count > 0 else { return nil }
        if !isFull {
            return buffer[head - 1]
        }
        let idx = head == 0 ? capacity - 1 : head - 1
        return buffer[idx]
    }
}

// MARK: - SensorFusionEngine

/// Merges data from multiple sensor sources into time-aligned frames.
/// Maintains per-source ring buffers and performs nearest-neighbor time alignment.
final class SensorFusionEngine {

    /// Maximum time difference (seconds) for matching samples across sources.
    private let alignmentToleranceSeconds: Double = 0.020  // 20ms

    /// Ring buffers for each sensor source.
    /// Capacity of 500 samples = ~10 seconds at 50 Hz.
    private var buffers: [SensorSource: SensorRingBuffer] = [:]

    /// Lock for thread-safe access.
    private let lock = NSLock()

    init(bufferCapacity: Int = 500) {
        for source in SensorSource.allCases {
            buffers[source] = SensorRingBuffer(capacity: bufferCapacity)
        }
    }

    // MARK: - Ingestion

    /// Add a sensor sample to the appropriate ring buffer.
    func addSample(source: SensorSource, timestamp: TimeInterval, reading: SensorReading) {
        lock.lock()
        defer { lock.unlock() }
        buffers[source]?.append(timestamp: timestamp, reading: reading)
    }

    // MARK: - Retrieval

    /// Returns raw samples from a single source within the last N seconds.
    func getSourceWindow(
        source: SensorSource,
        durationSeconds: Double
    ) -> [(timestamp: TimeInterval, reading: SensorReading)] {
        lock.lock()
        defer { lock.unlock() }
        return buffers[source]?.samplesInWindow(durationSeconds: durationSeconds) ?? []
    }

    /// Returns time-aligned fused frames from all active sources for the last N seconds.
    /// Uses the source with the most samples as the primary timeline.
    /// Other sources are matched via nearest-neighbor within the alignment tolerance.
    func getWindow(durationSeconds: Double) -> [FusedSensorFrame] {
        lock.lock()
        defer { lock.unlock() }

        // Collect windowed samples from each source
        var sourceWindows: [SensorSource: [(timestamp: TimeInterval, reading: SensorReading)]] = [:]
        var maxCount = 0
        var primarySource: SensorSource = .leftFoot

        for source in SensorSource.allCases {
            let window = buffers[source]?.samplesInWindow(durationSeconds: durationSeconds) ?? []
            sourceWindows[source] = window
            if window.count > maxCount {
                maxCount = window.count
                primarySource = source
            }
        }

        guard let primarySamples = sourceWindows[primarySource], !primarySamples.isEmpty else {
            return []
        }

        // Build fused frames using the primary source's timestamps
        var frames: [FusedSensorFrame] = []
        frames.reserveCapacity(primarySamples.count)

        // Pre-compute search indices for secondary sources
        var searchIndices: [SensorSource: Int] = [:]
        for source in SensorSource.allCases where source != primarySource {
            searchIndices[source] = 0
        }

        for primary in primarySamples {
            var frame = FusedSensorFrame(timestamp: primary.timestamp)

            // Set the primary source reading
            setReading(on: &frame, source: primarySource, reading: primary.reading)

            // Find nearest neighbor for each secondary source
            for source in SensorSource.allCases where source != primarySource {
                guard let window = sourceWindows[source], !window.isEmpty else { continue }

                let startIdx = searchIndices[source] ?? 0
                if let (matchIdx, matchReading) = findNearest(
                    in: window,
                    targetTime: primary.timestamp,
                    startSearchAt: startIdx,
                    tolerance: alignmentToleranceSeconds
                ) {
                    setReading(on: &frame, source: source, reading: matchReading)
                    // Advance search index for next iteration (samples are ordered)
                    searchIndices[source] = matchIdx
                }
            }

            frames.append(frame)
        }

        return frames
    }

    /// Returns the most recent timestamp across all sources, or nil if no data.
    func latestTimestamp() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }

        var latest: TimeInterval?
        for source in SensorSource.allCases {
            if let sample = buffers[source]?.latestSample() {
                if latest == nil || sample.timestamp > latest! {
                    latest = sample.timestamp
                }
            }
        }
        return latest
    }

    // MARK: - Helpers

    private func setReading(on frame: inout FusedSensorFrame, source: SensorSource, reading: SensorReading) {
        switch source {
        case .leftFoot: frame.leftFoot = reading
        case .rightFoot: frame.rightFoot = reading
        case .watch: frame.watch = reading
        }
    }

    /// Nearest-neighbor search in an ordered array. Returns (index, reading) if within tolerance.
    private func findNearest(
        in samples: [(timestamp: TimeInterval, reading: SensorReading)],
        targetTime: TimeInterval,
        startSearchAt: Int,
        tolerance: Double
    ) -> (Int, SensorReading)? {
        guard !samples.isEmpty else { return nil }

        var bestIdx = startSearchAt
        var bestDiff = abs(samples[bestIdx].timestamp - targetTime)

        // Linear scan forward from the start index
        var i = startSearchAt + 1
        while i < samples.count {
            let diff = abs(samples[i].timestamp - targetTime)
            if diff < bestDiff {
                bestDiff = diff
                bestIdx = i
            } else if samples[i].timestamp > targetTime + tolerance {
                // Past the target + tolerance, no point continuing
                break
            }
            i += 1
        }

        if bestDiff <= tolerance {
            return (bestIdx, samples[bestIdx].reading)
        }
        return nil
    }
}

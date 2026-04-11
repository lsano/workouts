import Foundation
import Accelerate

/// Utility class for digital signal processing operations on sensor data.
/// Uses the Accelerate framework (vDSP) for FFT-based frequency analysis.
final class SignalProcessing {

    // MARK: - Vector Magnitude

    /// Compute the Euclidean magnitude of a 3D vector.
    static func magnitude(x: Double, y: Double, z: Double) -> Double {
        return sqrt(x * x + y * y + z * z)
    }

    /// Compute element-wise magnitude from three axis arrays.
    static func magnitudeArray(ax: [Double], ay: [Double], az: [Double]) -> [Double] {
        let count = min(ax.count, ay.count, az.count)
        guard count > 0 else { return [] }

        var result = [Double](repeating: 0.0, count: count)
        for i in 0..<count {
            result[i] = magnitude(x: ax[i], y: ay[i], z: az[i])
        }
        return result
    }

    // MARK: - Butterworth Low-Pass Filter

    /// Second-order Butterworth low-pass filter (IIR).
    /// Processes samples in-order and returns the filtered output.
    static func lowPassFilter(samples: [Double], cutoffHz: Double, sampleRateHz: Double) -> [Double] {
        guard samples.count > 1, cutoffHz > 0, sampleRateHz > 0 else { return samples }

        // Bilinear transform pre-warped frequency
        let omega = tan(.pi * cutoffHz / sampleRateHz)
        let omega2 = omega * omega
        let sqrt2 = sqrt(2.0)

        // Second-order Butterworth coefficients (normalized)
        let k = 1.0 + sqrt2 * omega + omega2
        let b0 = omega2 / k
        let b1 = 2.0 * omega2 / k
        let b2 = omega2 / k
        let a1 = 2.0 * (omega2 - 1.0) / k
        let a2 = (1.0 - sqrt2 * omega + omega2) / k

        var output = [Double](repeating: 0.0, count: samples.count)
        // State variables for the direct-form II transposed structure
        var x1 = 0.0, x2 = 0.0  // previous inputs
        var y1 = 0.0, y2 = 0.0  // previous outputs

        for i in 0..<samples.count {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            output[i] = y0

            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }

        return output
    }

    // MARK: - Gravity Removal

    /// Complementary high-pass filter to separate gravity from accelerometer data.
    /// `alpha` controls the cutoff: typical value 0.8-0.95. Higher alpha retains more
    /// high-frequency content (motion) and removes more gravity.
    static func removeGravity(
        samples: [(ax: Double, ay: Double, az: Double)],
        alpha: Double = 0.9
    ) -> [(ax: Double, ay: Double, az: Double)] {
        guard !samples.isEmpty else { return [] }

        var result = [(ax: Double, ay: Double, az: Double)]()
        result.reserveCapacity(samples.count)

        // Gravity estimate starts from the first sample
        var gx = samples[0].ax
        var gy = samples[0].ay
        var gz = samples[0].az

        for sample in samples {
            // Update gravity estimate using complementary filter
            gx = alpha * gx + (1.0 - alpha) * sample.ax
            gy = alpha * gy + (1.0 - alpha) * sample.ay
            gz = alpha * gz + (1.0 - alpha) * sample.az

            // Linear acceleration = raw - gravity
            result.append((ax: sample.ax - gx, ay: sample.ay - gy, az: sample.az - gz))
        }

        return result
    }

    // MARK: - FFT Dominant Frequency

    /// Uses Accelerate vDSP to compute an FFT and return the dominant frequency in Hz.
    /// The signal is zero-padded to the next power of two if necessary.
    static func dominantFrequency(signal: [Double], sampleRateHz: Double) -> Double {
        guard signal.count >= 4, sampleRateHz > 0 else { return 0.0 }

        // Determine FFT length (next power of 2)
        let log2n = vDSP_Length(ceil(log2(Double(signal.count))))
        let n = Int(1 << log2n)
        let halfN = n / 2

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return 0.0
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Zero-pad signal to length n
        var paddedSignal = [Double](repeating: 0.0, count: n)
        for i in 0..<min(signal.count, n) {
            paddedSignal[i] = signal[i]
        }

        // Apply Hann window to reduce spectral leakage
        var window = [Double](repeating: 0.0, count: n)
        vDSP_hann_windowD(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmulD(paddedSignal, 1, window, 1, &paddedSignal, 1, vDSP_Length(n))

        // Convert to split complex format
        var realPart = [Double](repeating: 0.0, count: halfN)
        var imagPart = [Double](repeating: 0.0, count: halfN)

        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPDoubleSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                // Pack interleaved real data into split complex form
                paddedSignal.withUnsafeBufferPointer { signalPtr in
                    let signalAsComplex = UnsafeRawPointer(signalPtr.baseAddress!)
                        .bindMemory(to: DSPDoubleComplex.self, capacity: halfN)
                    vDSP_ctozD(signalAsComplex, 2, &splitComplex, 1, vDSP_Length(halfN))
                }

                // Perform forward FFT
                vDSP_fft_zripD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Compute magnitudes
                var magnitudes = [Double](repeating: 0.0, count: halfN)
                vDSP_zvmagsD(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

                // Find the peak bin (skip bin 0 = DC component)
                var maxVal: Double = 0.0
                var maxIdx: vDSP_Length = 0
                if magnitudes.count > 1 {
                    // Search from index 1 to skip DC
                    let startPtr = UnsafePointer(magnitudes) + 1
                    let searchCount = vDSP_Length(magnitudes.count - 1)
                    vDSP_maxviD(startPtr, 1, &maxVal, &maxIdx, searchCount)
                    maxIdx += 1 // Adjust for the offset
                }

                // Convert bin index to frequency
                let freqResolution = sampleRateHz / Double(n)
                // Store result via capture (we'll read it after the closure)
                paddedSignal[0] = Double(maxIdx) * freqResolution
            }
        }

        return paddedSignal[0]
    }

    // MARK: - Peak Detection

    /// Adaptive peak detection. Returns indices of samples that are local maxima
    /// exceeding `minHeight` and separated by at least `minDistance` samples.
    static func findPeaks(signal: [Double], minHeight: Double, minDistance: Int) -> [Int] {
        guard signal.count >= 3 else { return [] }

        var peaks: [Int] = []
        let distance = max(minDistance, 1)

        for i in 1..<(signal.count - 1) {
            // Check local maximum
            if signal[i] > signal[i - 1] && signal[i] > signal[i + 1] && signal[i] >= minHeight {
                // Check minimum distance from last peak
                if let lastPeak = peaks.last {
                    if (i - lastPeak) >= distance {
                        peaks.append(i)
                    } else if signal[i] > signal[lastPeak] {
                        // Replace the previous peak if this one is higher
                        peaks[peaks.count - 1] = i
                    }
                } else {
                    peaks.append(i)
                }
            }
        }

        return peaks
    }

    // MARK: - Rolling Statistics

    /// Compute a centered rolling mean with the given window size.
    static func rollingMean(signal: [Double], windowSize: Int) -> [Double] {
        guard !signal.isEmpty else { return [] }
        let w = max(windowSize, 1)
        guard signal.count >= w else {
            let mean = signal.reduce(0.0, +) / Double(signal.count)
            return [Double](repeating: mean, count: signal.count)
        }

        var result = [Double](repeating: 0.0, count: signal.count)

        // Compute initial window sum
        var windowSum = 0.0
        for i in 0..<w {
            windowSum += signal[i]
        }

        // Assign the first value for the window
        let halfW = w / 2
        result[halfW] = windowSum / Double(w)

        // Slide the window
        for i in (w)..<signal.count {
            windowSum += signal[i] - signal[i - w]
            let center = i - halfW
            if center < signal.count {
                result[center] = windowSum / Double(w)
            }
        }

        // Fill edges by extending nearest computed value
        let firstValid = halfW
        let lastValid = signal.count - 1 - (w - 1 - halfW)
        for i in 0..<firstValid {
            result[i] = result[firstValid]
        }
        for i in (lastValid + 1)..<signal.count {
            result[i] = result[max(lastValid, 0)]
        }

        return result
    }

    /// Compute a centered rolling standard deviation with the given window size.
    static func rollingStdDev(signal: [Double], windowSize: Int) -> [Double] {
        guard !signal.isEmpty else { return [] }
        let w = max(windowSize, 1)
        guard signal.count >= w else {
            let v = variance(signal: signal)
            let std = sqrt(v)
            return [Double](repeating: std, count: signal.count)
        }

        let means = rollingMean(signal: signal, windowSize: w)
        var result = [Double](repeating: 0.0, count: signal.count)
        let halfW = w / 2

        for i in 0..<signal.count {
            let start = max(0, i - halfW)
            let end = min(signal.count - 1, i + (w - 1 - halfW))
            let count = end - start + 1
            guard count > 0 else { continue }

            var sumSqDiff = 0.0
            let mean = means[i]
            for j in start...end {
                let diff = signal[j] - mean
                sumSqDiff += diff * diff
            }
            result[i] = sqrt(sumSqDiff / Double(count))
        }

        return result
    }

    // MARK: - Variance

    /// Population variance of a signal.
    static func variance(signal: [Double]) -> Double {
        guard !signal.isEmpty else { return 0.0 }
        let n = Double(signal.count)
        var mean: Double = 0.0
        vDSP_meanvD(signal, 1, &mean, vDSP_Length(signal.count))

        var sumSqDiff = 0.0
        for value in signal {
            let diff = value - mean
            sumSqDiff += diff * diff
        }
        return sumSqDiff / n
    }
}

import Accelerate
import Foundation

/// Turns a stream of mono samples into a few smoothed 0...1 band levels.
/// Not thread-safe; used from the audio queue only.
final class SpectrumAnalyzer {
    /// Frequency ranges (Hz) of the bars, bass to treble.
    static let bands: [ClosedRange<Float>] = [40...150, 150...600, 600...2500, 2500...10000]
    /// Music has far less energy up high, so higher bands get a boost (dB).
    private static let bandGain: [Float] = [0, 4, 9, 14]
    private static let floorDB: Float = -62
    private static let ceilingDB: Float = -14

    private let size = 1024
    private let log2n: vDSP_Length = 10
    private let setup: FFTSetup
    private let window: [Float]
    private var samples: [Float] = []
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]

    private(set) var levels = [Float](repeating: 0, count: SpectrumAnalyzer.bands.count)

    init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
        magnitudes = [Float](repeating: 0, count: size / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Adds samples; returns true when the levels were updated.
    @discardableResult
    func process(_ newSamples: UnsafeBufferPointer<Float>, sampleRate: Float) -> Bool {
        samples.append(contentsOf: newSamples)
        guard samples.count >= size else { return false }
        if samples.count > size { samples.removeFirst(samples.count - size) }

        let windowed = vDSP.multiply(samples, window)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }

        // zrip doubles the output and the Hann window halves it, so amplitude ≈ 2·mag / N.
        let binWidth = sampleRate / Float(size)
        for (index, band) in Self.bands.enumerated() {
            let low = max(1, Int(band.lowerBound / binWidth))
            let high = min(size / 2 - 1, max(low, Int(band.upperBound / binWidth)))
            var sumOfSquares: Float = 0
            for bin in low...high {
                let amplitude = 2 * magnitudes[bin] / Float(size)
                sumOfSquares += amplitude * amplitude
            }
            let rms = sqrt(sumOfSquares / Float(high - low + 1))
            let db = 20 * log10(max(rms, 1e-9)) + Self.bandGain[index]
            let target = min(max((db - Self.floorDB) / (Self.ceilingDB - Self.floorDB), 0), 1)
            // Jump up instantly, fall back smoothly.
            levels[index] = target > levels[index] ? target : levels[index] * 0.82 + target * 0.18
        }
        samples.removeFirst(size / 2)  // 50% overlap between frames
        return true
    }
}

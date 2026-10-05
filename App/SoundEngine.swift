import AVFoundation

/// Synthesised needle drop and vinyl crackle, matching the prototype's Web Audio recipe.
final class SoundEngine {
    static let shared = SoundEngine()

    var enabled = true { didSet { if !enabled { crackle(false) } } }

    private let engine = AVAudioEngine()
    private let dropNode = AVAudioPlayerNode()
    private let crackleNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private lazy var dropBuffer = makeNeedleDrop()
    private lazy var crackleBuffer = makeCrackle()
    private var crackling = false
    private var fadeTimer: Timer?
    private var stopWork: DispatchWorkItem?

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(dropNode)
        engine.attach(crackleNode)
        engine.connect(dropNode, to: engine.mainMixerNode, format: format)
        engine.connect(crackleNode, to: engine.mainMixerNode, format: format)
        crackleNode.volume = 0
    }

    private func start() -> Bool {
        stopWork?.cancel()
        if engine.isRunning { return true }
        do { try engine.start(); return true } catch { NSLog("Sound: \(error.localizedDescription)"); return false }
    }

    private func scheduleStop() {
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.crackling else { return }
            self.engine.pause()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func needleDrop() {
        guard enabled, start(), let buf = dropBuffer else { return }
        dropNode.scheduleBuffer(buf, at: nil, options: .interrupts)
        dropNode.play()
        if !crackling { scheduleStop() }
    }

    func crackle(_ on: Bool) {
        if on {
            guard enabled, !crackling, start(), let buf = crackleBuffer else { return }
            crackling = true
            crackleNode.scheduleBuffer(buf, at: nil, options: .loops)
            crackleNode.play()
            fade(to: 1, over: 0.6) // the 0.14 gain is baked into the buffer
        } else {
            guard crackling else { return }
            crackling = false
            fade(to: 0, over: 0.35) { [weak self] in
                self?.crackleNode.stop()
                self?.scheduleStop()
            }
        }
    }

    private func fade(to target: Float, over seconds: Double, done: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        let start = crackleNode.volume, began = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let k = min(1, Date().timeIntervalSince(began) / seconds)
            self.crackleNode.volume = start + (target - start) * Float(k)
            if k >= 1 { t.invalidate(); done?() }
        }
    }

    // MARK: Synthesis

    /// 90→38 Hz sine thump (180 ms, peak 0.22) plus an 80 ms band-passed (2.4 kHz) noise tick.
    private func makeNeedleDrop() -> AVAudioPCMBuffer? {
        let sr = format.sampleRate, n = Int(sr * 0.22)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        var phase = 0.0
        var noise = [Float](repeating: 0, count: Int(sr * 0.08))
        for k in 0..<noise.count { noise[k] = Float.random(in: -1...1) * pow(1 - Float(k) / Float(noise.count), 3) }
        let tick = Biquad.bandpass(freq: 2400, q: 0.8, sampleRate: sr).run(noise)
        for i in 0..<n {
            let t = Double(i) / sr
            let f = t < 0.14 ? 90 * pow(38.0 / 90.0, t / 0.14) : 38
            phase += 2 * .pi * f / sr
            let env: Double
            if t < 0.008 { env = 0.0001 * pow(0.22 / 0.0001, t / 0.008) }
            else if t < 0.18 { env = 0.22 * pow(0.0001 / 0.22, (t - 0.008) / 0.172) }
            else { env = 0 }
            var s = Float(sin(phase) * env)
            if i < tick.count { s += tick[i] * 0.12 }
            ch[i] = s
        }
        return buf
    }

    /// 3 s loop of sparse clicks (p = 0.00035) plus faint hiss, high-passed at 900 Hz, gain 0.14.
    private func makeCrackle() -> AVAudioPCMBuffer? {
        let sr = format.sampleRate, n = Int(sr * 3)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)), let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        var raw = [Float](repeating: 0, count: n)
        for i in 0..<n {
            raw[i] = (Float.random(in: 0..<1) < 0.00035 ? Float.random(in: -1...1) * 0.8 : 0) + Float.random(in: -1...1) * 0.003
        }
        let out = Biquad.highpass(freq: 900, q: 0.707, sampleRate: sr).run(raw)
        for i in 0..<n { ch[i] = out[i] * 0.14 }
        return buf
    }
}

/// RBJ cookbook biquad, used offline to shape the synthesized buffers.
private struct Biquad {
    var b0, b1, b2, a1, a2: Double

    static func bandpass(freq: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * .pi * freq / sampleRate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }

    static func highpass(freq: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * .pi * freq / sampleRate, alpha = sin(w) / (2 * q), c = cos(w), a0 = 1 + alpha
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    func run(_ x: [Float]) -> [Float] {
        var y = [Float](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let xi = Double(x[i])
            let yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = yi
            y[i] = Float(yi)
        }
        return y
    }
}

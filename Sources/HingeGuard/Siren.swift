import AVFoundation
import Foundation

/// Yüksek sesli siren üretir ve sistem sesini maksimuma çeker.
final class Siren {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var phase = 0.0
    private var time = 0.0
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        Siren.forceMaxVolume()

        phase = 0
        time = 0
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sweepPeriod = 1.0 / 1.5
        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                // Uzun süre çalışınca hassasiyet kaybolmasın diye periyotla sarılır
                self.time = (self.time + 1.0 / sampleRate).truncatingRemainder(dividingBy: sweepPeriod)
                // 400-1400 Hz arasında inip çıkan "wail" sireni
                let freq = 900.0 + 500.0 * sin(2.0 * .pi * 1.5 * self.time)
                self.phase = (self.phase + 2.0 * .pi * freq / sampleRate)
                    .truncatingRemainder(dividingBy: 2.0 * .pi)
                let value = Float(sin(self.phase)) * 0.95
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        engine.attach(sourceNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        node = sourceNode
        do {
            try engine.start()
        } catch {
            NSLog("HingeGuard: siren başlatılamadı: \(error)")
        }
    }

    func stop() {
        guard running else { return }
        running = false
        engine.stop()
        // Bir sonraki alarmda node'lar birikmesin
        if let node {
            engine.detach(node)
            self.node = nil
        }
    }

    /// Sessize alınmış ya da kısılmış olsa bile sesi tam açar.
    static func forceMaxVolume() {
        let script = "set volume without output muted\nset volume output volume 100"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

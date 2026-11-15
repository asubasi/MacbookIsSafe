import Combine
import Foundation

/// Panel açıkken sensörleri sık aralıklarla okuyup arayüze yayınlar.
final class SensorMonitor: ObservableObject {
    struct Sample: Identifiable {
        let id: Int
        let time: Date
        let value: Double
    }

    // Menteşe
    @Published private(set) var angle: Double?
    @Published private(set) var rawBytes: [UInt8] = []
    @Published private(set) var angleHistory: [Sample] = []
    @Published private(set) var sampleRate: Double = 0

    // İvmeölçer
    @Published private(set) var accel: Accelerometer.Snapshot?
    @Published private(set) var motionHistory: [Sample] = []
    @Published private(set) var accelRate: Double = 0

    let sensorAvailable: Bool
    let accelAvailable: Bool
    let interval: TimeInterval = 0.05          // 20 Hz arayüz güncellemesi
    let historyWindow: TimeInterval = 30       // grafikte son 30 sn

    private let sensor: LidAngleSensor?
    private let accelerometer: Accelerometer?
    private let accelConsumer: Accelerometer.Consumer?
    private var timer: Timer?
    private var nextID = 0
    private var readsInWindow = 0
    private var accelReportsAtWindowStart = 0
    private var rateWindowStart = Date()

    init(sensor: LidAngleSensor?, accelerometer: Accelerometer?) {
        self.sensor = sensor
        self.accelerometer = accelerometer
        self.sensorAvailable = sensor != nil
        self.accelAvailable = accelerometer != nil
        self.accelConsumer = accelerometer?.makeConsumer()
    }

    /// Alarm eşikleri; grafikte çizgi olarak gösterilir.
    var motionThreshold: Double?

    var minAngle: Double? { angleHistory.map(\.value).min() }
    var maxAngle: Double? { angleHistory.map(\.value).max() }
    var peakMotion: Double? { motionHistory.map(\.value).max() }

    func start() {
        guard timer == nil else { return }
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func resetHistory() {
        angleHistory.removeAll()
        motionHistory.removeAll()
    }

    private func poll() {
        let now = Date()

        if let sensor {
            let reading = sensor.read()
            angle = reading.angle
            if reading.rawBytes != rawBytes { rawBytes = reading.rawBytes }
            if let value = reading.angle {
                append(value, at: now, to: &angleHistory)
                readsInWindow += 1
            }
        }

        if let accelerometer, let accelConsumer {
            let snapshot = accelerometer.takeSnapshot(for: accelConsumer)
            accel = snapshot
            append(snapshot.motion, at: now, to: &motionHistory)
        }

        let elapsed = now.timeIntervalSince(rateWindowStart)
        if elapsed >= 1 {
            sampleRate = Double(readsInWindow) / elapsed
            let reports = accel?.reportCount ?? 0
            accelRate = Double(reports &- accelReportsAtWindowStart) / elapsed
            accelReportsAtWindowStart = reports
            readsInWindow = 0
            rateWindowStart = now
        }
    }

    private func append(_ value: Double, at time: Date, to history: inout [Sample]) {
        history.append(Sample(id: nextID, time: time, value: value))
        nextID += 1
        let cutoff = time.addingTimeInterval(-historyWindow)
        if let firstKept = history.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            history.removeFirst(firstKept)
        }
    }
}

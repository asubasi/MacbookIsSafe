import Combine
import Foundation
import IOKit.pwr_mgt

enum AlarmState: Equatable {
    case disarmed
    case arming(until: Date)   // Kullanıcı uzaklaşsın diye geri sayım
    case armed
    case grace(until: Date)    // Alarm öncesi kısa devre dışı bırakma penceresi
    case alarming
}

/// Alarmın durum makinesi: disarmed -> arming -> armed -> grace -> alarming
final class AlarmController: ObservableObject {
    // Ayarlar (sonra arayüzden değiştirilebilir)
    var armingDelay: TimeInterval = 10
    var graceDelay: TimeInterval = 5
    var angleThreshold: Double = 4.0       // derece
    var requiredHits = 3                   // art arda kaç ölçüm sapmalı (gürültü filtresi)
    // İvmeölçer: masada 200 ms'lik tepe gürültü 1-5 mg ölçüldü (M4 Pro)
    var motionThreshold: Double = 0.030    // g (30 mg)
    var motionRequiredHits = 2             // art arda kaç 200 ms penceresi; tek vuruş tetiklemesin
    var tiltThreshold: Double = 8.0        // derece, kurulduğu andaki duruşa göre
    var ntfyTopic: String? = ProcessInfo.processInfo.environment["HINGEGUARD_NTFY_TOPIC"]

    private(set) var state: AlarmState = .disarmed {
        willSet { objectWillChange.send() }
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((AlarmState) -> Void)?
    var sensorAvailable: Bool { sensor != nil }

    private let sensor: LidAngleSensor?
    private let accelerometer: Accelerometer?
    private let accelConsumer: Accelerometer.Consumer?
    private let power = PowerMonitor()
    private let siren = Siren()

    private var timer: Timer?
    private var baselineAngle: Double?
    private var watchPower = false
    private var hits = 0
    private var motionHits = 0
    private var baselineGravity: (x: Double, y: Double, z: Double)?
    private var lastVolumeEnforce = Date.distantPast
    private var sleepAssertion: IOPMAssertionID = 0
    private(set) var lastReason = ""
    /// Son kurma denemesi neden başarısız oldu (menüde gösterilir).
    private(set) var armError: String? {
        willSet { objectWillChange.send() }
    }
    /// Aktifken hangi algılayıcılar çalışıyor.
    private(set) var watchingAngle = false
    var watchingPower: Bool { watchPower }
    var watchingMotion: Bool { baselineGravity != nil }

    init(sensor: LidAngleSensor?, accelerometer: Accelerometer?) {
        self.sensor = sensor
        self.accelerometer = accelerometer
        self.accelConsumer = accelerometer?.makeConsumer()
        power.onUnplug = { [weak self] in
            guard let self, self.state == .armed, self.watchPower else { return }
            self.trigger(reason: "Güç kablosu çekildi")
        }
    }

    // MARK: - Dışarıya açık işlemler

    func arm() {
        guard state == .disarmed else { return }
        armError = nil
        // Algılayacak hiçbir şey yoksa sahte bir güven hissi verme
        guard sensor?.angle() != nil || accelerometerIsLive() || PowerMonitor.isOnAC() else {
            armError = "Kurulamadı: hiçbir sensör okunamıyor ve şarj kablosu takılı değil"
            onStateChange?(state)
            return
        }
        preventSleep()
        power.start()
        state = .arming(until: Date().addingTimeInterval(armingDelay))
        startTimer()
    }

    /// Geri sayım sırasında iptal: kimlik doğrulama gerekmez.
    func cancelArming() {
        guard case .arming = state else { return }
        shutDown()
    }

    /// Armed / grace / alarming durumlarında çağrılır; çağıran önce kimlik doğrulamalıdır.
    func disarm() {
        shutDown()
    }

    // MARK: - İç mantık

    private func startTimer() {
        timer?.invalidate()
        // .common modu: menü açıkken (event tracking) de çalışmaya devam etsin.
        // Aksi halde hırsız menüyü açık tutarak alarmı dondurabilir.
        let newTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        let now = Date()
        switch state {
        case .disarmed:
            break

        case .arming(let until):
            if now >= until {
                baselineAngle = sensor?.angle()
                watchPower = power.startedOnAC
                watchingAngle = baselineAngle != nil
                baselineGravity = nil
                if accelerometerIsLive(), let accelerometer, let accelConsumer {
                    // Geri sayım sırasındaki hareketleri (uzaklaşırken masaya çarpma vs.) unut
                    let snapshot = accelerometer.takeSnapshot(for: accelConsumer)
                    baselineGravity = (snapshot.gravityX, snapshot.gravityY, snapshot.gravityZ)
                }
                hits = 0
                motionHits = 0
                // Geri sayım sırasında kablo çekildiyse ve sensör yoksa izlenecek bir şey kalmadı
                guard watchingAngle || watchingMotion || watchPower else {
                    shutDown()
                    armError = "Kurulamadı: izlenecek sensör kalmadı (kablo çekildi mi?)"
                    onStateChange?(state)
                    return
                }
                state = .armed
            }

        case .armed:
            checkAngle()
            if state == .armed { checkMotion() }

        case .grace(let until):
            if now >= until {
                startAlarm()
            }

        case .alarming:
            // Biri sesi kısarsa tekrar tam aç
            if now.timeIntervalSince(lastVolumeEnforce) > 2 {
                Siren.forceMaxVolume()
                lastVolumeEnforce = now
            }
        }
    }

    private func checkAngle() {
        guard let baseline = baselineAngle, let angle = sensor?.angle() else { return }
        if abs(angle - baseline) > angleThreshold {
            hits += 1
            if hits >= requiredHits {
                trigger(reason: String(format: "Menteşe açısı değişti (%.0f° -> %.0f°)", baseline, angle))
            }
        } else {
            hits = 0
        }
    }

    private func checkMotion() {
        guard let base = baselineGravity, let accelerometer, let accelConsumer else { return }
        let snapshot = accelerometer.takeSnapshot(for: accelConsumer)

        // 1) Sarsıntı / kaldırma: yerçekimi dışı ivme art arda eşiği aşarsa
        if snapshot.motion > motionThreshold {
            motionHits += 1
            if motionHits >= motionRequiredHits {
                trigger(reason: String(format: "Hareket algılandı (%.0f mg)", snapshot.motion * 1000))
                return
            }
        } else {
            motionHits = 0
        }

        // 2) Yavaşça eğme: yerçekimi vektörü kurulduğu andakinden ne kadar saptı
        let tilt = Self.angleBetween(base, (snapshot.gravityX, snapshot.gravityY, snapshot.gravityZ))
        if tilt > tiltThreshold {
            trigger(reason: String(format: "Eğim değişti (%.0f°)", tilt))
        }
    }

    /// İvmeölçerden gerçekten veri geliyor mu?
    private func accelerometerIsLive() -> Bool {
        guard let accelerometer, let accelConsumer else { return false }
        return accelerometer.takeSnapshot(for: accelConsumer).reportCount > 0
    }

    private static func angleBetween(_ a: (x: Double, y: Double, z: Double),
                                     _ b: (x: Double, y: Double, z: Double)) -> Double {
        let dot = a.x * b.x + a.y * b.y + a.z * b.z
        let lengths = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            * (b.x * b.x + b.y * b.y + b.z * b.z).squareRoot()
        guard lengths > 0 else { return 0 }
        return acos(max(-1, min(1, dot / lengths))) * 180 / .pi
    }

    private func trigger(reason: String) {
        guard state == .armed else { return }
        lastReason = reason
        state = .grace(until: Date().addingTimeInterval(graceDelay))
    }

    private func startAlarm() {
        state = .alarming
        siren.start()
        sendPhoneNotification()
    }

    private func shutDown() {
        timer?.invalidate()
        timer = nil
        siren.stop()
        power.stop()
        allowSleep()
        baselineAngle = nil
        watchingAngle = false
        watchPower = false
        baselineGravity = nil
        hits = 0
        motionHits = 0
        state = .disarmed
    }

    // MARK: - Uyku engeli

    private func preventSleep() {
        guard sleepAssertion == 0 else { return }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "HingeGuard armed" as CFString,
            &sleepAssertion
        )
    }

    private func allowSleep() {
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    // MARK: - Telefon bildirimi (ntfy.sh)

    private func sendPhoneNotification() {
        guard let topic = ntfyTopic, !topic.isEmpty,
              let url = URL(string: "https://ntfy.sh/\(topic)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("MacBook alarmı!", forHTTPHeaderField: "Title")
        request.setValue("urgent", forHTTPHeaderField: "Priority")
        request.httpBody = "HingeGuard tetiklendi: \(lastReason)".data(using: .utf8)
        URLSession.shared.dataTask(with: request).resume()
    }
}

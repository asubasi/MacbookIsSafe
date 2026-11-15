import Charts
import SwiftUI

/// Ana panel: menteşe açısı ve ivmeölçer verisini canlı gösterir.
struct DashboardView: View {
    @ObservedObject var monitor: SensorMonitor
    let alarm: AlarmCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                alarm
                if monitor.sensorAvailable {
                    HingeCard(monitor: monitor)
                } else {
                    MissingCard(title: "Menteşe sensörü okunamadı")
                }
                if monitor.accelAvailable {
                    AccelCard(monitor: monitor)
                } else {
                    MissingCard(title: "İvmeölçer okunamadı")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("HingeGuard")
                .font(.title2.weight(.semibold))
            Spacer()
            LiveBadge(isLive: monitor.angle != nil || monitor.accelRate > 0)
        }
    }
}

// MARK: - Menteşe kartı

private struct HingeCard: View {
    @ObservedObject var monitor: SensorMonitor

    var body: some View {
        Card(title: "Menteşe açısı", rate: monitor.sampleRate) {
            HStack(spacing: 24) {
                HingeIllustration(angle: monitor.angle ?? 0)
                    .frame(width: 150, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    Text(degrees(monitor.angle))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.15), value: monitor.angle)
                    HStack(spacing: 14) {
                        Stat(label: "Min", value: degrees(monitor.minAngle))
                        Stat(label: "Maks", value: degrees(monitor.maxAngle))
                        Stat(label: "Fark", value: degrees(spread))
                    }
                }
            }

            HistoryChart(samples: monitor.angleHistory, window: monitor.historyWindow,
                         color: .accentColor, includesZero: false) { "\(Int($0))°" }
                .frame(height: 110)

            HStack {
                Text("Ham rapor").foregroundStyle(.secondary)
                Text(hex(monitor.rawBytes))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Geçmişi sıfırla") { monitor.resetHistory() }
                    .controlSize(.small)
            }
            .font(.caption)
        }
    }

    private var spread: Double? {
        guard let lo = monitor.minAngle, let hi = monitor.maxAngle else { return nil }
        return hi - lo
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.isEmpty ? "—" : bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// MARK: - İvmeölçer kartı

private struct AccelCard: View {
    @ObservedObject var monitor: SensorMonitor

    var body: some View {
        let a = monitor.accel
        Card(title: "İvmeölçer", rate: monitor.accelRate) {
            HStack(alignment: .center, spacing: 24) {
                BubbleLevel(pitch: a?.pitch ?? 0, roll: a?.roll ?? 0)
                    .frame(width: 110, height: 110)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Hareket").font(.caption).foregroundStyle(.secondary)
                        Text(milliG(a?.motion))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    AxisBar(label: "X", value: a?.x)
                    AxisBar(label: "Y", value: a?.y)
                    AxisBar(label: "Z", value: a?.z)
                }
            }

            HStack(spacing: 14) {
                Stat(label: "Eğim (öne/arkaya)", value: degrees(a?.pitch))
                Stat(label: "Eğim (yana)", value: degrees(a?.roll))
                Stat(label: "30 sn tepe", value: milliG(monitor.peakMotion))
            }

            HistoryChart(samples: monitor.motionHistory, window: monitor.historyWindow,
                         color: .orange, includesZero: true,
                         threshold: monitor.motionThreshold) { "\(Int($0 * 1000)) mg" }
                .frame(height: 110)

            Text("Hareket, yerçekimi çıkarıldıktan sonra kalan ivmedir; her 50 ms'deki en yüksek değer gösterilir. Alarm kuruluyken eşiğin art arda 0,4 sn aşılması ya da 8°'den fazla eğim alarmı tetikler.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func milliG(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f mg", value * 1000)
    }
}

/// Su terazisi: kabarcık eğime göre kayar (±30° kenara denk gelir).
private struct BubbleLevel: View {
    let pitch: Double
    let roll: Double

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            let bubble = radius * 0.28
            let travel = radius - bubble
            let dx = CGFloat(max(-1, min(1, roll / 30))) * travel
            let dy = CGFloat(max(-1, min(1, pitch / 30))) * travel
            ZStack {
                Circle().fill(Color.secondary.opacity(0.12))
                Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    .frame(width: bubble * 2.4, height: bubble * 2.4)
                Path { p in
                    p.move(to: CGPoint(x: radius, y: 0)); p.addLine(to: CGPoint(x: radius, y: radius * 2))
                    p.move(to: CGPoint(x: 0, y: radius)); p.addLine(to: CGPoint(x: radius * 2, y: radius))
                }
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                Circle()
                    .fill(Color.green.opacity(0.85))
                    .frame(width: bubble * 2, height: bubble * 2)
                    .offset(x: dx, y: dy)
                    .animation(.easeOut(duration: 0.1), value: dx)
                    .animation(.easeOut(duration: 0.1), value: dy)
            }
            .frame(width: radius * 2, height: radius * 2)
        }
    }
}

/// Bir eksenin değerini −1…+1 g aralığında ortadan dolan çubukla gösterir.
private struct AxisBar: View {
    let label: String
    let value: Double?

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.weight(.semibold)).frame(width: 12)
            GeometryReader { geo in
                let half = geo.size.width / 2
                let v = CGFloat(max(-1, min(1, value ?? 0)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: abs(v) * half)
                        .offset(x: v >= 0 ? half : half + v * half)
                    Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 1).offset(x: half)
                }
                .clipShape(Capsule())
            }
            .frame(width: 120, height: 8)
            Text(value.map { String(format: "%+.3f g", $0) } ?? "—")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: - Yan görünüş çizimi

/// MacBook'u yandan çizer: alt kasa sabit, kapak açıya göre döner.
private struct HingeIllustration: View {
    let angle: Double

    var body: some View {
        GeometryReader { geo in
            let hinge = CGPoint(x: geo.size.width * 0.42, y: geo.size.height - 8)
            let length = min(geo.size.width * 0.52, geo.size.height - 16)
            let clamped = min(max(angle, 0), 180)

            ZStack {
                AngleArc(center: hinge, radius: length * 0.38, degrees: clamped)
                    .fill(Color.accentColor.opacity(0.18))
                Path { p in
                    p.move(to: hinge)
                    p.addLine(to: CGPoint(x: hinge.x + length, y: hinge.y))
                }
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                LidLine(center: hinge, length: length, degrees: clamped)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 8)
                    .position(hinge)
            }
            .animation(.easeOut(duration: 0.12), value: clamped)
        }
    }
}

private struct LidLine: Shape {
    var center: CGPoint
    var length: CGFloat
    var degrees: Double

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radians = degrees * .pi / 180
        var p = Path()
        p.move(to: center)
        p.addLine(to: CGPoint(x: center.x + length * cos(radians),
                              y: center.y - length * sin(radians)))
        return p
    }
}

private struct AngleArc: Shape {
    var center: CGPoint
    var radius: CGFloat
    var degrees: Double

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: center)
        // SwiftUI'de y aşağı doğru; saat yönünün tersi için negatif açı
        p.addArc(center: center, radius: radius,
                 startAngle: .degrees(0), endAngle: .degrees(-degrees), clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Geçmiş grafiği

private struct HistoryChart: View {
    let samples: [SensorMonitor.Sample]
    let window: TimeInterval
    let color: Color
    let includesZero: Bool
    var threshold: Double? = nil
    let label: (Double) -> String

    var body: some View {
        let end = samples.last?.time ?? Date()
        Chart {
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Zaman", sample.time),
                    y: .value("Değer", sample.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
            }
            if let threshold {
                RuleMark(y: .value("Eşik", threshold))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("alarm eşiği").font(.caption2).foregroundStyle(.red)
                    }
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-window)...end)
        .chartYScale(domain: .automatic(includesZero: includesZero))
        .chartXAxis {
            AxisMarks(values: .stride(by: .second, count: 10)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text("-\(Int(end.timeIntervalSince(date).rounded())) sn")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(label(v)) }
                }
            }
        }
        .overlay {
            if samples.isEmpty {
                Text("Veri bekleniyor…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Ortak parçalar

private struct Card<Content: View>: View {
    let title: String
    let rate: Double
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f Hz", rate))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }
    }
}

private func degrees(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.0f°", value)
}

private struct LiveBadge: View {
    let isLive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(isLive ? "Canlı" : "Okuma yok")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MissingCard: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Bu Mac'te sensör bulunamadı ya da erişim reddedildi. Uygulamayı root olarak çalıştırmayı dene:")
                .foregroundStyle(.secondary)
            Text("sudo .build/debug/HingeGuard")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

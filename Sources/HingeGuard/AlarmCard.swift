import SwiftUI

/// Panelin en üstündeki alarm kartı: durum, geri sayım ve kur / devre dışı bırak düğmeleri.
/// Menü çubuğu simgesi görünmese bile alarm buradan yönetilebilir.
struct AlarmCard: View {
    @ObservedObject var controller: AlarmController
    let onArm: () -> Void
    let onCancel: () -> Void
    let onDisarm: () -> Void

    var body: some View {
        // Geri sayımlar için saniyede birkaç kez yeniden çiz
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let info = StateInfo(state: controller.state, now: context.date, controller: controller)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: info.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(info.color, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(info.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                    actionButton
                }

                if controller.state == .armed {
                    HStack(spacing: 8) {
                        DetectorChip(label: "Menteşe", active: controller.watchingAngle)
                        DetectorChip(label: "Hareket/eğim", active: controller.watchingMotion)
                        DetectorChip(label: "Güç kablosu", active: controller.watchingPower)
                    }
                }

                if controller.state == .disarmed, let error = controller.armError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(info.color.opacity(info.isAlert ? 0.18 : 0.08),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(info.color.opacity(info.isAlert ? 0.6 : 0.25), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch controller.state {
        case .disarmed:
            Button(action: onArm) {
                Label("Alarmı kur", systemImage: "lock.fill")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .arming:
            Button("İptal", action: onCancel)
                .controlSize(.large)
        case .armed, .grace, .alarming:
            Button(action: onDisarm) {
                Label("Devre dışı bırak", systemImage: "touchid")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.state == .armed ? .accentColor : .red)
            .controlSize(.large)
        }
    }
}

private struct StateInfo {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let isAlert: Bool

    init(state: AlarmState, now: Date, controller: AlarmController) {
        func remaining(_ until: Date) -> Int { max(0, Int(until.timeIntervalSince(now).rounded(.up))) }

        switch state {
        case .disarmed:
            title = "Alarm kapalı"
            subtitle = "Kurduktan sonra \(Int(controller.armingDelay)) sn içinde uzaklaş."
            symbol = "lock.open.fill"
            color = .gray
            isAlert = false
        case .arming(let until):
            title = "Kuruluyor · \(remaining(until)) sn"
            subtitle = "Bilgisayara dokunmadan uzaklaşabilirsin."
            symbol = "hourglass"
            color = .blue
            isAlert = false
        case .armed:
            title = "Alarm aktif"
            subtitle = "Kapak, hareket ya da kablo değişirse alarm çalar."
            symbol = "lock.fill"
            color = .green
            isAlert = false
        case .grace(let until):
            title = "Şüpheli hareket · \(remaining(until)) sn"
            subtitle = "\(controller.lastReason). Siren çalmadan önce devre dışı bırak."
            symbol = "exclamationmark.triangle.fill"
            color = .orange
            isAlert = true
        case .alarming:
            title = "ALARM ÇALIYOR"
            subtitle = controller.lastReason
            symbol = "bell.and.waves.left.and.right.fill"
            color = .red
            isAlert = true
        }
    }
}

private struct DetectorChip: View {
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: active ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(active ? .green : .secondary)
            Text(label)
                .foregroundStyle(active ? .primary : .secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

import Foundation
import IOKit.ps

/// Güç kablosunun çekilmesini izler.
final class PowerMonitor {
    var onUnplug: (() -> Void)?
    private var source: CFRunLoopSource?
    private var wasOnAC = PowerMonitor.isOnAC()

    static func isOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else {
            return false
        }
        return type == "AC Power"
    }

    func start() {
        guard source == nil else { return }
        wasOnAC = PowerMonitor.isOnAC()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let runLoopSource = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue().check()
        }, context).takeRetainedValue()
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        source = nil
    }

    /// Alarm kurulduğu anda kablo takılı muydu?
    var startedOnAC: Bool { wasOnAC }

    private func check() {
        let nowOnAC = PowerMonitor.isOnAC()
        if wasOnAC && !nowOnAC {
            onUnplug?()
        }
        wasOnAC = nowOnAC
    }
}

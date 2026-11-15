import Foundation
import IOKit
import IOKit.hid

/// Apple Silicon MacBook'lardaki dahili menteşe (lid angle) sensörünü okur.
/// Resmi bir API değildir; IOKit HID üzerinden (usage page 0x20, usage 0x8A) okunur.
/// macOS güncellemeleriyle değişebilir. Okuyamazsa `angle()` nil döner.
final class LidAngleSensor {
    struct Reading {
        let angle: Double?
        let rawBytes: [UInt8]   // Bayt düzenini doğrulamak için ham rapor
    }

    private let manager: IOHIDManager
    private var device: IOHIDDevice?

    init?() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey as String: 0x20,
            kIOHIDPrimaryUsageKey as String: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let first = devices.first else {
            return nil
        }
        guard IOHIDDeviceOpen(first, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        device = first
    }

    /// Menteşe açısı (derece). Okunamazsa nil.
    func angle() -> Double? {
        read().angle
    }

    /// Açıyı ve ham rapor baytlarını birlikte döner.
    func read() -> Reading {
        guard let device else { return Reading(angle: nil, rawBytes: []) }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess else { return Reading(angle: nil, rawBytes: []) }
        let bytes = Array(report.prefix(max(0, min(length, report.count))))
        guard bytes.count >= 3 else { return Reading(angle: nil, rawBytes: bytes) }
        // Rapor: [reportID, düşük bayt, yüksek bayt] -> derece
        let raw = (UInt16(bytes[2]) << 8) | UInt16(bytes[1])
        return Reading(angle: Double(raw), rawBytes: bytes)
    }
}

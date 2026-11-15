import Foundation
import IOKit
import IOKit.hid

/// Apple Silicon MacBook'lardaki SPU ivmeölçerini okur (resmi olmayan yol).
/// Cihaz: AppleSPUHIDDevice "accel", usage page 0xFF00, usage 3.
/// ~800 Hz, 22 baytlık rapor; x/y/z 6, 10, 14. baytlarda int32 LE, /65536 = g.
/// M4 Pro (Mac16,8) üzerinde doğrulandı.
final class Accelerometer {
    struct Snapshot {
        var x = 0.0, y = 0.0, z = 0.0      // ham ivme (g)
        var pitch = 0.0, roll = 0.0        // yerçekimine göre eğim (derece)
        var gravityX = 0.0, gravityY = 0.0, gravityZ = -1.0   // filtrelenmiş yerçekimi vektörü (g)
        var motion = 0.0                   // yerçekimi çıkarılmış ivme (g), bu okuyucunun son okumasından beri tepe değer
        var reportCount = 0
    }

    /// Her okuyucunun (panel, alarm) kendi tepe değeri olur; biri okuyunca diğerininki sıfırlanmaz.
    struct Consumer: Hashable {
        fileprivate let id: Int
    }

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    // Yerçekimi tahmini (alçak geçiren filtre). 800 Hz'de ~0.25 sn zaman sabiti.
    private let gravityAlpha = 0.005
    private var gravity: (x: Double, y: Double, z: Double)?
    private var latest = Snapshot()
    private var peaks: [Consumer: Double] = [:]
    private var nextConsumerID = 0

    init?() {
        Accelerometer.enableReporting()

        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey as String: 0xFF00,
            kIOHIDPrimaryUsageKey as String: 3,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let first = devices.first,
              IOHIDDeviceOpen(first, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            reportBuffer.deallocate()
            return nil
        }
        device = first

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, 64, { ctx, result, _, _, _, report, length in
            guard let ctx, result == kIOReturnSuccess else { return }
            Unmanaged<Accelerometer>.fromOpaque(ctx).takeUnretainedValue().handle(report, length)
        }, context)
        // .common: menü açıkken de okumaya devam etsin
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBuffer.deallocate()
    }

    func makeConsumer() -> Consumer {
        let consumer = Consumer(id: nextConsumerID)
        nextConsumerID += 1
        peaks[consumer] = 0
        return consumer
    }

    /// Son değerleri verir ve bu okuyucunun tepe hareket değerini sıfırlar.
    /// Böylece iki okuma arasında olan kısa bir sarsıntı kaçmaz.
    func takeSnapshot(for consumer: Consumer) -> Snapshot {
        var snapshot = latest
        snapshot.motion = peaks[consumer] ?? 0
        peaks[consumer] = 0
        return snapshot
    }

    // MARK: - Rapor işleme

    private func handle(_ report: UnsafeMutablePointer<UInt8>, _ length: Int) {
        guard length >= 18 else { return }
        func axis(_ offset: Int) -> Double {
            let raw = UInt32(report[offset])
                | UInt32(report[offset + 1]) << 8
                | UInt32(report[offset + 2]) << 16
                | UInt32(report[offset + 3]) << 24
            return Double(Int32(bitPattern: raw)) / 65536
        }
        let x = axis(6), y = axis(10), z = axis(14)

        var g = gravity ?? (x, y, z)
        g.x += (x - g.x) * gravityAlpha
        g.y += (y - g.y) * gravityAlpha
        g.z += (z - g.z) * gravityAlpha
        gravity = g

        let dx = x - g.x, dy = y - g.y, dz = z - g.z
        let motion = (dx * dx + dy * dy + dz * dz).squareRoot()
        for (consumer, peak) in peaks where motion > peak {
            peaks[consumer] = motion
        }

        latest.x = x
        latest.y = y
        latest.z = z
        latest.gravityX = g.x
        latest.gravityY = g.y
        latest.gravityZ = g.z
        latest.pitch = atan2(g.x, (g.y * g.y + g.z * g.z).squareRoot()) * 180 / .pi
        latest.roll = atan2(g.y, (g.x * g.x + g.z * g.z).squareRoot()) * 180 / .pi
        latest.reportCount &+= 1
    }

    // MARK: - Sürücüde raporlamayı aç

    /// SPU sürücüsü bazen sensörü kapalı tutar; güç ve raporlama özelliklerini açar.
    private static func enableReporting() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let page = IORegistryEntryCreateCFProperty(service, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            let usage = IORegistryEntryCreateCFProperty(service, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            guard page == 0xFF00, usage == 3 else { continue }
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 1000 as CFNumber)
        }
    }
}

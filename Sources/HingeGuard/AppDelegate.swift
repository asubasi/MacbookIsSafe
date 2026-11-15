import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // Alarm ve panel aynı sensör bağlantısını paylaşır
    private let sensor = LidAngleSensor()
    private let accelerometer = Accelerometer()
    private lazy var controller = AlarmController(sensor: sensor, accelerometer: accelerometer)
    private lazy var monitor = SensorMonitor(sensor: sensor, accelerometer: accelerometer)
    private var dashboardWindow: NSWindow?
    private var quitAuthorized = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.onStateChange = { [weak self] _ in self?.refreshMenu() }
        monitor.motionThreshold = controller.motionThreshold
        statusItem.isVisible = true
        statusItem.autosaveName = "HingeGuardStatusItem"
        buildMainMenu()
        refreshMenu()
        showDashboard()
    }

    /// Dock simgesine tıklanınca paneli geri aç.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showDashboard() }
        return true
    }

    /// ⌘Q, Dock'tan "Çık" ve menüdeki "Çık" hepsi buradan geçer:
    /// alarm açıkken kimlik doğrulamadan çıkılmaz.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if controller.state == .disarmed || quitAuthorized { return .terminateNow }
        Authenticator.authenticate(reason: "HingeGuard'dan çık") { [weak self] ok in
            guard ok, let self else { return }
            self.quitAuthorized = true
            NSApp.terminate(nil)
        }
        return .terminateCancel
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item("Paneli göster", #selector(showDashboard)))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "HingeGuard'dan çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // ⌘W ile pencereyi kapatabilmek için
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Pencere")
        windowMenu.addItem(NSMenuItem(title: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Panel penceresi

    @objc private func showDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "HingeGuard"
            let alarmCard = AlarmCard(
                controller: controller,
                onArm: { [weak self] in self?.arm() },
                onCancel: { [weak self] in self?.cancelArming() },
                onDisarm: { [weak self] in self?.disarm() }
            )
            let hosting = NSHostingController(rootView: DashboardView(monitor: monitor, alarm: alarmCard))
            // İçerik pencereyi büyütmesin (ScrollView yüzünden 1800 px'e şişiyordu)
            hosting.sizingOptions = []
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 540, height: 900))
            window.contentMinSize = NSSize(width: 480, height: 400)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            dashboardWindow = window
        }
        monitor.start()
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Panel kapalıyken 20 Hz okumaya gerek yok; alarm kendi zamanlayıcısıyla çalışır
        monitor.stop()
    }

    // MARK: - Menü

    private func refreshMenu() {
        let menu = NSMenu()
        let state = controller.state

        switch state {
        case .disarmed:
            statusItem.button?.title = "🔓"
            menu.addItem(withTitle: "Durum: Kapalı", action: nil, keyEquivalent: "")
            if !controller.sensorAvailable {
                menu.addItem(withTitle: "⚠️ Menteşe sensörü okunamadı", action: nil, keyEquivalent: "")
            }
            if let error = controller.armError {
                menu.addItem(withTitle: "⚠️ \(error)", action: nil, keyEquivalent: "")
            }
            menu.addItem(.separator())
            menu.addItem(item("Alarmı kur (\(Int(controller.armingDelay)) sn sonra aktif)", #selector(arm)))

        case .arming:
            statusItem.button?.title = "⏳"
            menu.addItem(withTitle: "Durum: Kuruluyor, uzaklaşabilirsin", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(item("İptal", #selector(cancelArming)))

        case .armed:
            statusItem.button?.title = "🔒"
            menu.addItem(withTitle: "Durum: Aktif", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Menteşe: \(controller.watchingAngle ? "izleniyor" : "YOK")", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Hareket/eğim: \(controller.watchingMotion ? "izleniyor" : "YOK")", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Güç kablosu: \(controller.watchingPower ? "izleniyor" : "takılı değildi")", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(item("Devre dışı bırak (Touch ID)", #selector(disarm)))

        case .grace:
            statusItem.button?.title = "⚠️"
            menu.addItem(withTitle: "Şüpheli hareket: \(controller.lastReason)", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(item("Devre dışı bırak (Touch ID)", #selector(disarm)))

        case .alarming:
            statusItem.button?.title = "🚨"
            menu.addItem(withTitle: "ALARM: \(controller.lastReason)", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(item("Devre dışı bırak (Touch ID)", #selector(disarm)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Paneli göster", #selector(showDashboard)))
        menu.addItem(NSMenuItem(title: "Çık", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    // MARK: - Eylemler

    @objc private func arm() { controller.arm() }

    @objc private func cancelArming() { controller.cancelArming() }

    @objc private func disarm() {
        Authenticator.authenticate(reason: "HingeGuard alarmını devre dışı bırak") { [weak self] ok in
            if ok { self?.controller.disarm() }
        }
    }

    @objc private func quit() {
        // Kimlik doğrulama applicationShouldTerminate içinde
        NSApp.terminate(nil)
    }
}

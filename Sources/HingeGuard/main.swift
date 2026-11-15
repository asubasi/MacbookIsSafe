import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // Dock'ta görünür; menü çubuğu simgesi gizlense de panele ulaşılır
app.run()

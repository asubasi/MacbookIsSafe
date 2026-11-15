// Uygulama simgesini üretir: koyu degrade zemin üzerinde kilitli dizüstü sembolü.
// Kullanım: swift scripts/make-icon.swift <çıktı.iconset klasörü>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "HingeGuard.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS simge ızgarası: kenarlarda ~%10 boşluk, yuvarlatılmış kare
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.24, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 1)])!
        .draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 1), .white]))
    if let symbol = NSImage(systemSymbolName: "lock.laptopcomputer", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let sz = symbol.size
        let scale = min(rect.width * 0.62 / sz.width, rect.height * 0.62 / sz.height)
        let w = sz.width * scale, h = sz.height * scale
        symbol.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Simge: \(outDir.path)")

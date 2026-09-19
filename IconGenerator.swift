import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
let rect = NSRect(origin: .zero, size: size)
let background = NSBezierPath(roundedRect: rect.insetBy(dx: 72, dy: 72), xRadius: 210, yRadius: 210)
// Match the blue-and-white mark used in the app interface.
NSColor(srgbRed: 52.0 / 255.0, green: 120.0 / 255.0, blue: 246.0 / 255.0, alpha: 1).setFill()
background.fill()

if let symbol = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 500, weight: .semibold)
    let configured = symbol.withSymbolConfiguration(config) ?? symbol
    let symbolSize = NSSize(width: 590, height: 590)
    let tinted = NSImage(size: symbolSize)

    tinted.lockFocus()
    configured.draw(in: NSRect(origin: .zero, size: symbolSize))
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let symbolRect = NSRect(
        x: (size.width - symbolSize.width) / 2,
        y: (size.height - symbolSize.height) / 2 + 10,
        width: symbolSize.width,
        height: symbolSize.height
    )
    tinted.draw(in: symbolRect)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render icon")
}
try png.write(to: URL(fileURLWithPath: outputPath))

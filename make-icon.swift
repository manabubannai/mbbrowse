// アイコン生成: swift make-icon.swift <出力dir>
import AppKit

let outDir = CommandLine.arguments[1]
let base = 1024
let image = NSImage(size: NSSize(width: base, height: base))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: base, height: base).fill()
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: CGFloat(base) - inset * 2, height: CGFloat(base) - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.15, alpha: 1),
    NSColor(calibratedRed: 0.92, green: 0.16, blue: 0.10, alpha: 1)])
grad?.draw(in: path, angle: -90)
let font = NSFont.systemFont(ofSize: 520)
let s = NSAttributedString(string: "🦁", attributes: [.font: font])
let ssize = s.size()
s.draw(at: NSPoint(x: (CGFloat(base) - ssize.width) / 2, y: (CGFloat(base) - ssize.height) / 2 - 10))
image.unlockFocus()

func png(_ px: Int) -> Data? {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

let iconset = outDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    if let d = png(px) { try? d.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png")) }
}
print("iconset written: \(iconset)")

// アイコン生成: swift make-icon.swift <出力dir> <背景hex> <文字hex> <文字>
// 例: swift make-icon.swift . "#26282B" "#FFFFFF" 窓
import AppKit

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."
func color(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
    return NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let bg = args.count > 2 ? color(args[2]) : color("#26282B")
let fg = args.count > 3 ? color(args[3]) : color("#FFFFFF")
let glyph = args.count > 4 ? args[4] : "窓"

let base = 1024
let image = NSImage(size: NSSize(width: base, height: base))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: base, height: base).fill()
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: CGFloat(base) - inset * 2, height: CGFloat(base) - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
bg.setFill()
path.fill()
let font = NSFont(name: "Hiragino Mincho ProN W6", size: 470) ?? NSFont.systemFont(ofSize: 470)
let s = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: fg])
let ssize = s.size()
s.draw(at: NSPoint(x: (CGFloat(base) - ssize.width) / 2, y: (CGFloat(base) - ssize.height) / 2 - 20))
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

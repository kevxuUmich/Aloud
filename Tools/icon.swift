// Builds App/Aloud.icns from App/Icon/Aloud-1024.png.
//
// The source is the mark's full-bleed 1024 export. A macOS icon draws its body on
// 824 of the 1024 points and leaves the rest as margin, so the art sits level with
// its neighbours in the Dock; this scales the export into that margin, writes the
// iconset at each size, and hands it to iconutil. Run through `make icon`.
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let source = root.appendingPathComponent("App/Icon/Aloud-1024.png")
let iconset = root.appendingPathComponent(".build/Aloud.iconset")
let output = root.appendingPathComponent("App/Aloud.icns")

let canvas = 1024
let body = 824

guard let data = try? Data(contentsOf: source),
    let cgSource = CGImageSourceCreateWithData(data as CFData, nil),
    let art = CGImageSourceCreateImageAtIndex(cgSource, 0, nil)
else {
    FileHandle.standardError.write(Data("icon: cannot read \(source.path)\n".utf8))
    exit(1)
}

func render(_ side: Int) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high
    let scale = CGFloat(side) / CGFloat(canvas)
    let drawn = CGFloat(body) * scale
    let inset = (CGFloat(side) - drawn) / 2
    ctx.draw(art, in: CGRect(x: inset, y: inset, width: drawn, height: drawn))
    return ctx.makeImage()
}

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = base * scale
        guard let image = render(side) else { exit(1) }
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let url = iconset.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { exit(1) }
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try! task.run()
task.waitUntilExit()
exit(task.terminationStatus)

import AppKit

// 使い方: image-stats <PNG>
// 画像のうち、色の付いた点（最大と最小の差が 0.25 以上）と暗い点（明るさ 0.3 未満）の割合、
// 暗い点・明るい点を囲む四角の大きさ（幅x高さ）、画素から作った目印（2枚の画像が同じかどうかを比べる）を出す
guard let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("画像を読めない\n".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
var colorful = 0, dark = 0, total = 0
// 暗い点と明るい点（明るさ 0.7 より上）を囲む四角
var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
var lightMinX = Int.max, lightMaxX = Int.min, lightMinY = Int.max, lightMaxY = Int.min, light = 0
var checksum: UInt64 = 14_695_981_039_346_656_037
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        if max(r, g, b) - min(r, g, b) >= 0.25 { colorful += 1 }
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        if luma < 0.3 {
            dark += 1
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } else if luma > 0.7 {
            light += 1
            lightMinX = min(lightMinX, x); lightMaxX = max(lightMaxX, x)
            lightMinY = min(lightMinY, y); lightMaxY = max(lightMaxY, y)
        }
        total += 1
        for v in [r, g, b] {
            checksum = (checksum ^ UInt64(v * 255)) &* 1_099_511_628_211
        }
    }
}
let box = dark > 0 ? "\(maxX - minX + 1)x\(maxY - minY + 1)" : "0x0"
let lightBox = light > 0 ? "\(lightMaxX - lightMinX + 1)x\(lightMaxY - lightMinY + 1)" : "0x0"
print(String(format: "colorful=%.4f dark=%.4f", Double(colorful) / Double(max(total, 1)),
             Double(dark) / Double(max(total, 1))) + " dark-box=\(box) light-box=\(lightBox) checksum=\(checksum)")

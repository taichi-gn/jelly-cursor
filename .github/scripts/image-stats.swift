import AppKit

// 使い方: image-stats <PNG>
// 画像のうち、色の付いた点（最大と最小の差が 0.25 以上）と暗い点（明るさ 0.3 未満）の割合と、
// 画素から作った目印（2枚の画像が同じかどうかを比べる）を出す
guard let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("画像を読めない\n".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
var colorful = 0, dark = 0, total = 0
var checksum: UInt64 = 14_695_981_039_346_656_037
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        if max(r, g, b) - min(r, g, b) >= 0.25 { colorful += 1 }
        if 0.299 * r + 0.587 * g + 0.114 * b < 0.3 { dark += 1 }
        total += 1
        for v in [r, g, b] {
            checksum = (checksum ^ UInt64(v * 255)) &* 1_099_511_628_211
        }
    }
}
print(String(format: "colorful=%.4f dark=%.4f", Double(colorful) / Double(max(total, 1)),
             Double(dark) / Double(max(total, 1))) + " checksum=\(checksum)")

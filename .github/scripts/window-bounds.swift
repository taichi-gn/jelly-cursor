import CoreGraphics
import Foundation

// 使い方: window-bounds <アプリ名>
// そのアプリのふつうの層の窓のうち、いちばん大きいものの範囲を screencapture -R の形（x,y,幅,高さ）で出す
let owner = CommandLine.arguments[1]
let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let rects = infos.compactMap { info -> CGRect? in
    guard info[kCGWindowOwnerName as String] as? String == owner,
          (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
          let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: bounds as CFDictionary)
}
guard let r = rects.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
    FileHandle.standardError.write(Data("\(owner) の窓が見つからない\n".utf8))
    exit(1)
}
print("\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))")

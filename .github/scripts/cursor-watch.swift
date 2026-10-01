import AppKit
import Foundation

// 使い方: cursor-watch <秒> [<x> <y>]
// 画面に出ているカーソルの形が変わるたびに、時刻・通し番号・形（矢印・I 字・指・その他）・見えているかを出し、
// 最後に形が変わった回数をまとめる。x と y を渡すと、はじめにマウスをそこへ置く（左上原点の画面座標）
_ = NSApplication.shared
let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
let seconds = args.first ?? 3
if args.count >= 3 { CGWarpMouseCursorPosition(CGPoint(x: args[1], y: args[2])) }
typealias Int32Getter = @convention(c) () -> Int32
let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
let seedOf = dlsym(rtldDefault, "CGSCurrentCursorSeed").map { unsafeBitCast($0, to: Int32Getter.self) }
let visibleOf = dlsym(rtldDefault, "CGCursorIsVisible").map { unsafeBitCast($0, to: Int32Getter.self) }

func kind(_ cursor: NSCursor?) -> String {
    guard let cursor else { return "なし" }
    for (name, known) in [("矢印", NSCursor.arrow), ("I字", NSCursor.iBeam), ("指", NSCursor.pointingHand)]
    where cursor.image.size == known.image.size && cursor.hotSpot == known.hotSpot {
        return name
    }
    return "その他(\(Int(cursor.image.size.width))x\(Int(cursor.image.size.height)))"
}

let start = Date()
var lastSeed: Int32?
var lastKind = ""
var lastVisible: Int32?
var kindChanges = 0, seedChanges = 0, visibleChanges = 0
while case let t = Date().timeIntervalSince(start), t < seconds {
    let seed = seedOf?() ?? 0
    let visible = visibleOf?() ?? -1
    if seed != lastSeed {
        let now = kind(NSCursor.currentSystem)
        if lastSeed != nil { seedChanges += 1 }
        if now != lastKind {
            if !lastKind.isEmpty { kindChanges += 1 }
            print(String(format: "%.3f 形=%@ 番号=%d 見える=%d", t, now, seed, visible))
            lastKind = now
        }
        lastSeed = seed
    }
    if visible != lastVisible {
        if lastVisible != nil { visibleChanges += 1 }
        lastVisible = visible
    }
    // 本物が一瞬だけ出るのも捉えられるよう、細かく見る
    usleep(200)
}
print("形の変化 \(kindChanges) 回、通し番号の変化 \(seedChanges) 回、見える・見えないの変化 \(visibleChanges) 回")

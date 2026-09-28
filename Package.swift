// swift-tools-version: 6.0
import PackageDescription

// JellyCursorCore: 動きの計算と設定・判断のロジック。AppKit を使わないので、macOS 以外でも試験を回せる
// JellyCursorKit: 窓・本物のカーソル・メニュー・設定画面など、macOS に触る部分
// JellyCursor: 起動だけ
var targets: [Target] = [
    .target(name: "JellyCursorCore"),
    .testTarget(
        name: "JellyCursorCoreTests",
        dependencies: ["JellyCursorCore"],
        resources: [.copy("Resources/golden-motion.json")]),
]

#if os(macOS)
targets += [
    .target(name: "JellyCursorKit", dependencies: ["JellyCursorCore"]),
    .executableTarget(name: "JellyCursor", dependencies: ["JellyCursorKit"]),
    // 本物のカーソルの画像や AppKit の値を使う試験。macOS でだけ回す
    .testTarget(name: "JellyCursorKitTests", dependencies: ["JellyCursorKit", "JellyCursorCore"]),
]
#endif

let package = Package(
    name: "JellyCursor",
    platforms: [.macOS(.v14)],
    targets: targets
)

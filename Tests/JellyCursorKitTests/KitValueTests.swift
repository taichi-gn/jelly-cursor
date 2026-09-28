import AppKit
import JellyCursorCore
import Testing
@testable import JellyCursorKit

@Suite struct KitValueTests {
    // CGWindowListCopyWindowInfo と同じ形の辞書から読む
    @Test func windowInfoFromDictionary() throws {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200).dictionaryRepresentation
        let info: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 42),
            kCGWindowOwnerPID as String: NSNumber(value: 1234),
            kCGWindowLayer as String: NSNumber(value: 24),
            kCGWindowAlpha as String: NSNumber(value: 0.5),
            kCGWindowBounds as String: bounds,
        ]
        let window = try #require(WindowInfo(info))
        #expect(window == WindowInfo(number: 42, ownerPID: 1234, layer: 24, alpha: 0.5,
                                     bounds: CGRect(x: 10, y: 20, width: 300, height: 200)))
        // 透明度が無ければ見えている扱い、窓番号や範囲が無ければ読まない
        var noAlpha = info
        noAlpha[kCGWindowAlpha as String] = nil
        #expect(WindowInfo(noAlpha)?.alpha == 1)
        var noBounds = info
        noBounds[kCGWindowBounds as String] = nil
        #expect(WindowInfo(noBounds) == nil)
    }

    @Test func modifierFlagsRoundTrip() {
        for raw in 0..<16 {
            let modifiers = KeyModifiers(rawValue: raw)
            #expect(KeyModifiers(NSEvent.ModifierFlags(modifiers)) == modifiers)
        }
        #expect(KeyModifiers(NSEvent.ModifierFlags([.command, .capsLock, .function])) == .command)
    }

    @Test func colorsKeepComponents() throws {
        let color = RGBA(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5).cgColor
        let srgb = try #require(color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil))
        let c = try #require(srgb.components)
        #expect(abs(c[0] - 0.25) < 0.001 && abs(c[1] - 0.5) < 0.001 && abs(c[2] - 0.75) < 0.001 && abs(c[3] - 0.5) < 0.001)
    }

    @Test func pointerScaleIsInRange() {
        #expect((1...4).contains(SystemPointer.scale()))
    }
}

// アイコンの書き出し
@MainActor
@Suite struct AppIconTests {
    @Test func writesEveryIconsetSize() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("JellyCursorTests-\(UUID().uuidString).iconset")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(AppIconImage.writeIconset(to: folder.path))
        let expected: [String: Int] = [
            "icon_16x16.png": 16, "icon_16x16@2x.png": 32, "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128, "icon_128x128@2x.png": 256, "icon_256x256.png": 256,
            "icon_256x256@2x.png": 512, "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
        ]
        for (name, pixels) in expected {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(bitmap.pixelsWide == pixels && bitmap.pixelsHigh == pixels, "\(name)")
        }
    }

    // 角は透明で、真ん中は塗られている（角の丸い四角の周りに余白がある）
    @Test func iconHasTransparentCorners() throws {
        let data = try #require(AppIconImage.png(AppIconImage.make(), pixels: 256))
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect((bitmap.colorAt(x: 2, y: 2)?.alphaComponent ?? 1) < 0.01)
        #expect((bitmap.colorAt(x: 128, y: 128)?.alphaComponent ?? 0) > 0.99)
    }
}

// 診断情報に入れる記録は、この起動のあいだに書いたものを読めること
@Suite struct RecentLogTests {
    @Test func readsWhatWasJustLogged() async throws {
        let message = "試験の記録 \(UUID().uuidString)"
        logger.notice("\(message, privacy: .public)")
        // 書いてから読めるようになるまで、少し待つことがある
        var found = false
        for _ in 0..<20 where !found {
            found = recentLogLines(limit: 200).contains { $0.hasSuffix(message) }
            if !found { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(found)
    }
}

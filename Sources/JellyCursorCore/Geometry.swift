import Foundation

#if !canImport(CoreGraphics)
// macOS 以外の Foundation には CGVector が無い。試験を macOS 以外でも回せるよう、同じ形のものを用意する
package struct CGVector: Equatable, Sendable {
    package var dx: CGFloat
    package var dy: CGFloat

    package static let zero = CGVector(dx: 0, dy: 0)

    package init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }
}
#endif

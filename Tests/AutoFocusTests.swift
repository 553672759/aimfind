import CoreGraphics
import Testing

@testable import AimFind

struct AutoFocusTests {

    private let center = CGPoint(x: 0.5, y: 0.4)

    /// 归一化坐标是算出来的，别做浮点相等比较
    private func near(_ point: CGPoint?, x: CGFloat, y: CGFloat, tolerance: CGFloat = 0.0001) -> Bool {
        guard let point else { return false }
        return abs(point.x - x) < tolerance && abs(point.y - y) < tolerance
    }

    @Test func focusesWhereTheCodeWasRead() {
        let box = CGRect(x: 0.4, y: 0.35, width: 0.2, height: 0.1)
        let target = AutoFocus.target(box: box, lastFocused: nil, now: 10, lastAt: 0)
        #expect(near(target, x: 0.5, y: 0.4))
    }

    @Test func staysQuietWithoutARead() {
        #expect(AutoFocus.target(box: nil, lastFocused: center, now: 10, lastAt: 0) == nil)
    }

    @Test func respectsTheCooldown() {
        let box = CGRect(x: 0.4, y: 0.35, width: 0.2, height: 0.1)
        // 冷却未过 → 不动作
        #expect(AutoFocus.target(box: box, lastFocused: nil, now: 10, lastAt: 9.6) == nil)
        // 冷却已过 → 合焦
        #expect(AutoFocus.target(box: box, lastFocused: nil, now: 10, lastAt: 9.0) != nil)
    }

    @Test func ignoresDriftSmallerThanTheThreshold() {
        let drifted = CGRect(x: 0.402, y: 0.352, width: 0.2, height: 0.1)   // 中心只动了 ~0.2%
        #expect(AutoFocus.target(box: drifted, lastFocused: center, now: 10, lastAt: 0) == nil)

        let jumped = CGRect(x: 0.62, y: 0.35, width: 0.2, height: 0.1)      // 跳到另一件
        #expect(near(AutoFocus.target(box: jumped, lastFocused: center, now: 10, lastAt: 0), x: 0.72, y: 0.4))
    }
}

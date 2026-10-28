// AimFind — 自动对焦的"何时重新对焦"判定（纯函数）。
//
// 不做自动变焦：数码变焦只绕画面中心，用户要的是**合焦到识别出的位置**，
// 等效于手指在那一点一下，所以走和点击完全相同的坐标路径。
//
// 时间由调用方传进来（不读时钟），这样这条规则可以离线单测。

import CoreGraphics
import Foundation

enum AutoFocus {
    /// 目标中心移动超过这个幅度才重新合焦（连续自动对焦本来会跟手，我们只在"跳到另一件"时介入）。
    static let jumpThreshold: CGFloat = 0.06
    /// 两次自动合焦的最小间隔（秒）：AF 反复重锁既耗电又会让画面抽动。
    static let interval: TimeInterval = 0.7

    /// 返回这次该合焦的**图像归一化中心**（左上原点）；nil = 别动。
    static func target(box: CGRect?,
                       lastFocused: CGPoint?,
                       now: TimeInterval,
                       lastAt: TimeInterval) -> CGPoint? {
        guard let box else { return nil }
        let center = CGPoint(x: box.midX, y: box.midY)
        guard now - lastAt >= interval else { return nil }
        guard let previous = lastFocused else { return center }
        let dx = abs(center.x - previous.x)
        let dy = abs(center.y - previous.y)
        return max(dx, dy) > jumpThreshold ? center : nil
    }
}

// AimFind — 命中的东西在画面的哪个方位（纯函数，供提示文案用）。
// 九宫格按**框中心**划分；远近按框高度（同一件包裹越近字越大）。

import CoreGraphics

enum ScreenRegion: String {
    case upperLeft, upperCenter, upperRight
    case middleLeft, middleCenter, middleRight
    case lowerLeft, lowerCenter, lowerRight

    init(center: CGPoint) {
        let column: Int
        switch center.x {
        case ..<0.334: column = 0
        case ..<0.667: column = 1
        default: column = 2
        }
        let row: Int
        switch center.y {
        case ..<0.334: row = 0
        case ..<0.667: row = 1
        default: row = 2
        }
        self = ScreenRegion.grid[row][column]
    }

    private static let grid: [[ScreenRegion]] = [
        [.upperLeft, .upperCenter, .upperRight],
        [.middleLeft, .middleCenter, .middleRight],
        [.lowerLeft, .lowerCenter, .lowerRight],
    ]
}

enum Approach: Equatable {
    case far        // 还要走近
    case middle
    case close      // 已经很近，基本就在眼前
}

extension LocatedCode {
    var region: ScreenRegion { ScreenRegion(center: CGPoint(x: box.midX, y: box.midY)) }

    /// 码文本身占画面高度的比例 → 远近。经验值：货架上那 4 位大字在 0.5m 左右约占 6% 高度。
    var approach: Approach {
        switch box.height {
        case ..<0.03: return .far
        case ..<0.07: return .middle
        default: return .close
        }
    }
}

// AimFind — 结果框层：把匹配到的码按 aspect-fill 映射到取景上。
// 已找到的标签 = 绿色实线 + 淡填充；没找到的精确命中 = 绿色描边；需修正的 = 黄色虚线带 ≈。

import SwiftUI

struct DetectionOverlay: View {
    let codes: [LocatedCode]
    let imageAspect: CGFloat
    let found: Set<String>

    var body: some View {
        Canvas { context, size in
            let mapper = ViewportMapper(imageAspect: imageAspect)
            for code in codes {
                let rect = mapper.rect(code.box, in: size)
                guard rect.width > 2, rect.height > 2 else { continue }
                let isFound = found.contains(code.target.id)
                let color: Color = code.strength == .probable ? .yellow : .green
                let style = StrokeStyle(lineWidth: isFound ? 4 : 2,
                                        dash: code.strength == .exact ? [] : [7, 5])
                if isFound {
                    context.fill(Path(rect), with: .color(color.opacity(0.14)))
                }
                context.stroke(Path(rect), with: .color(color), style: style)
                context.draw(
                    Text(label(for: code, found: isFound))
                        .font(isFound ? .title3.bold() : .caption.bold())
                        .foregroundColor(color),
                    at: CGPoint(x: rect.midX, y: max(rect.minY - 12, 16)),
                    anchor: .center
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func label(for code: LocatedCode, found: Bool) -> String {
        if found { return code.display }
        return code.strength == .probable ? "≈\(code.display)" : "\(code.display) · \(Int((code.confidence * 100).rounded()))%"
    }
}

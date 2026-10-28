// AimFind — 文本读取引擎接口：只负责"这行写了什么"，语义判断都在 CodeGrammar / TargetMatcher。

import CoreGraphics
import CoreVideo
import ImageIO

/// 一行 OCR 结果。box 是**旋正后图像的归一化坐标，左上原点**（与 YOLO 结果同一套约定）。
struct TextHit: Equatable {
    let raw: String
    let confidence: Double
    let box: CGRect
}

protocol TextReader {
    var name: String { get }
    func read(_ pixelBuffer: CVPixelBuffer,
              orientation: CGImagePropertyOrientation) async throws -> [TextHit]
}

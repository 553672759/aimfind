// AimFind — 检测结果的最小数据模型：一个框 + 一个类别。
// box 是**方向修正后的图像归一化坐标**（0...1，左上原点），overlay 只负责乘上视图尺寸。

import CoreGraphics
import Foundation

struct Detection: Identifiable, Equatable {
    let classIndex: Int
    let label: String
    let confidence: Double
    let box: CGRect

    var id: Int { classIndex }

    init(classIndex: Int, label: String, confidence: Double, box: CGRect) {
        self.classIndex = classIndex
        self.label = label
        self.confidence = confidence
        self.box = box
    }
}

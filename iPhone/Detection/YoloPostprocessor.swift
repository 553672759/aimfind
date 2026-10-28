// AimFind — YOLO 输出张量 → Detection 的后处理层。
// 职责：识别输出布局 → 解码框/分数 → 置信度阈值 → 同类 NMS → letterbox 反映射到原图归一化坐标。
// 纯函数，不依赖 Vision / CoreML，因此三种常见导出都能在这里单测。

import CoreGraphics
import Foundation

enum YoloPostprocessor {

    struct Request {
        /// 去掉 batch 维、行优先展平的输出张量
        let values: [Float]
        /// 去掉 batch 维后的形状，例如 [84, 8400]、[25200, 85]、[300, 6]
        let dims: [Int]
        let labels: [String]
        /// 模型输入边长（letterbox 后是正方形），框坐标默认落在这个像素空间里
        let inputSide: CGFloat
        /// 方向修正后的图像尺寸，框最终归一化到它
        let imageSize: CGSize
        var confidenceThreshold: Float = 0.25
        var iouThreshold: Float = 0.45
        var maxDetections: Int = 40
    }

    enum Failure: Error, Equatable {
        case shapeNotUnderstood([Int])
        case notEnoughValues(count: Int, expected: Int)
    }

    enum Layout: Equatable {
        /// [attrs, anchors]：YOLOv8 / v11 默认导出，例如 84 × 8400
        case anchorsFirst(attrs: Int, anchors: Int)
        /// [rows, attrs]：YOLOv5 风格或转置导出，例如 25200 × 85
        case anchorsLast(rows: Int, attrs: Int)
        /// [rows, 6] = x1,y1,x2,y2,score,class：导出时已带 NMS 的端到端模型
        case endToEnd(rows: Int)
    }

    struct Candidate: Equatable {
        var box: CGRect
        var score: Float
        var classIndex: Int
    }

    // MARK: - 入口

    static func detect(_ request: Request) throws -> [Detection] {
        guard let layout = layout(for: request.dims) else {
            throw Failure.shapeNotUnderstood(request.dims)
        }
        let expected = request.dims.reduce(1, *)
        guard request.values.count >= expected else {
            throw Failure.notEnoughValues(count: request.values.count, expected: expected)
        }

        let raw = candidates(for: layout, request: request)
        let kept = nonMaxSuppression(raw, iouThreshold: request.iouThreshold, limit: request.maxDetections)
        let letterbox = Letterbox.fitting(imageSize: request.imageSize, inputSide: request.inputSide)

        return kept.map {
            Detection(classIndex: $0.classIndex,
                      label: label(for: $0.classIndex, labels: request.labels),
                      confidence: Double($0.score),
                      box: letterbox.normalizedRect(inModelSpace: $0.box))
        }
    }

    // MARK: - 布局判定

    static func layout(for dims: [Int]) -> Layout? {
        guard dims.count == 2, dims[0] > 0, dims[1] > 0 else { return nil }
        let (outer, inner) = (dims[0], dims[1])
        if inner == 6, outer > 6 { return .endToEnd(rows: outer) }
        if inner > outer { return .anchorsFirst(attrs: outer, anchors: inner) }
        if outer > inner { return .anchorsLast(rows: outer, attrs: inner) }
        return nil
    }

    /// attrs 是 4+C（无 objectness，v8 风格）还是 5+C（有 objectness，v5 风格）。
    /// 优先用类名表对齐；表缺失或对齐不上时按 4+C 解。
    static func classPlan(attrs: Int, labelCount: Int) -> (classes: Int, hasObjectness: Bool) {
        if labelCount > 0 {
            if attrs - 5 == labelCount { return (labelCount, true) }
            if attrs - 4 == labelCount { return (labelCount, false) }
        }
        return (max(attrs - 4, 0), false)
    }

    // MARK: - 解码

    static func candidates(for layout: Layout, request: Request) -> [Candidate] {
        let values = request.values
        let threshold = request.confidenceThreshold

        switch layout {
        case let .endToEnd(rows):
            var out: [Candidate] = []
            out.reserveCapacity(rows)
            for row in 0..<rows {
                let score = values[row * 6 + 4]
                guard score >= threshold else { continue }
                let classValue = values[row * 6 + 5]
                guard classValue >= 0, classValue.isFinite else { continue }
                let left = CGFloat(values[row * 6]), top = CGFloat(values[row * 6 + 1])
                let right = CGFloat(values[row * 6 + 2]), bottom = CGFloat(values[row * 6 + 3])
                out.append(Candidate(box: CGRect(x: left, y: top,
                                                 width: max(right - left, 0), height: max(bottom - top, 0)),
                                     score: score,
                                     classIndex: Int(classValue)))
            }
            return out

        case let .anchorsFirst(attrs, anchors):
            let plan = classPlan(attrs: attrs, labelCount: request.labels.count)
            guard plan.classes > 0 else { return [] }
            let scoreBase = plan.hasObjectness ? 5 : 4
            var out: [Candidate] = []
            for anchor in 0..<anchors {
                let cx = values[anchor], cy = values[anchors + anchor]
                let width = values[2 * anchors + anchor], height = values[3 * anchors + anchor]
                let objectness: Float = plan.hasObjectness ? values[4 * anchors + anchor] : 1
                var best = Candidate(box: .zero, score: 0, classIndex: -1)
                for cls in 0..<plan.classes {
                    let score = objectness * values[(scoreBase + cls) * anchors + anchor]
                    if score > best.score { best = Candidate(box: .zero, score: score, classIndex: cls) }
                }
                guard best.score >= threshold else { continue }
                best.box = CGRect(x: CGFloat(cx - width / 2), y: CGFloat(cy - height / 2),
                                  width: CGFloat(width), height: CGFloat(height))
                out.append(best)
            }
            return out

        case let .anchorsLast(rows, attrs):
            let plan = classPlan(attrs: attrs, labelCount: request.labels.count)
            guard plan.classes > 0 else { return [] }
            let scoreBase = plan.hasObjectness ? 5 : 4
            var out: [Candidate] = []
            for row in 0..<rows {
                let cx = values[row * attrs]
                let cy = values[row * attrs + 1], width = values[row * attrs + 2], height = values[row * attrs + 3]
                let objectness: Float = plan.hasObjectness ? values[row * attrs + 4] : 1
                var best = Candidate(box: .zero, score: 0, classIndex: -1)
                for cls in 0..<plan.classes {
                    let score = objectness * values[row * attrs + scoreBase + cls]
                    if score > best.score { best = Candidate(box: .zero, score: score, classIndex: cls) }
                }
                guard best.score >= threshold else { continue }
                best.box = CGRect(x: CGFloat(cx - width / 2), y: CGFloat(cy - height / 2),
                                  width: CGFloat(width), height: CGFloat(height))
                out.append(best)
            }
            return out
        }
    }

    // MARK: - NMS

    static func nonMaxSuppression(_ candidates: [Candidate], iouThreshold: Float, limit: Int) -> [Candidate] {
        let sorted = candidates.sorted { $0.score > $1.score }
        var kept: [Candidate] = []
        for candidate in sorted {
            let suppressed = kept.contains {
                $0.classIndex == candidate.classIndex && iou($0.box, candidate.box) > CGFloat(iouThreshold)
            }
            if !suppressed {
                kept.append(candidate)
                if kept.count >= limit { break }
            }
        }
        return kept
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let overlap = intersection.width * intersection.height
        guard overlap > 0 else { return 0 }
        let union = a.width * a.height + b.width * b.height - overlap
        guard union > 0 else { return 0 }
        return overlap / union
    }

    static func label(for classIndex: Int, labels: [String]) -> String {
        labels.indices.contains(classIndex) ? labels[classIndex] : "class_\(classIndex)"
    }

    // MARK: - letterbox 反映射

    /// Vision 的 `.scaleFit` 与 ultralytics 的 letterbox 等价：等比缩放 + 居中补边。
    struct Letterbox: Equatable {
        let scale: CGFloat
        let padX: CGFloat
        let padY: CGFloat
        let imageSize: CGSize

        static func fitting(imageSize: CGSize, inputSide: CGFloat) -> Letterbox {
            guard imageSize.width > 0, imageSize.height > 0, inputSide > 0 else {
                return Letterbox(scale: 1, padX: 0, padY: 0, imageSize: CGSize(width: 1, height: 1))
            }
            let scale = min(inputSide / imageSize.width, inputSide / imageSize.height)
            return Letterbox(scale: scale,
                             padX: (inputSide - imageSize.width * scale) / 2,
                             padY: (inputSide - imageSize.height * scale) / 2,
                             imageSize: imageSize)
        }

        /// 模型空间（inputSide × inputSide 像素）→ 原图归一化（0...1，左上原点），并裁进画面内
        func normalizedRect(inModelSpace rect: CGRect) -> CGRect {
            guard scale > 0, imageSize.width > 0, imageSize.height > 0 else { return .zero }
            let left = (rect.minX - padX) / scale / imageSize.width
            let right = (rect.maxX - padX) / scale / imageSize.width
            let top = (rect.minY - padY) / scale / imageSize.height
            let bottom = (rect.maxY - padY) / scale / imageSize.height
            let clampedLeft = min(max(left, 0), 1)
            let clampedRight = min(max(right, 0), 1)
            let clampedTop = min(max(top, 0), 1)
            let clampedBottom = min(max(bottom, 0), 1)
            return CGRect(x: clampedLeft, y: clampedTop,
                          width: max(clampedRight - clampedLeft, 0),
                          height: max(clampedBottom - clampedTop, 0))
        }
    }
}

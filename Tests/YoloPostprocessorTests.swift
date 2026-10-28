import CoreGraphics
import Testing

@testable import AimFind

/// 后处理层是纯函数，所以三种 YOLO 导出布局都能在单测里喂假张量验证。
struct YoloPostprocessorTests {

    private static let labels = COCOClassLabels.coco80

    // MARK: - 布局判定

    @Test func detectsLayouts() {
        #expect(YoloPostprocessor.layout(for: [84, 8400]) == .anchorsFirst(attrs: 84, anchors: 8400))
        #expect(YoloPostprocessor.layout(for: [25200, 85]) == .anchorsLast(rows: 25200, attrs: 85))
        #expect(YoloPostprocessor.layout(for: [300, 6]) == .endToEnd(rows: 300))
        #expect(YoloPostprocessor.layout(for: [7, 7]) == nil)
        #expect(YoloPostprocessor.layout(for: [8400]) == nil)
    }

    @Test func classPlanUsesLabelTableToSpotObjectness() {
        #expect(YoloPostprocessor.classPlan(attrs: 84, labelCount: 80) == (classes: 80, hasObjectness: false))
        #expect(YoloPostprocessor.classPlan(attrs: 85, labelCount: 80) == (classes: 80, hasObjectness: true))
        // 类名表缺失时按 4+C 解（v8 风格）
        #expect(YoloPostprocessor.classPlan(attrs: 85, labelCount: 0) == (classes: 81, hasObjectness: false))
    }

    // MARK: - YOLOv8 默认导出：[84, 8400]，无 objectness

    @Test func decodesAnchorsFirstTensor() throws {
        let attrs = 84, anchors = 8400
        var values = [Float](repeating: 0, count: attrs * anchors)
        let anchor = 1234
        func write(_ row: Int, _ value: Float) { values[row * anchors + anchor] = value }

        write(0, 320)  // cx
        write(1, 160)  // cy
        write(2, 64)   // w
        write(3, 64)   // h
        write(4, 0.9)  // class 0 = person

        let detections = try YoloPostprocessor.detect(request(values: values, dims: [attrs, anchors],
                                                              imageSize: CGSize(width: 640, height: 640)))
        #expect(detections.count == 1)
        let box = try #require(detections.first)
        #expect(box.label == "person")
        #expect(box.classIndex == 0)
        #expect(box.confidence > 0.89 && box.confidence < 0.91)
        // 方图输入、无补边：模型像素 / 640 即归一化坐标
        #expect(approx(box.box, CGRect(x: 0.45, y: 0.2, width: 0.1, height: 0.1)))
    }

    // MARK: - YOLOv5 风格：[25200, 85]，第 5 列是 objectness

    @Test func decodesAnchorsLastTensorWithObjectness() throws {
        let rows = 25_200, attrs = 85
        var values = [Float](repeating: 0, count: rows * attrs)
        let row = 7
        values[row * attrs + 0] = 100   // cx
        values[row * attrs + 1] = 200   // cy
        values[row * attrs + 2] = 40    // w
        values[row * attrs + 3] = 80    // h
        values[row * attrs + 4] = 0.8   // objectness
        values[row * attrs + 5 + 2] = 0.5   // class 2 = car

        let detections = try YoloPostprocessor.detect(request(values: values, dims: [rows, attrs],
                                                              imageSize: CGSize(width: 640, height: 640)))
        #expect(detections.count == 1)
        let car = try #require(detections.first)
        #expect(car.label == "car")
        #expect(car.classIndex == 2)
        #expect(approx(car.confidence, 0.4, tolerance: 0.001))   // 0.8 × 0.5
        #expect(approx(car.box, CGRect(x: 0.125, y: 0.25, width: 0.0625, height: 0.125)))  // (80,160,40,80)/640
    }

    // MARK: - 端到端导出（已在模型里做 NMS）：[300, 6] = x1,y1,x2,y2,score,class

    @Test func decodesEndToEndTensor() throws {
        let rows = 300
        var values = [Float](repeating: 0, count: rows * 6)
        func plant(_ row: Int, _ box: CGRect, score: Float, cls: Int) {
            values[row * 6] = Float(box.minX)
            values[row * 6 + 1] = Float(box.minY)
            values[row * 6 + 2] = Float(box.maxX)
            values[row * 6 + 3] = Float(box.maxY)
            values[row * 6 + 4] = score
            values[row * 6 + 5] = Float(cls)
        }
        plant(0, CGRect(x: 0, y: 0, width: 320, height: 640), score: 0.7, cls: 24)     // backpack
        plant(1, CGRect(x: 0, y: 0, width: 100, height: 100), score: 0.1, cls: 0)      // 低于阈值

        let detections = try YoloPostprocessor.detect(request(values: values, dims: [rows, 6],
                                                              imageSize: CGSize(width: 640, height: 640)))
        #expect(detections.count == 1)
        let found = try #require(detections.first)
        #expect(found.label == "backpack")
        #expect(approx(found.box, CGRect(x: 0, y: 0, width: 0.5, height: 1)))
    }

    // MARK: - 阈值 / NMS / 上限

    @Test func sameClassOverlapIsSuppressedButDistantBoxesSurvive() throws {
        let overlapping = YoloPostprocessor.nonMaxSuppression(
            [Candidate(box: CGRect(x: 0, y: 0, width: 10, height: 10), score: 0.9, classIndex: 0),
             Candidate(box: CGRect(x: 1, y: 1, width: 10, height: 10), score: 0.8, classIndex: 0),
             Candidate(box: CGRect(x: 50, y: 50, width: 10, height: 10), score: 0.7, classIndex: 0),
             Candidate(box: CGRect(x: 0, y: 0, width: 10, height: 10), score: 0.6, classIndex: 1)],
            iouThreshold: 0.45,
            limit: 40
        )
        #expect(overlapping.count == 3)
        #expect(overlapping.first?.score == 0.9)

        // 不同类别即使完全重叠也互不压制
        #expect(overlapping.contains { $0.classIndex == 1 })
    }

    @Test func maxDetectionsCapsKeptCandidates() {
        let many = (0..<20).map {
            YoloPostprocessor.Candidate(box: CGRect(x: CGFloat($0 * 100), y: 0, width: 20, height: 20),
                                        score: Float(20 - $0),
                                        classIndex: $0 % 80)
        }
        #expect(YoloPostprocessor.nonMaxSuppression(many, iouThreshold: 0.45, limit: 3).count == 3)
    }

    @Test func iouIsZeroForDisjointAndOneForIdentical() {
        let box = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(YoloPostprocessor.iou(box, box) == 1)
        #expect(YoloPostprocessor.iou(box, CGRect(x: 20, y: 0, width: 10, height: 10)) == 0)
        #expect(approx(YoloPostprocessor.iou(box, CGRect(x: 5, y: 0, width: 10, height: 10)), 1 / 3, tolerance: 0.001))
    }

    // MARK: - letterbox 反映射

    @Test func mapsModelSpaceThroughLetterboxPadding() throws {
        // 1080×1920 竖屏喂进 640 输入：scale = 1/3，左右各补 140
        let letterbox = YoloPostprocessor.Letterbox.fitting(imageSize: CGSize(width: 1080, height: 1920),
                                                           inputSide: 640)
        #expect(approx(letterbox.scale, 1 / 3, tolerance: 0.0001))
        #expect(approx(letterbox.padX, 140, tolerance: 0.0001))
        #expect(approx(letterbox.padY, 0, tolerance: 0.0001))
        // 整幅画面 → 归一化 (0,0,1,1)
        #expect(approx(letterbox.normalizedRect(inModelSpace: CGRect(x: 140, y: 0, width: 360, height: 640)),
                       CGRect(x: 0, y: 0, width: 1, height: 1)))
        // 越界的框被裁进画面
        let clipped = letterbox.normalizedRect(inModelSpace: CGRect(x: 0, y: 0, width: 200, height: 700))
        #expect(clipped.minX == 0 && clipped.maxY == 1)
    }

    @Test func rejectsTooShortTensor() {
        #expect(throws: YoloPostprocessor.Failure.notEnoughValues(count: 3, expected: 12)) {
            try YoloPostprocessor.detect(request(values: [0, 0, 0], dims: [3, 4],
                                                 imageSize: CGSize(width: 640, height: 640)))
        }
    }

    // MARK: - 造请求

    private func request(values: [Float], dims: [Int], imageSize: CGSize) -> YoloPostprocessor.Request {
        YoloPostprocessor.Request(values: values,
                                  dims: dims,
                                  labels: Self.labels,
                                  inputSide: 640,
                                  imageSize: imageSize)
    }

    private func approx(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.0001) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    private func approx(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.0001) -> Bool {
        abs(a - b) < tolerance
    }

    private func approx(_ a: Double, _ b: Double, tolerance: Double = 0.0001) -> Bool {
        abs(a - b) < tolerance
    }
}

private typealias Candidate = YoloPostprocessor.Candidate

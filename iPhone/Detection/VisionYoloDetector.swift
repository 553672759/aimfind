// AimFind — 检测引擎接口 + Vision/Core ML 上的 YOLO 实现。
// 换引擎只需实现 `Detector`；本文件不含解码数学（都在 YoloPostprocessor，方便单测）。

import AVFoundation
import CoreGraphics
import CoreML
import Foundation
import Vision

protocol Detector {
    var name: String { get }
    func detect(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async throws -> [Detection]
}

struct VisionYoloDetector: Detector {

    struct Configuration {
        var modelName: String = DetectionConfig.modelResourceName
        var confidenceThreshold: Float = DetectionConfig.confidenceThreshold
        var iouThreshold: Float = DetectionConfig.iouThreshold
        var maxDetections: Int = DetectionConfig.maxDetections
    }

    enum LoadFailure: Error, Equatable {
        case modelNotFound(String)
        case modelLoadFailed(String)
        case noImageInput(String)
        case unsupportedOutputDataType(String)
        case unexpectedOutputShape([Int])
    }

    let name: String
    let labels: [String]
    let inputSide: CGFloat

    private let configuration: Configuration
    private let coreMLModel: VNCoreMLModel

    /// Vision 的 `perform` 是同步阻塞调用：给它一条自己的串行队列，
    /// 既保证同一时刻只有一次推理，也不占用 Swift 并发线程池。
    private static let inferenceQueue = DispatchQueue(label: "com.aimfind.detection.vision", qos: .userInitiated)

    init(configuration: Configuration = Configuration()) throws {
        let (model, sourceURL) = try Self.loadModel(named: configuration.modelName)
        guard let side = Self.inputSide(of: model) else {
            throw LoadFailure.noImageInput(configuration.modelName)
        }
        self.configuration = configuration
        self.inputSide = side
        self.labels = (model.modelDescription.classLabels as? [String]) ?? COCOClassLabels.coco80
        self.name = "\(sourceURL.lastPathComponent) · YOLO"
        self.coreMLModel = try VNCoreMLModel(for: model)
    }

    // MARK: - 推理

    func detect(_ pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation) async throws -> [Detection] {
        var observations: [VNObservation] = []
        let request = VNCoreMLRequest(model: coreMLModel) { finished, _ in
            observations = finished.results ?? []
        }
        request.imageCropAndScaleOption = .scaleFit   // 与 ultralytics 的 letterbox 对齐

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try await Self.inferenceQueue.awaiting {
            try handler.perform([request])
        }

        let arrays = observations.compactMap { ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue }
        guard let array = arrays.first else { return [] }

        let flattened = try Self.flatten(array)
        return try YoloPostprocessor.detect(YoloPostprocessor.Request(
            values: flattened.values,
            dims: flattened.dims,
            labels: labels,
            inputSide: inputSide,
            imageSize: pixelBuffer.size(applying: orientation),
            confidenceThreshold: configuration.confidenceThreshold,
            iouThreshold: configuration.iouThreshold,
            maxDetections: configuration.maxDetections
        ))
    }

    // MARK: - 模型装载

    /// Xcode 会把模型编成 `*.mlmodelc`；直接当文件夹拷贝时留下的是 `.mlpackage` / `.mlmodel`，需运行时编译。
    private static func loadModel(named name: String) throws -> (MLModel, URL) {
        let options = MLModelConfiguration()
        options.computeUnits = .all

        guard let url = bundleURL(name, "mlmodelc") ?? bundleURL(name, "mlpackage") ?? bundleURL(name, "mlmodel") else {
            throw LoadFailure.modelNotFound(name)
        }
        let modelURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        do {
            return (try MLModel(contentsOf: modelURL, configuration: options), url)
        } catch {
            throw LoadFailure.modelLoadFailed(error.localizedDescription)
        }
    }

    private static func bundleURL(_ name: String, _ extensionName: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: extensionName)
            ?? Bundle.main.url(forResource: name, withExtension: extensionName, subdirectory: "Models")
    }

    /// YOLO 输入是正方形：取图像输入约束的短边。没有图像输入（读不到尺寸约束）就返回 nil。
    private static func inputSide(of model: MLModel) -> CGFloat? {
        for description in model.modelDescription.inputDescriptionsByName.values {
            guard let constraint = description.imageConstraint else { continue }
            let side = min(CGFloat(constraint.pixelsWide), CGFloat(constraint.pixelsHigh))
            if side > 0 { return side }
        }
        return nil
    }

    // MARK: - 输出张量 → 展平数组

    private static func flatten(_ array: MLMultiArray) throws -> (values: [Float], dims: [Int]) {
        let shape = array.shape.map { $0.intValue }
        let dims = (shape.first == 1 && shape.count > 2) ? Array(shape.dropFirst()) : shape
        guard dims.count == 2 else { throw LoadFailure.unexpectedOutputShape(shape) }

        let offsets = elementOffsets(of: array)
        switch array.dataType {
        case .float32:
            let base = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
            return (offsets.map { base[$0] }, dims)
        case .double:
            let base = array.dataPointer.bindMemory(to: Float64.self, capacity: array.count)
            return (offsets.map { Float(base[$0]) }, dims)
        default:
            throw LoadFailure.unsupportedOutputDataType(String(describing: array.dataType))
        }
    }

    /// 行优先线性下标 → 元素偏移。内存已连续时直接给出 0..<count，避免逐元素计算。
    private static func elementOffsets(of array: MLMultiArray) -> [Int] {
        let shape = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        let count = array.count

        var expectedStride = 1
        var contiguous = true
        for dimension in stride(from: shape.count - 1, through: 0, by: -1) {
            guard strides[dimension] == expectedStride else { contiguous = false; break }
            expectedStride *= shape[dimension]
        }
        if contiguous { return Array(0..<count) }

        var indices = [Int](repeating: 0, count: shape.count)
        var offsets = [Int]()
        offsets.reserveCapacity(count)
        for _ in 0..<count {
            var offset = 0
            for dimension in 0..<shape.count { offset += indices[dimension] * strides[dimension] }
            offsets.append(offset)
            var dimension = shape.count - 1
            while dimension >= 0 {
                indices[dimension] += 1
                if indices[dimension] < shape[dimension] { break }
                indices[dimension] = 0
                dimension -= 1
            }
        }
        return offsets
    }
}

extension CVPixelBuffer {
    /// Vision 的 orientation 会把缓冲区旋正，归一化坐标要以**旋正后**的尺寸为基准。
    func size(applying orientation: CGImagePropertyOrientation) -> CGSize {
        let width = CGFloat(CVPixelBufferGetWidth(self))
        let height = CGFloat(CVPixelBufferGetHeight(self))
        switch orientation {
        case .up, .down, .upMirrored, .downMirrored:
            return CGSize(width: width, height: height)
        default:
            return CGSize(width: height, height: width)
        }
    }
}

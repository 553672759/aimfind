// AimFind — Vision 本地文本读取：把一帧里所有文本行原样交给上层，语义判断在 CodeGrammar/TargetMatcher。

import AVFoundation
import CoreGraphics
import Foundation
import Vision

struct VisionTextReader: TextReader {

    struct Configuration {
        /// 码面只有 ASCII 字母与数字：加中文语种只会增加误召和耗时。
        var recognitionLanguages = ["en-US"]
        /// 库位码字小、笔画接近，.fast 漏读明显，默认走 .accurate。
        var prefersAccurate = true
        var candidateCount = 1
    }

    enum ReadFailure: Error {
        case languageUnavailable([String])
    }

    let name: String
    private let configuration: Configuration

    /// Vision 的 perform 只有同步版本：给它一条私有串行队列，既保证一次只跑一个识别，
    /// 也不占用 Swift 并发线程池的工作线程。
    private static let inferenceQueue = DispatchQueue(label: "com.aimfind.text.vision", qos: .userInitiated)

    init(configuration: Configuration = Configuration()) throws {
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = configuration.prefersAccurate ? .accurate : .fast
        let supported = Set(try probe.supportedRecognitionLanguages())
        guard configuration.recognitionLanguages.allSatisfy(supported.contains) else {
            throw ReadFailure.languageUnavailable(configuration.recognitionLanguages)
        }
        self.configuration = configuration
        self.name = configuration.prefersAccurate ? "Vision Text · accurate" : "Vision Text · fast"
    }

    func read(_ pixelBuffer: CVPixelBuffer,
              orientation: CGImagePropertyOrientation) async throws -> [TextHit] {
        try await perform(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]))
    }

    /// 相册/截图里的码：照片已经是正的，orientation 走 .up。
    func read(cgImage: CGImage,
              orientation: CGImagePropertyOrientation = .up) async throws -> [TextHit] {
        try await perform(VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:]))
    }

    private func perform(_ handler: VNImageRequestHandler) async throws -> [TextHit] {
        var observations: [VNObservation] = []
        let request = VNRecognizeTextRequest { finished, _ in
            observations = finished.results ?? []
        }
        request.recognitionLanguages = configuration.recognitionLanguages
        request.recognitionLevel = configuration.prefersAccurate ? .accurate : .fast
        request.usesLanguageCorrection = false        // ★ 字母数字码上语言纠正是反作用
        // revision 不写死：Vision 默认用当前系统支持的最新版（iOS 18+ 即 revision3，
        // 而 revision1/2 常量在新 SDK 里已标 deprecated）。

        try await Self.inferenceQueue.awaiting {
            try handler.perform([request])
        }

        return observations.compactMap { entry -> TextHit? in
            guard let observation = entry as? VNRecognizedTextObservation,
                  let text = observation.topCandidates(configuration.candidateCount).first else { return nil }
            return TextHit(raw: text.string,
                           confidence: Double(text.confidence),
                           box: Self.topLeftBox(of: observation))
        }
    }

    /// Vision 的 boundingBox 是**左下原点**；上层统一用左上原点。
    static func topLeftBox(of observation: VNRecognizedTextObservation) -> CGRect {
        let box = observation.boundingBox
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }
}

// AimFind — 相机页运行时：AVCaptureSession → 帧闸 → 文本读取 → 多标签匹配 → 连续帧稳定判定。
// 会话配置、startRunning、识别调度都在 videoQueue / Vision 线程；主线程只读 published 值。
//
// 线程约定（编译器查不了，靠这里说清）：可变的采集/识别状态只在 videoQueue 上碰；
// published 结果一律 hop 回主线程写，UI 侧只读。

import AVFoundation
import CoreGraphics
import QuartzCore
import SwiftUI
import UIKit
import Vision

final class CameraPageModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                            @unchecked Sendable {

    enum Engine: Equatable {
        case loading
        case ready(name: String)
        case failed(reason: String)
    }

    @Published private(set) var hits: [LocatedCode] = []
    /// 已确认找到的标签（`SearchTarget.id`）。多标签时"找到 k/N"的 k 就是它。
    @Published private(set) var found: Set<String> = []
    /// 最近一次新找到的标签，给大字显示用。
    @Published private(set) var lastFound: LocatedCode?
    @Published private(set) var imageAspect: CGFloat = 0
    /// 该合焦的位置（图像归一化中心）；预览层负责换算成设备坐标。
    @Published private(set) var autoFocusCenter: CGPoint?
    @Published private(set) var engine: Engine = .loading
    @Published private(set) var isStreaming = false
    /// 货架清点结论：把"还没扫到"和"这层没有"区分开。
    @Published private(set) var sweep: ShelfCensus.Verdict?
    @Published private(set) var zoomFactor: CGFloat = 1

    let targets: [SearchTarget]
    let session = AVCaptureSession()

    /// 连续这么多帧读到同一个标签才记为"找到"：挡掉偶发误读与手抖。
    static let stableHits = 3

    private let videoQueue = DispatchQueue(label: "com.aimfind.camera.video", qos: .userInitiated)
    private let minimumFrameInterval: CFTimeInterval

    private var reader: TextReader?
    private var videoDevice: AVCaptureDevice?
    private var lastFocusedCenter: CGPoint?
    private var lastFocusTime: TimeInterval = 0

    private var configured = false
    private var running = false
    private var inferenceInFlight = false
    private var lastAcceptedTime: CFTimeInterval = 0
    private var frameIndex = 0
    private var streaks: [String: Int] = [:]
    private var census = ShelfCensus()

    init(targets: [SearchTarget]) {
        self.targets = targets
        self.minimumFrameInterval = 1.0 / CFTimeInterval(max(ReadingConfig.maxFrameRate, 1))
        super.init()
    }

    var allFound: Bool { !targets.isEmpty && found.count >= targets.count }

    // MARK: - 生命周期

    func start() {
        videoQueue.async { [weak self] in self?.startWork() }
    }

    func stop() {
        videoQueue.async { [weak self] in
            guard let self, self.running else { return }
            self.session.stopRunning()
            self.running = false
            self.publishStreaming(false)
        }
    }

    private func startWork() {
        guard !running else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DebugLog.note("no back camera available")
            publishEngine(.failed(reason: "这台设备没有可用的后置摄像头。"))
            return
        }
        installReader()
        do {
            try configureSession(with: device)
        } catch let failure as SessionSetupFailure {
            publishEngine(.failed(reason: failure.displayText))
            return
        } catch {
            publishEngine(.failed(reason: error.localizedDescription))
            return
        }
        session.startRunning()
        running = true
        publishStreaming(true)
        DebugLog.note("searching for " + targets.map(\.display).joined(separator: ", "))
    }

    private enum SessionSetupFailure: Error {
        case inputUnavailable(String)
        case outputUnavailable

        var displayText: String {
            switch self {
            case .inputUnavailable(let reason): return "相机输入不可用：\(reason)"
            case .outputUnavailable: return "相机取帧通道不可用。"
            }
        }
    }

    private func configureSession(with device: AVCaptureDevice) throws {
        guard !configured else { return }
        session.beginConfiguration()
        // 远处小字首先输在像素上：1080p 给 Vision 的文本高度明显好于 720p，
        // 代价是单帧更慢 —— 帧闸会直接把超预算的帧丢掉，预览不会卡。
        session.sessionPreset = .hd1920x1080

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw SessionSetupFailure.inputUnavailable(error.localizedDescription)
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw SessionSetupFailure.inputUnavailable("设备被其它进程占用")
        }
        session.addInput(input)
        videoDevice = device
        configureDefaultFocus(device)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw SessionSetupFailure.outputUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
    }

    private func configureDefaultFocus(_ device: AVCaptureDevice) {
        guard lock(device) else { return }
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
    }

    /// 读码是系统自带能力，不需要往 bundle 里放模型；这里只可能因为语种不支持而失败。
    private func installReader() {
        guard reader == nil else { return }
        do {
            let installed = try VisionTextReader()
            reader = installed
            DebugLog.note("reader ready: \(installed.name)")
            publishEngine(.ready(name: installed.name))
        } catch {
            DebugLog.note("reader unavailable: \(error)")
            publishEngine(.failed(reason: error.localizedDescription))
        }
    }

    // MARK: - 对焦与变焦

    /// 点击对焦；自动合焦走的也是这里（坐标由预览层按同一映射换算好）。
    func focus(at devicePoint: CGPoint) {
        videoQueue.async { [weak self] in self?.applyFocus(devicePoint) }
    }

    private func applyFocus(_ point: CGPoint) {
        guard let device = videoDevice, lock(device) else { return }
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
        }
        if device.isExposurePointOfInterestSupported,
           device.isExposureModeSupported(.continuousAutoExposure) {
            // 曝光点位设了但模式保持连续，否则每次合焦画面会跳一下亮度
            device.exposurePointOfInterest = point
        }
    }

    /// 双指放大：主摄最近对焦距离约 10cm，贴太近时退开或变焦是仅有的两条路。
    func setZoom(_ factor: CGFloat) {
        videoQueue.async { [weak self] in self?.applyZoom(factor) }
    }

    private func applyZoom(_ factor: CGFloat) {
        guard let device = videoDevice, lock(device) else { return }
        defer { device.unlockForConfiguration() }
        let ceiling = min(device.activeFormat.videoMaxZoomFactor, 8)
        guard ceiling > 1 else { return }
        let target = min(max(factor, device.minAvailableVideoZoomFactor), ceiling)
        device.ramp(toVideoZoomFactor: target, withRate: 6)
        DispatchQueue.main.async { [weak self] in self?.zoomFactor = target }
    }

    private func lock(_ device: AVCaptureDevice) -> Bool {
        do { try device.lockForConfiguration(); return true }
        catch { DebugLog.note("device busy, configuration skipped"); return false }
    }

    // MARK: - 取帧

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let reader, !targets.isEmpty else { return }
        // 帧闸：上一帧还在读、或距上帧不足 1/maxFrameRate，直接丢
        let now = CACurrentMediaTime()
        guard !inferenceInFlight, now - lastAcceptedTime >= minimumFrameInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        inferenceInFlight = true
        lastAcceptedTime = now
        frameIndex += 1
        let index = frameIndex
        // 锁竖屏 + 后置摄像头：缓冲是横的，交给 Vision 旋正（.right）
        let orientation: CGImagePropertyOrientation = .right
        let size = pixelBuffer.size(applying: orientation)
        let aspect = size.height > 0 ? size.width / size.height : 0

        // 闭包持有 sampleBuffer，识别期间底层像素不会被池子回收
        Task { [weak self, sampleBuffer] in
            guard let self else { return }
            var matched: [LocatedCode] = []
            var sweep: ShelfCensus.Verdict?
            if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                if let lines = try? await reader.read(buffer, orientation: orientation) {
                    matched = TargetMatcher.locate(lines, targets: self.targets)
                    self.census.register(ShelfCensus.fullCodes(in: lines), at: CACurrentMediaTime())
                    sweep = self.census.verdict(now: CACurrentMediaTime())
                    if index % 10 == 1 {
                        DebugLog.note("frame #\(index) lines="
                            + lines.prefix(6).map { "\"\($0.raw)\"" }.joined(separator: " "))
                    }
                }
            }
            self.videoQueue.async { self.inferenceInFlight = false }
            await self.publish(matched, aspect: aspect, sweep: sweep)
        }
    }

    // MARK: - 发布与判定（主线程）

    @MainActor
    private func publish(_ matched: [LocatedCode], aspect: CGFloat, sweep: ShelfCensus.Verdict?) async {
        hits = matched
        imageAspect = aspect
        self.sweep = allFound ? nil : sweep
        consume(matched)
        refocusIfNeeded(matched)
    }

    /// 每个标签各自计"连续命中帧数"，够了才记为找到；一次锁上不重复触发反馈。
    private func consume(_ matched: [LocatedCode]) {
        var seen: Set<String> = []
        for hit in matched {
            let id = hit.target.id
            seen.insert(id)
            let count = (streaks[id] ?? 0) + 1
            streaks[id] = count
            guard count >= Self.stableHits, !found.contains(id) else { continue }
            found.insert(id)
            lastFound = hit
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DebugLog.note("found \(hit.display) confidence=\(hit.confidence) strength=\(hit.strength)")
        }
        streaks = streaks.filter { seen.contains($0.key) }
    }

    /// 还没找到的目标优先吸引合焦；全找到之后不再动镜头。
    private func refocusIfNeeded(_ matched: [LocatedCode]) {
        let pending = matched.first { !found.contains($0.target.id) }
        let now = CACurrentMediaTime()
        guard let center = AutoFocus.target(box: pending?.box,
                                            lastFocused: lastFocusedCenter,
                                            now: now,
                                            lastAt: lastFocusTime) else { return }
        lastFocusedCenter = center
        lastFocusTime = now
        autoFocusCenter = center
    }

    private func publishEngine(_ engine: Engine) {
        DispatchQueue.main.async { [weak self] in self?.engine = engine }
    }

    private func publishStreaming(_ streaming: Bool) {
        DispatchQueue.main.async { [weak self] in self?.isStreaming = streaming }
    }
}

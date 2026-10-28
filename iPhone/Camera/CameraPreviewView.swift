// AimFind — 取景视图：AVCaptureVideoPreviewLayer 的宿主，aspect fill 铺满 + 竖屏旋转。
// 触摸对焦在这里做坐标换算：layer 的点击点 → 设备对焦坐标系（`captureDevicePointConverted`
// 会按当前视频方向处理，别自己写旋转公式）。

import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let imageAspect: CGFloat
    /// 识别到的位置（图像归一化中心）；变了就走一次和点击相同的换算 → 合焦
    let autoFocusCenter: CGPoint?
    /// 合焦回调：手指点击与自动对焦共用同一条路径
    /// (layer 坐标 = 画准星用, 设备坐标 = 设对焦点用)
    let onFocusAt: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.connection?.videoRotationAngle = 90
        view.onFocusAt = onFocusAt
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onFocusAt = onFocusAt
        guard let center = autoFocusCenter, center != context.coordinator.lastHandled else { return }
        context.coordinator.lastHandled = center
        guard uiView.bounds.width > 0, uiView.bounds.height > 0 else { return }
        // 与 DetectionOverlay 用同一个映射，保证"框在哪，焦点就在哪"
        let mapper = ViewportMapper(imageAspect: imageAspect)
        let mapped = mapper.rect(CGRect(x: center.x, y: center.y, width: 0, height: 0), in: uiView.bounds.size)
        uiView.autoFocus(at: CGPoint(x: mapped.midX, y: mapped.midY))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastHandled: CGPoint?
    }

    final class PreviewUIView: UIView {
        var onFocusAt: ((CGPoint, CGPoint) -> Void)?

        /// layer 点 → 设备对焦坐标（方向换算交给系统，别自己写公式）
        func autoFocus(at layerPoint: CGPoint) {
            onFocusAt?(layerPoint, previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint))
        }

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first, previewLayer.session?.inputs.isEmpty == false else { return }
            let layerPoint = touch.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            onFocusAt?(layerPoint, devicePoint)
        }
    }
}

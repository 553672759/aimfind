// AimFind — 帧几何：Vision 的 orientation 会旋正缓冲，归一化坐标必须以旋正后的尺寸为基准。

import CoreGraphics
import CoreVideo
import ImageIO

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

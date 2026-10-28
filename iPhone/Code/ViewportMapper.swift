// AimFind — overlay 坐标映射：图像归一化坐标 → 预览视口坐标。
// 预览层是 .resizeAspectFill（铺满并裁边），框必须走同一套 cover 变换，否则会和画面错位。

import CoreGraphics

struct ViewportMapper {
    /// 旋正后的图像宽高比。<= 0 表示还没有帧，退化成铺满视口。
    let imageAspect: CGFloat

    func rect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        guard imageAspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height,
                          width: normalized.width * size.width, height: normalized.height * size.height)
        }
        // 把图像看成 (imageAspect × 1) 的单位矩形，等比放大到覆盖视口，再居中
        let scale = max(size.width / imageAspect, size.height)
        let drawn = CGSize(width: imageAspect * scale, height: scale)
        let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        return CGRect(x: origin.x + normalized.minX * drawn.width,
                      y: origin.y + normalized.minY * drawn.height,
                      width: normalized.width * drawn.width,
                      height: normalized.height * drawn.height)
    }
}

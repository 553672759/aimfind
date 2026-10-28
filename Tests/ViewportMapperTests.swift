import CoreGraphics
import Testing

@testable import AimFind

struct ViewportMapperTests {

    @Test func coversViewportAndCentersCrop() {
        // 1080×1920（aspect 0.5625）放进 400×800 视口：按高度铺满，宽度溢出被裁
        let mapper = ViewportMapper(imageAspect: 0.5625)
        let rect = mapper.rect(CGRect(x: 0, y: 0, width: 1, height: 1), in: CGSize(width: 400, height: 800))
        #expect(near(rect.height, 800))
        #expect(near(rect.width, 450))
        #expect(near(rect.minX, -25))
        #expect(near(rect.minY, 0))
    }

    @Test func imageCenterMapsToViewportCenter() {
        // 框的中心落在图像正中 (0.5, 0.5)
        let mapper = ViewportMapper(imageAspect: 0.75)
        let rect = mapper.rect(CGRect(x: 0.45, y: 0.4, width: 0.1, height: 0.2), in: CGSize(width: 300, height: 600))
        #expect(near(rect.midX, 150))   // 铺满后 450×600，横偏 -75
        #expect(near(rect.midY, 300))
    }

    @Test func boxSizeScalesWithCoverFactor() {
        let mapper = ViewportMapper(imageAspect: 0.75)
        let rect = mapper.rect(CGRect(x: 0, y: 0, width: 0.1, height: 0.1), in: CGSize(width: 300, height: 600))
        #expect(near(rect.width, 45))    // 0.1 × 450
        #expect(near(rect.height, 60))   // 0.1 × 600
    }

    @Test func fallsBackToViewportUntilFirstFrame() {
        let mapper = ViewportMapper(imageAspect: 0)
        #expect(mapper.rect(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), in: CGSize(width: 200, height: 100))
                == CGRect(x: 50, y: 25, width: 100, height: 50))
    }

    private func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
}

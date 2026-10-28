># 目标检测框架设计（相机实时链路）

> **接线状态（2026-10-27）**：相机页当前跑的是**读码引擎** `CodeReader`（见 `docs/CODE_READING.md`），
> 本文件的 YOLO 检测层作为 L3 备选路线保留 —— 代码在 `iPhone/Detection/`、测试在跑、文档在此，
> 只是没有从 `CameraPageModel` 调用。要把两阶段（YOLO 定位标签牌 → 文本精读）接上，
> 在 `installReader()` 旁并列装配 `Detector` 即可，坐标契约与 overlay 完全共用。

> AimFind 的检测层。**打开相机即在取景画面上跑目标检测**，框与读数实时叠在预览上。
> 目标不是"跑通一次 YOLO"，而是把**引擎可换、坐标可算、模型可缺**这三件事定死，
> 后面换成自训模型 / 换推理引擎 / 加跟踪计数时不用动相机代码。

## 1. 分层

```
HomeView（一个按钮）
   │  权限 + 硬件闸门 CameraGate
   ▼
CameraPage ──► CameraPreviewView（AVCaptureVideoPreviewLayer，aspect fill）
   │           DetectionOverlay（SwiftUI Canvas，描框 + 类名/置信度）
   ▼
CameraPageModel        会话 / 帧闸 / 调度 / 发布        ← iPhone/Camera/
   ▼
Detector（协议）       detect(CVPixelBuffer, orientation) async throws → [Detection]
   ▼
VisionYoloDetector     Core ML + Vision 推理，输出张量展平  ← iPhone/Detection/
   ▼
YoloPostprocessor      纯函数：布局判定 / 解码 / 阈值 / NMS / letterbox 反映射
```

单向依赖：`Camera → Detection → (CoreML/Vision)`。检测层不认识 UI，相机层不认识 YOLO。

## 2. 数据契约

```swift
struct Detection {          // 一个框
    let classIndex: Int
    let label: String
    let confidence: Double  // 0...1
    let box: CGRect         // 归一化 0...1，左上原点，**旋正后的图像**坐标系
}

struct DetectionFrame {     // 一帧的结果
    let frameIndex: Int     // UI 可据此丢弃过期结果
    let imageSize: CGSize   // 旋正后的帧尺寸 → overlay 算 aspect-fill 映射
    let detections: [Detection]
}
```

坐标只有两个约定，别混：

| 阶段 | 空间 | 谁负责 |
|---|---|---|
| 模型输出 | letterbox 后的输入像素（如 640×640） | `YoloPostprocessor.Letterbox` |
| `Detection.box` | 图像归一化 0...1（已旋正、已裁进画面） | 同上 |
| 屏幕位置 | 视口 points | `ViewportMapper`（Canvas 里执行） |

预览用 `.resizeAspectFill`（铺满裁边），所以 `ViewportMapper` 必须走同一套 cover 变换，
否则框会横向偏移——这是这套映射唯一的存在理由，`ViewportMapperTests` 锁住它。

## 3. 帧闸（不积压）

采集回调在 `videoQueue`（串行）上，两条件全满足才送检：

1. `!inferenceInFlight` —— 一帧在推就丢新帧，**不做排队**（实时取景要的是最新画面）；
2. `now - lastAcceptedTime >= 1 / DetectionConfig.maxFrameRate`（默认 12 fps）。

另外 `alwaysDiscardsLateVideoFrames = true`，像素缓冲由闭包持有 `CMSampleBuffer` 直到推理结束
（不持有会被 CVPixelBufferPool 回收，边推边复用就是随机崩溃）。

会话预设 `.hd1280x720`，`VisionYoloDetector` 把帧交给 `VNCoreMLRequest`
（`imageCropAndScaleOption = .scaleFit`，与 ultralytics 的 letterbox 等价）。
iOS 27 SDK 的 `VNImageRequestHandler` 只有同步 `performRequests:error:`（没有 completion-handler 版本），
所以推理挂在 `VisionYoloDetector.inferenceQueue` 这条私有串行队列上再桥接成 `async`：
既保证同一时刻只有一次 Vision 调用，也不阻塞 Swift 并发线程池的工作线程。

## 4. 模型装载与缺失降级

`VisionYoloDetector.init` 顺序：bundle 里找 `mlmodelc` → `mlpackage` → `mlmodel`
（含 `Models/` 子目录两种路径），原样拷贝的包走 `MLModel.compileModel` 兜底；
输入边长从模型 metadata 的 image constraint 读（不写死 640）；类名优先用 metadata 的
`classLabels`，缺失时回退 `COCOClassLabels.coco80`。

找不到模型 **不是崩溃，也不假装能跑**：`CameraPageModel.engine = .modelMissing(name)`，
页面顶部徽章显示「无模型」、底部给出放置说明，取景照常。这条降级路径是有意为之——
和 WristEcho 里 `MAC-CALIBRATION` 桩的做法一致。

## 5. 三种 YOLO 导出都能吃

`YoloPostprocessor.layout(for dims:)` 按形状分派，不需要告诉它模型是哪一代：

| 形状（去掉 batch） | 布局 | 备注 |
|---|---|---|
| `[84, 8400]` | `.anchorsFirst` | YOLOv8/v11 默认导出，`attrs > anchors` |
| `[25200, 85]` | `.anchorsLast` | YOLOv5 风格/转置导出 |
| `[300, 6]` | `.endToEnd` | `nms=True` 端到端，已在模型里 NMS |

objectness 有无由类名表对齐推断（`attrs - 5 == 类数` → 有；`attrs - 4 == 类数` → 没有）。
NMS 是同类别内贪心压制（IoU 阈值默认 0.45），跨类别不互相吞。

## 6. 扩展点

| 要加的东西 | 动哪里 |
|---|---|
| 换推理引擎（Vision 自训 / Apple FM / 别的框架） | 实现 `Detector`，在 `CameraPageModel.loadDetector()` 里换装配 |
| 多引擎并存 / A-B | `Detector` 上加 `name`，`CameraPageModel` 持数组并择优 |
| 自训类别（找"我的钥匙"） | 导出时把类名写进 metadata；或替换 `COCOClassLabels` |
| 跟踪 / 计数 / 停留时长 | 消费 `DetectionFrame`（`frameIndex` 已给好），别改后处理层 |
| 拍照后再判、或"看到目标自动快门" | `CameraPageModel` 加 `AVCapturePhotoOutput`，`result` 已经是每帧快照 |
| 阈值/上限调参 | `DetectionConfig` 一处 |

## 7. 已知校准点（诚实清单）

1. **未真机验证。** 纯逻辑层（后处理 + 坐标映射）已在 macOS 上用 SwiftPM 真跑过 15 个测试；
   但相机采集 → 推理 → overlay 这条链路只在 `generic/platform=iOS` 编译通过
   （本机没有任何 iOS 模拟器 runtime，模拟器本身也没有摄像头），
   帧率、延迟、框对齐、模型输入尺寸读取都必须在真机上量。
2. **`.endToEnd` 的坐标空间**按"letterbox 输入像素"解（ultralytics 常见导出）。若某个导出给的是
   0...1 归一化框，框会缩成左上角一小块——那时在 `candidates(for: .endToEnd)` 分支里按
   `max(coords) <= 1` 判断一次即可，其余路径不受影响。
3. **方向写死竖屏**：`orientation = .right` 对应"锁竖屏 + 后置摄像头"。要做横屏/前摄镜像，
   得按 UI 方向算 `CGImagePropertyOrientation`，并同步 `CameraPreviewView` 的 `videoRotationAngle`。
4. **模型体积与下载**：模型进 bundle 会撑大安装包；要做按需下载，参照 WristEcho 的
   `ModelAsset`（校验主机 + SHA256）思路，别裸下。
5. `AVCaptureSession` 在新 SDK 上有被更高阶 API 取代的趋势（编译有告警时按提示迁移），
   检测层的坐标契约不受影响。

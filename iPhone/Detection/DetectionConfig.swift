// AimFind — 检测层配置：换模型只改这一处。

enum DetectionConfig {
    /// 期望的资源名（不含扩展名）。把 ultralytics 导出的 `YOLOv8n.mlpackage` 放进
    /// `Resources/Models/` 即可生效；换了别的名字就改这里。
    static let modelResourceName = "YOLOv8n"

    static let confidenceThreshold: Float = 0.25
    static let iouThreshold: Float = 0.45
    static let maxDetections = 40

    /// 送进检测引擎的帧上限：高于此值的帧直接丢弃，避免推理积压拖慢预览。
    static let maxFrameRate: Int = 12
}

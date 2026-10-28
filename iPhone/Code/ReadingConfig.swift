// AimFind — 取景识别的配置。

enum ReadingConfig {
    /// 送进文字识别的帧上限：高于此值的帧直接丢弃，避免推理积压拖慢预览。
    static let maxFrameRate = 12
}

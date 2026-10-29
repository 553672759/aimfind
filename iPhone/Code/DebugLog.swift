// AimFind — Debug 诊断输出。真机没有 UI 可看时，由 `devicectl device process launch --console`
// 把 stdout 接回 Mac（见 docs/BUILD.md §5）。Release 构建里这些调用整体不存在。

enum DebugLog {
    static func note(_ message: String) {
        #if DEBUG
        print("[AimFind] \(message)")
        #endif
    }
}

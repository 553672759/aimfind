// AimFind — 把同步阻塞调用挂到指定队列并以 async 等待（Vision 的 perform 只有同步版本）。

import Foundation

extension DispatchQueue {
    func awaiting<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { resume in
            async {
                do { resume.resume(returning: try work()) } catch { resume.resume(throwing: error) }
            }
        }
    }
}

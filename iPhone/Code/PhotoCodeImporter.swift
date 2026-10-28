// AimFind — 从相册截图里取码：图片 → 文本行 → CodeInbox。
// 语义筛选全在 CodeInbox（纯函数、有单测），这里只做图片解码与 OCR。

import UIKit

enum PhotoCodeImporter {

    enum ImportError: Error {
        case unreadableImage
    }

    static func codes(from data: Data) async throws -> [SearchTarget] {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw ImportError.unreadableImage
        }
        let reader = try VisionTextReader()
        let lines = try await reader.read(cgImage: cgImage)
        return CodeInbox.extract(lines: lines.map(\.raw))
    }

    /// 逐张读，单张失败不影响其它张（相册里偶尔有 iCloud 还没下下来的项）。
    static func codes(from datas: [Data]) async -> [SearchTarget] {
        var merged: [SearchTarget] = []
        var seen = Set<String>()
        for data in datas {
            let codes = (try? await codes(from: data)) ?? []
            for code in codes where seen.insert(code.id).inserted {
                merged.append(code)
            }
        }
        return merged
    }
}

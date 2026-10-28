// AimFind — 从照片/通知文本里收码（纯函数）。
//
// 只收**带货架/层前缀的完整码**（`B2-4-2073`、`C5-5-7225`）。截图里裸的 4 位数字
// 可能是日期、金额、门牌，收进来就是给自己制造误找；也一律不接受需要修正的读法 ——
// 导入是离线动作，宁可漏一条让用户再传一次，也不放一个错码进标签列表。

import Foundation

enum CodeInbox {

    static func extract(lines: [String], limit: Int = 12) -> [SearchTarget] {
        var seen = Set<String>()
        var results: [SearchTarget] = []
        for line in lines {
            for reading in CodeGrammar.readings(in: line, maxCorrections: 0) {
                guard reading.code.hasPrefix,
                      let shelf = reading.code.shelf,
                      let level = reading.code.level else { continue }
                let target = SearchTarget.located(shelf: shelf, level: level, tail: reading.code.tail)
                guard seen.insert(target.id).inserted else { continue }
                results.append(target)
                if results.count >= limit { return results }
            }
        }
        return results
    }
}

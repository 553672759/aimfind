// AimFind — 货架清点（纯函数）：把"扫过了但没找到"和"还没扫到"区分开。
//
// 现场最难受的不是没找到，而是**不知道是没扫到还是这里真没有**。
// 所以统计画面里出现过的所有完整取件码（不限于目标）：
//   一个都没见到 → 还在扫，别下结论；
//   见到不少、且一段时间没有新码出现 → 这一层大概率扫完了，提示换一层。

import Foundation

struct ShelfCensus {
    /// 一个码被"忘掉"的时间：镜头移开后不再计入这一层。
    static let ttl: TimeInterval = 4
    /// 判定"扫完了"需要安静多久（没有新码出现）。
    static let settleInterval: TimeInterval = 2.5
    /// 少于这么多个码不下"这里没有"的结论 —— 一两个可能只是扫到边角。
    static let enoughToJudge = 3

    private var lastSeen: [String: TimeInterval] = [:]
    private var lastChange: TimeInterval = 0

    enum Verdict: Equatable {
        case sweeping(seen: Int)   // 还在扫
        case notHere(seen: Int)    // 这层扫过了，没有你要的
    }

    /// 一帧里出现的所有完整码。
    static func fullCodes(in hits: [TextHit]) -> [String] {
        var codes: [String] = []
        for hit in hits {
            for reading in CodeGrammar.readings(in: hit.raw, maxCorrections: 0) where reading.code.hasPrefix {
                codes.append(reading.code.display)
            }
        }
        return codes
    }

    mutating func register(_ codes: [String], at now: TimeInterval) {
        for code in codes where lastSeen[code] == nil || now - lastSeen[code]! > Self.ttl {
            lastChange = now
        }
        for code in codes { lastSeen[code] = now }
    }

    func verdict(now: TimeInterval) -> Verdict? {
        let alive = lastSeen.values.filter { now - $0 < Self.ttl }
        guard !alive.isEmpty else { return nil }
        return (now - lastChange >= Self.settleInterval && alive.count >= Self.enoughToJudge)
            ? .notHere(seen: alive.count)
            : .sweeping(seen: alive.count)
    }
}

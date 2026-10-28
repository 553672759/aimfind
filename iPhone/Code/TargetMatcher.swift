// AimFind — 目标匹配（纯函数）：把一帧的 OCR 结果收敛成"要找的那件在哪"。
//
// 搜索键有两种：
//   6760          只搜尾号（远距离最常只有它读得到）
//   38-1-6760     搜完整库位码：前缀对不上的一律不标 —— 标错货架比不标更糟
//
// 输出强度：exact（尾号精确）> probable（尾号需一位混淆修正）。
// 同级排序按**框高度**（字号大 = 更近/更醒目 = 更可能是主编号），再按 OCR 置信度。

import CoreGraphics
import Foundation

enum SearchTarget: Equatable, Identifiable {
    /// 记住上一次搜的码（首页输入框回填用）。
    static let storageKey = "aimfind.searchTarget"

    case tail(String)
    case located(shelf: String, level: String, tail: String)

    var id: String { display }

    var tail: String {
        switch self {
        case .tail(let value): return value
        case .located(_, _, let value): return value
        }
    }

    var display: String {
        switch self {
        case .tail(let value): return value
        case .located(let shelf, let level, let value): return "\(shelf)-\(level)-\(value)"
        }
    }

    /// 用户在首页输入的东西：`6760` 或 `38-1-6760`（大小写、空格、破折号都容错）。
    static func parse(_ text: String) -> SearchTarget? {
        let parts = CodeGrammar.tokens(in: text)
        if parts.count == 1, let reading = CodeGrammar.bareTail(parts[0], maxCorrections: 0) {
            return .tail(reading.code.tail)
        }
        if parts.count == 3,
           let reading = CodeGrammar.fullCode(shelf: parts[0], level: parts[1], tail: parts[2],
                                             maxCorrections: 0) {
            return .located(shelf: reading.code.shelf!, level: reading.code.level!, tail: reading.code.tail)
        }
        return nil
    }
}

struct LocatedCode: Equatable {
    /// 命中的是哪一个搜索目标（多标签同时找时靠它区分）。
    let target: SearchTarget

    enum Strength: Int, Comparable {
        case probable = 0
        case exact = 1

        static func < (left: Strength, right: Strength) -> Bool { left.rawValue < right.rawValue }
    }

    /// 目标带前缀时，读到的前缀是"一致"还是"没读到"。
    enum PrefixState: Equatable {
        case notRequired
        case matched
        case absent
    }

    let strength: Strength
    let prefix: PrefixState
    let code: CodeGrammar.Code
    let confidence: Double
    let box: CGRect

    var display: String { code.display }
}

enum TargetMatcher {

    static func locate(_ hits: [TextHit], targets: [SearchTarget],
                       maxCorrections: Int = 1, maxResults: Int = 6) -> [LocatedCode] {
        var results: [LocatedCode] = []

        for hit in hits {
            // 同一行文本只取最强的那条解读（一行里可能既像完整码又像裸尾号，也可能命中多个标签）
            var bestForLine: LocatedCode?
            for reading in CodeGrammar.readings(in: hit.raw, maxCorrections: maxCorrections) {
                for target in targets {
                    guard let located = classify(reading: reading, target: target) else { continue }
                    let placed = LocatedCode(target: target, strength: located.strength, prefix: located.prefix,
                                             code: reading.code, confidence: hit.confidence, box: hit.box)
                    if bestForLine == nil || rank(of: placed) > rank(of: bestForLine!) { bestForLine = placed }
                }
            }
            if let placed = bestForLine { results.append(placed) }
        }

        // 同尾号的两处 = 两件包裹，都标出来；排序后按上限截断
        return Array(results.sorted { rank(of: $0) > rank(of: $1) }.prefix(maxResults))
    }

    /// 一条解读相对目标的判定；返回 nil = 不是我们要的东西（或前缀对不上）。
    static func classify(reading: CodeGrammar.Reading,
                         target: SearchTarget) -> (strength: LocatedCode.Strength, prefix: LocatedCode.PrefixState)? {
        guard reading.code.tail == target.tail else { return nil }
        let strength: LocatedCode.Strength = reading.corrections == 0 ? .exact : .probable

        switch target {
        case .tail:
            return (strength, .notRequired)
        case .located(let shelf, let level, _):
            guard let readingShelf = reading.code.shelf, let readingLevel = reading.code.level else {
                return (strength, .absent)          // 只读到尾号：可以标，但要提示"前缀未确认"
            }
            guard readingShelf == shelf, readingLevel == level else { return nil }   // 前缀不符 → 不标
            return (strength, .matched)
        }
    }

    /// 排序键：强度 → 框高度（字号/远近）→ 置信度。
    private static func rank(of located: LocatedCode) -> (Int, Int, Int) {
        (located.strength.rawValue,
         Int(located.box.height * 10_000),
         Int(located.confidence * 10_000))
    }
}

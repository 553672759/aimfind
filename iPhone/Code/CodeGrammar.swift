// AimFind — 库位码语法（纯函数，不碰 Vision，可离线喂假 OCR 结果单测）。
//
// 真实场景里的码（见 docs/CODE_READING.md）：
//   38-1-6760   包裹标签：货架 38 / 层 1 / 尾号 6760
//   1-4-XXXX    货架条：XXXX 是包裹尾号占位
//   6760        包裹上印得最大的那 4 位 —— 远距离往往只读得出它
//   C-2-4456    字母货架号
// 规则：段1 = 1–2 位 ASCII 字母或数字；段2 = 1–2 位数字；段3 = **恰好 4 位数字**。
// 尾号定长是把它和日期/价格/距离区分开的依据。
//
// 三条保守规则（"宁可不出，不出错"）：
//   1. token 边界切分 —— 绝不做子串匹配，`YT8747063366760` 里藏的 6760 不算读到；
//   2. 某一位只在「该位字符集下解释唯一」时才修正，二义（如数字位上的 0 可能是 O/D/Q）直接放弃；
//   3. 只修正尾号，不修正货架/层 —— 前缀读错会让你以为"不在这个架"，代价太高。

import Foundation

enum CodeGrammar {

    static let tailLength = 4
    static let shelfMax = 2
    static let levelMax = 2

    struct Code: Equatable {
        let shelf: String?
        let level: String?
        let tail: String

        var hasPrefix: Bool { shelf != nil && level != nil }

        var display: String {
            guard let shelf, let level else { return tail }
            return "\(shelf)-\(level)-\(tail)"
        }
    }

    struct Reading: Equatable {
        let code: Code
        let corrections: Int
        /// 尾号是「整段独立读到的」还是跟在货架前缀后面的
        var isBareTail: Bool { code.shelf == nil }
    }

    /// 双向混淆表：修正时还会按目标位的字符集再过滤一遍，剩下的唯一候选才敢用。
    static let confusions: [Character: [Character]] = [
        "O": ["0", "D", "Q"], "0": ["O", "D", "Q"], "D": ["0", "O"], "Q": ["O", "0"],
        "I": ["1", "L"], "L": ["1", "I"], "1": ["I", "L", "T"], "T": ["1", "7"],
        "Z": ["2"], "2": ["Z"],
        "S": ["5"], "5": ["S"],
        "G": ["6"], "6": ["G"],
        "B": ["8"], "8": ["B", "3"],
        "A": ["4"], "4": ["A"],
        "7": ["T"], "3": ["B", "E"],
    ]

    // MARK: - 一行 OCR → 所有解读

    static func readings(in raw: String, maxCorrections: Int = 1) -> [Reading] {
        let parts = tokens(in: raw)
        guard parts.count > 0 else { return [] }

        var readings: [Reading] = []
        var consumed: Set<Int> = []
        var offset = 0
        while offset + 3 <= parts.count {
            if let reading = fullCode(shelf: parts[offset], level: parts[offset + 1],
                                      tail: parts[offset + 2], maxCorrections: maxCorrections) {
                readings.append(reading)
                consumed.formUnion([offset, offset + 1, offset + 2])
                offset += 3
                continue
            }
            offset += 1
        }

        for (index, part) in parts.enumerated() where !consumed.contains(index) {
            if let reading = bareTail(part, maxCorrections: maxCorrections) {
                readings.append(reading)
            }
        }
        return readings.sorted { $0.corrections < $1.corrections }
    }

    /// 只在 **ASCII 字母数字** 处连续，其余一律是分隔符。
    /// 中文必须算分隔符：真实通知里写的是「取件码为C5-5-7225」，
    /// 若把中文当字母数字，token 会变成「码为C5」，码就丢了。
    /// `YT8747063366760` 仍然是一个整 token，所以不会把结尾的 6760 误当尾号。
    static func tokens(in raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in raw.uppercased() {
            if isASCIIAlphanumeric(character) {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - 部件

    static func fullCode(shelf: String, level: String, tail: String,
                         maxCorrections: Int = 1) -> Reading? {
        guard (1...shelfMax).contains(shelf.count), shelf.allSatisfy(isASCIIAlphanumeric),
              (1...levelMax).contains(level.count), level.allSatisfy(isDigit) else { return nil }
        guard let parsed = correctedTail(tail, maxCorrections: maxCorrections) else { return nil }
        return Reading(code: Code(shelf: shelf, level: level, tail: parsed.value),
                       corrections: parsed.corrections)
    }

    static func bareTail(_ token: String, maxCorrections: Int = 1) -> Reading? {
        guard let parsed = correctedTail(token, maxCorrections: maxCorrections) else { return nil }
        return Reading(code: Code(shelf: nil, level: nil, tail: parsed.value),
                       corrections: parsed.corrections)
    }

    /// 尾号：恰好 4 位；非数字位只在解释唯一时修正，且总共不超过预算。
    static func correctedTail(_ token: String, maxCorrections: Int = 1) -> (value: String, corrections: Int)? {
        let characters = Array(token)
        guard characters.count == tailLength else { return nil }
        var result = characters
        var corrections = 0
        for index in characters.indices {
            let character = characters[index]
            if isDigit(character) { continue }
            let options = (confusions[character] ?? []).filter { $0 != character && isDigit($0) }
            guard options.count == 1, corrections < maxCorrections else { return nil }
            result[index] = options[0]
            corrections += 1
        }
        return (String(result), corrections)
    }

    static func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }
    static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}

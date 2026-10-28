import CoreGraphics
import Testing

@testable import AimFind

struct TargetMatcherTests {

    private func hit(_ raw: String, confidence: Double = 0.9,
                     box: CGRect = CGRect(x: 0.3, y: 0.4, width: 0.3, height: 0.08)) -> TextHit {
        TextHit(raw: raw, confidence: confidence, box: box)
    }

    // MARK: - 目标解析

    @Test func parsesBothInputForms() {
        #expect(SearchTarget.parse("6760") == .tail("6760"))
        #expect(SearchTarget.parse("  6760 ") == .tail("6760"))
        #expect(SearchTarget.parse("38-1-6760") == .located(shelf: "38", level: "1", tail: "6760"))
        #expect(SearchTarget.parse("c-2-4456") == .located(shelf: "C", level: "2", tail: "4456"))
        #expect(SearchTarget.parse("676") == nil)
        #expect(SearchTarget.parse("1-4-67601") == nil)
    }

    // MARK: - 尾号搜索

    @Test func findsBareTailOnParcels() {
        let hits = TargetMatcher.locate([hit("6760"), hit("38-1-6760"), hit("2004")],
                                       targets: [.tail("6760")])
        #expect(hits.count == 2)
        #expect(hits.allSatisfy { $0.strength == .exact })
        #expect(hits.allSatisfy { $0.prefix == .notRequired })
    }

    @Test func biggerPrintWins() {
        // 同一帧里两处 6760：字大的（更近/主编号）排前面
        let near = hit("6760", box: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.16))
        let far = hit("6760", box: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.03))
        let hits = TargetMatcher.locate([far, near], targets: [.tail("6760")])
        #expect(hits.count == 2, "同尾号两处 = 两件包裹，都标出来")
        #expect(hits.first?.box.height == 0.16, "字大的排前面 = 更可能是要找的那件")
    }

    @Test func exactBeatsProbableEvenWhenSmaller() {
        let probable = hit("676O", box: CGRect(x: 0, y: 0, width: 0.5, height: 0.2))
        let exact = hit("6760", box: CGRect(x: 0, y: 0, width: 0.2, height: 0.02))
        let hits = TargetMatcher.locate([probable, exact], targets: [.tail("6760")])
        #expect(hits.first?.strength == .exact)
    }

    @Test func findsSeveralTagsAtOnce() {
        let targets: [SearchTarget] = [
            .located(shelf: "B2", level: "4", tail: "2073"),
            .located(shelf: "C5", level: "5", tail: "7225"),
        ]
        let hits = TargetMatcher.locate([hit("B2-4-2073"), hit("C5-5-7225"), hit("A1-2-9999")], targets: targets)
        #expect(hits.count == 2)
        #expect(Set(hits.map(\.target.id)) == Set(targets.map(\.id)))
    }

    @Test func trackingNumberEndingWithTailIsNotAHit() {
        // 真实场景最危险的误命中：运单号 YT8747063366760 末尾就是 6760
        let hits = TargetMatcher.locate([hit("YT8747063366760")], targets: [.tail("6760")])
        #expect(hits.isEmpty)
    }

    // MARK: - 完整库位码搜索

    @Test func wrongShelfOrLevelIsNeverMarked() {
        let hits = TargetMatcher.locate([hit("1-4-6760"), hit("38-2-6760")],
                                        targets: [.located(shelf: "38", level: "1", tail: "6760")])
        #expect(hits.isEmpty, "前缀对不上就不标：标错货架比不标更糟")
    }

    @Test func marksTailAndFlagsUnconfirmedPrefix() {
        let hits = TargetMatcher.locate([hit("6760")],
                                       targets: [.located(shelf: "38", level: "1", tail: "6760")])
        #expect(hits.first?.strength == .exact)
        #expect(hits.first?.prefix == .absent)
    }

    @Test func confirmedPrefixWhenBothAgree() {
        let hits = TargetMatcher.locate([hit("38-1-6760")],
                                       targets: [.located(shelf: "38", level: "1", tail: "6760")])
        #expect(hits.first?.prefix == .matched)
    }

    @Test func oneWrongDigitBecomesProbable() {
        let hits = TargetMatcher.locate([hit("38-1-676O")],
                                       targets: [.located(shelf: "38", level: "1", tail: "6760")])
        #expect(hits.first?.strength == .probable)
        #expect(hits.first?.display == "38-1-6760")
    }

    @Test func similarTailIsNotAHit() {
        // 6788 与 6760 差两位；即便只差一位，若不是混淆对也不能强行解释
        #expect(TargetMatcher.locate([hit("6788")], targets: [.tail("6760")]).isEmpty)
        #expect(TargetMatcher.locate([hit("6761")], targets: [.tail("6760")]).isEmpty)
    }

    // MARK: - 方位提示

    @Test func regionAndApproachFromBox() {
        let upperRight = CGRect(x: 0.8, y: 0.02, width: 0.15, height: 0.05)
        #expect(LocatedCode(target: .tail("6760"), strength: .exact, prefix: .notRequired,
                            code: CodeGrammar.Code(shelf: nil, level: nil, tail: "6760"),
                            confidence: 0.9, box: upperRight).region == .upperRight)

        let located = LocatedCode(target: .tail("6760"), strength: .exact, prefix: .notRequired,
                                  code: CodeGrammar.Code(shelf: nil, level: nil, tail: "6760"),
                                  confidence: 0.9, box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.12))
        #expect(located.approach == .close)
        #expect(LocatedCode(target: .tail("6760"), strength: .exact, prefix: .notRequired,
                            code: CodeGrammar.Code(shelf: nil, level: nil, tail: "6760"),
                            confidence: 0.9,
                            box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.01)).approach == .far)
    }
}

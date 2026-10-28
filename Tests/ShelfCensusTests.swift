import CoreGraphics
import Testing

@testable import AimFind

struct ShelfCensusTests {

    private func hit(_ raw: String) -> TextHit {
        TextHit(raw: raw, confidence: 0.9, box: CGRect(x: 0, y: 0, width: 0.1, height: 0.05))
    }

    @Test func countsEveryFullCodeNotJustTheTargets() {
        let codes = ShelfCensus.fullCodes(in: [
            hit("取件码为C5-5-7225"),
            hit("B2-4-2073"),
            hit("1-4-XXXX"),        // 占位符不算
            hit("YT8747063366760"), // 运单号不算
            hit("3.5 元"),
        ])
        #expect(Set(codes) == ["C5-5-7225", "B2-4-2073"])
    }

    @Test func staysQuietUntilSomethingIsActuallySeen() {
        var census = ShelfCensus()
        #expect(census.verdict(now: 100) == nil)
        census.register(["C5-5-7225"], at: 100)
        #expect(census.verdict(now: 100.5) == .sweeping(seen: 1))
    }

    @Test func declaresLevelFinishedOnlyWhenCalmAndRichEnough() {
        var census = ShelfCensus()
        let codes = ["C5-5-7225", "C5-2-9914", "B2-4-2073"]
        census.register(codes, at: 100)
        // 安静时间不够 → 还在扫
        #expect(census.verdict(now: 100 + ShelfCensus.settleInterval - 0.5) == .sweeping(seen: 3))
        // 安静够了且码数够 → 判定这层没有
        #expect(census.verdict(now: 100 + ShelfCensus.settleInterval) == .notHere(seen: 3))
    }

    @Test func twoOrFewerCodesNeverClaimTheLevelIsDone() {
        var census = ShelfCensus()
        census.register(["C5-5-7225", "C5-2-9914"], at: 100)
        // 安静够了，但只看到两件 → 不足以断言"这层扫完了"
        #expect(census.verdict(now: 100 + ShelfCensus.settleInterval) == .sweeping(seen: 2))
    }

    @Test func freshCodesOnTheNextShelfResetTheJudgement() {
        var census = ShelfCensus()
        census.register(["C5-5-7225", "C5-2-9914", "B2-4-2073"], at: 100)
        let settled = 100 + ShelfCensus.settleInterval
        #expect(census.verdict(now: settled) == .notHere(seen: 3))
        // 换一层：出现新码 → 结论收回，重新进入"正在扫"
        census.register(["A9-1-4444"], at: settled)
        #expect(census.verdict(now: settled + 0.5) == .sweeping(seen: 4))
    }

    @Test func staleCodesFallOutOfTheCount() {
        var census = ShelfCensus()
        census.register(["C5-5-7225", "C5-2-9914", "B2-4-2073"], at: 100)
        // 超过 TTL 还没被重新看到 → 不再计入，也不下结论
        #expect(census.verdict(now: 100 + ShelfCensus.ttl + 1) == nil)
    }
}

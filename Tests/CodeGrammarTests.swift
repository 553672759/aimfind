import Testing

@testable import AimFind

/// 语法规则全部用真实标签样本验证（图里的运单标签 + 货架条），不碰相机。
struct CodeGrammarTests {

    // MARK: - 真实形态

    @Test func parsesFullCodesFromRealLabels() {
        let readings = CodeGrammar.readings(in: "38-1-6760")
        #expect(readings.count == 1)
        #expect(readings.first?.code == CodeGrammar.Code(shelf: "38", level: "1", tail: "6760"))
        #expect(readings.first?.corrections == 0)

        #expect(CodeGrammar.readings(in: "C-2-4456").first?.code.display == "C-2-4456")
        #expect(CodeGrammar.readings(in: "C3-4-4483").first?.code.display == "C3-4-4483")
    }

    @Test func parsesBareTail() {
        let readings = CodeGrammar.readings(in: "6760")
        #expect(readings.map(\.code.display) == ["6760"])
        #expect(readings.first?.isBareTail == true)
    }

    @Test func picksTheCodeOutOfABusyLabelLine() {
        // 运单标签上常被读成一行：日期 + 运单号 + 库位码
        let readings = CodeGrammar.readings(in: "03/23 YT8747063366760 38-1-6760")
        #expect(readings.map(\.code.display) == ["38-1-6760"])
    }

    @Test func extractsCodesGluedToChineseInNotifications() {
        // 驿站通知原文（样本已脱敏：地址与店名为编造）
        let notice = "【示例驿站】您有包裹已到达文苑路店，取件码为C5-5-7225，地址:示例路1号小区2区-3号楼103室"
        #expect(CodeGrammar.readings(in: notice).map(\.code.display) == ["C5-5-7225"])
        // 地址里的「2区-3号楼103室」不能生出假码
        let pickup = "快件已在【示例区文苑路店】暂放，【取件地址：示例路1号小区2区-3号楼103室】，取件码 B2-4-2073"
        #expect(CodeGrammar.readings(in: pickup).map(\.code.display) == ["B2-4-2073"])
    }

    @Test func ignoresShelfBeamPlaceholder() {
        // 货架条上写的是 "1-4-XXXX"：XXXX 不该被当成任何码
        #expect(CodeGrammar.readings(in: "1号货架 1-4-XXXX").isEmpty)
        // 同一条如果印了真号，就该读出来
        #expect(CodeGrammar.readings(in: "1号货架 1-4-6760").first?.code.display == "1-4-6760")
    }

    // MARK: - 陷阱：绝不子串匹配

    @Test func neverMatchesInsideLongerTokens() {
        // YT8747063366760 结尾正好是 6760 —— 这是最危险的误命中来源
        #expect(CodeGrammar.readings(in: "YT8747063366760").isEmpty)
        #expect(CodeGrammar.readings(in: "YT8747063366760\n38-1-6760").map(\.code.display) == ["38-1-6760"])
    }

    @Test func rejectsNoiseOnLabels() {
        for noise in ["扫码必得5元", "别拆", "03/23", "5元", "200米", "1-4", "8747063366760", "http://a.b"] {
            #expect(CodeGrammar.readings(in: noise).isEmpty, "应该拒掉：\(noise)")
        }
    }

    // MARK: - 混淆修正：解释唯一才改

    @Test func correctsUnambiguousTailDigits() {
        #expect(CodeGrammar.readings(in: "676O").first?.code.tail == "6760")
        #expect(CodeGrammar.readings(in: "676O").first?.corrections == 1)
        #expect(CodeGrammar.readings(in: "B760").first?.code.tail == "8760")
        #expect(CodeGrammar.readings(in: "38-1-676S").first?.code.display == "38-1-6765")
    }

    @Test func refusesAmbiguousCorrections() {
        // T 既像 1 又像 7 → 二义，宁可不出
        #expect(CodeGrammar.readings(in: "T760").isEmpty)
        // 严格模式：任何修正都不接受
        #expect(CodeGrammar.readings(in: "676O", maxCorrections: 0).isEmpty)
        // 一位都不许多改时，两位都错的串读不出来
        #expect(CodeGrammar.readings(in: "6O6O", maxCorrections: 1).isEmpty)
        #expect(CodeGrammar.readings(in: "6O6O", maxCorrections: 2).first?.code.tail == "6060")
    }

    @Test func neverInventsShelfOrLevel() {
        // 前缀读歪了就按读歪的走（改错货架比读不出恶劣得多）
        let readings = CodeGrammar.readings(in: "3B-1-6760")
        #expect(readings.first?.code.shelf == "3B")
        // 噪声字符（星号）只当分隔符，不会被"修"成别的货架号
        #expect(CodeGrammar.readings(in: "3*-1-6760").first?.code.display == "3-1-6760")
    }

    @Test func tailLengthIsExact() {
        #expect(CodeGrammar.readings(in: "676").isEmpty)
        #expect(CodeGrammar.readings(in: "67601").isEmpty)
    }

    @Test func tokenizingKeepsTrackingNumbersWhole() {
        #expect(CodeGrammar.tokens(in: "38-1-6760") == ["38", "1", "6760"])
        #expect(CodeGrammar.tokens(in: "YT8747063366760") == ["YT8747063366760"])
        // 中文是分隔符：通知里「取件码为C5-5-7225」这种紧贴写法必须能切出码
        #expect(CodeGrammar.tokens(in: "1号货架 1-4-6760") == ["1", "1", "4", "6760"])
        #expect(CodeGrammar.tokens(in: "取件码为C5-5-7225，地址") == ["C5", "5", "7225"])
    }
}

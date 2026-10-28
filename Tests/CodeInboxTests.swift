import Testing

@testable import AimFind

/// 用例文本就是用户给的两张取件通知截图原文。
struct CodeInboxTests {

    private let lockerNotice = "【示例驿站】您有包裹已到达文苑路店，取件码为C5-5-7225，地址:示例路1号小区2区-3号楼103室"
    private let stationNotice = "快件已在【示例区文苑路店】暂放，【取件地址：示例路1号小区2区-3号楼103室】，请及时取件，取件码 B2-4-2073"

    @Test func pullsThePickupCodeOutOfNotificationText() {
        #expect(CodeInbox.extract(lines: [lockerNotice]).map(\.id) == ["C5-5-7225"])
        #expect(CodeInbox.extract(lines: [stationNotice]).map(\.id) == ["B2-4-2073"])
    }

    @Test func keepsEveryCodeFromSeveralScreenshotsInOrder() {
        let codes = CodeInbox.extract(lines: [
            "【示例驿站】…取件码为C5-5-7225…",
            "【示例驿站】…取件码为C5-2-9914…",
            "…取件码 B2-4-2073",
        ])
        #expect(codes.map(\.id) == ["C5-5-7225", "C5-2-9914", "B2-4-2073"])
    }

    @Test func dedupesRepeatedCodesAcrossImages() {
        #expect(CodeInbox.extract(lines: [lockerNotice, lockerNotice]).count == 1)
    }

    @Test func ignoresBareNumbersAndDates() {
        // 截图里到处是裸数字：日期、时间、门牌、金额，都不能变成标签
        let noise = [
            "星期六 12:44",
            "示例路1号小区2区-3号楼103室",
            "扫码必得5元",
            "2025-10-27 09:12 已入库",
            "1-4-XXXX",
        ]
        #expect(CodeInbox.extract(lines: noise).isEmpty)
    }

    @Test func refusesCorrectedReadsOnImport() {
        // 导入是离线动作：读得不完全干净就不要进标签列表（真机里读不清可以重拍）
        #expect(CodeInbox.extract(lines: ["取件码为C5-5-722O"]).isEmpty)
    }
}

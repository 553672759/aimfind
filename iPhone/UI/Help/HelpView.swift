// AimFind — 页内使用说明（首页与相机页共用一份，文案与 docs/USAGE.md 同源）。

import SwiftUI

struct HelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("三步上手") {
                    step("1", "从截图导入", "多选取件通知截图，App 读出「货架-层-尾号」变成标签；也可在输入框手输一个码后回车。")
                    step("2", "整理标签", "向左或向右滑一个标签即删除。最多 12 个，重启后还在。")
                    step("3", "打开相机", "所有标签一起带进取景画面，边扫边标。")
                }

                Section("画面上的东西是什么意思") {
                    legend("顶部 1/3", "已找到 / 总共要找的标签数")
                    legend("绿实线框", "精确命中这个取件码")
                    legend("淡绿填充", "这个已经确认找到（连续读到 3 帧）")
                    legend("黄虚线框 ≈", "疑似：差一个字符才对上，请自己核对")
                    legend("底部大字 + 右上·中距", "最近找到的码，以及它在画面里的方位与远近")
                    legend("白色圆圈", "合焦点：你点过的地方，或 App 对准还没找到的码")
                }

                Section("怎么扫得快") {
                    tip("慢慢横向平移，别站着不动", "镜头一直对着同一处，读到新码的机会就少")
                    tip("保持 0.5–1.5 米", "太近主摄合不了焦（最近约 10cm），太远那 4 位数字看不清")
                    tip("稍微侧一点避开反光膜", "比放大管用")
                    tip("扫到后停半秒", "要连续 3 帧读到才算找到，扫太快框会一闪就没")
                    tip("一次别放超过 3–4 个标签", "一屏找太多件会看不过来")
                }

                Section("底部提示分别在说什么") {
                    tip("对准货架慢慢扫", "一件包裹码都没读到：没对准、太远、或者糊了")
                    tip("已扫到 N 件…", "读到 N 个码，但没有你要的那个，继续扫")
                    tip("这层 N 件里没有你要的，换一层试试", "这片区域 2.5 秒没出新码 —— 提示你换层，不是报错")
                    tip("全部找到", "这批标签都确认了，镜头不再自动移动")
                }

                Section("它现在做不到什么") {
                    limit("只写裸 4 位数字的通知不会变成标签", "导入只收完整取件码，且要求识别干净：宁可漏一条，不放一个错码让你白找")
                    limit("同尾号不同层，会被忽略", "你搜 B2-4-2073，画面里的 B2-5-2073 不是你要的那件")
                    limit("不是条码 / 二维码扫描器", "印成条码的码，用手机自带相机扫更快")
                    limit("不联网，没有历史记录", "换手机标签不会同步；截图也不会离开这台设备")
                }

                Section("关于这个包") {
                    HStack {
                        Text("识别引擎")
                        Spacer()
                        Text(engineSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("签名类型")
                        Spacer()
                        Text(SigningStatus.current.kindLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("安装有效期")
                        Spacer()
                        Text(SigningStatus.current.expiryLabel)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if SigningStatus.current.isTimeLimited {
                        Text("测试签名到期后 App 会打不开，重新安装一次即可，不是数据丢了。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("使用说明")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 相机页只报状态，引擎全名放这儿（现场排查时看得到，平时不占界面）
    private var engineSummary: String {
        guard let reader = try? VisionTextReader() else { return "文字识别不可用" }
        return "\(reader.name) · \(DetectionConfig.maxFrameRate) fps 上限"
    }

    private func step(_ index: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.footnote.weight(.bold))
                .frame(width: 20, height: 20)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ mark: LocalizedStringKey, _ meaning: LocalizedStringKey) -> some View {
        HStack(alignment: .top) {
            Text(mark).font(.footnote.weight(.semibold)).frame(width: 116, alignment: .leading)
            Text(meaning).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func tip(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func limit(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "minus.circle").font(.subheadline.weight(.medium))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

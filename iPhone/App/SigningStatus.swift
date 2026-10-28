// AimFind — 读自己包里的描述文件，把"这个包能用到什么时候"如实显示给用户。
// 测试签名 7 天会过期、到期后 App 直接打不开，这是最容易让人以为"东西丢了"的时刻。

import Foundation

enum SigningStatus {

    struct Info {
        let expires: Date?
        let kind: Kind

        var isTimeLimited: Bool { expires != nil }

        var kindLabel: String {
            switch kind {
            case .development: return "开发签名（测试）"
            case .adHoc: return "Ad Hoc（限定设备）"
            case .enterprise: return "企业签名"
            case .appStore: return "App Store 版本"
            case .unknown: return "未知"
            }
        }

        var expiryLabel: String {
            guard let expires else { return "不限" }
            return Self.formatter.string(from: expires)
        }

        static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter
        }()
    }

    enum Kind {
        case development, adHoc, enterprise, appStore, unknown
    }

    static let current: Info = read()

    private static func read() -> Info {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let profile = xmlPlist(in: data), !profile.isEmpty else {
            return Info(expires: nil, kind: .unknown)
        }
        return Info(expires: profile["ExpirationDate"] as? Date, kind: kind(of: profile))
    }

    private static func kind(of profile: [String: Any]) -> Kind {
        let entitlements = profile["Entitlements"] as? [String: Any]
        if entitlements?["get-task-allow"] as? Bool == true { return .development }
        if profile["ProvisionsAllDevices"] as? Bool == true { return .enterprise }
        if profile["ProvisionedDevices"] is [Any] { return .adHoc }
        return .appStore
    }

    /// 描述文件是 CMS 包起来的 XML plist，取出其中的 plist 片段再解析。
    private static func xmlPlist(in data: Data) -> [String: Any]? {
        guard let head = data.range(of: Data("<?xml".utf8)),
              let tail = data.range(of: Data("</plist>".utf8), options: [], in: head.upperBound..<data.endIndex) else {
            return nil
        }
        let blob = data[head.lowerBound..<tail.upperBound]
        return try? PropertyListSerialization.propertyList(from: Data(blob), format: nil) as? [String: Any]
    }
}

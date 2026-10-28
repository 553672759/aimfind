# 构建指南（Mac 侧）

> 从 WristEcho 的 `docs/BUILD.md` 收敛而来：去掉了 watchOS / GRDB / App Group / 后台模式那整套，
> AimFind 只有一个 iOS target，正常一次就能编过。

## 1. 前置条件

| 项 | 要求 |
|---|---|
| macOS | 14+ |
| Xcode | 16+（本骨架在 Xcode 27 上验证过编译） |
| XcodeGen | `brew install xcodegen` —— 工程不提交 `.xcodeproj`，必须用 `project.yml` 生成 |
| Apple Developer 账号 | 真机跑相机需要；模拟器免签名但**模拟器没有摄像头** |

## 2. 生成并打开

```sh
cd aimfind
xcodegen generate
open AimFind.xcodeproj
```

无 SPM 依赖，打开即可编译。目标只有两个：`AimFind`（App）与 `AimFindTests`。

可选：放一个 YOLO 模型进 `Resources/Models/`（`YOLOv8n.mlpackage`）才有检测框；不放也能跑，
相机会显示「未内置检测模型」。导出命令与许可证说明见 `Resources/Models/README.md`。

签名团队写在 `project.yml` 的 `settings.base.DEVELOPMENT_TEAM`（开源仓库里默认留空）：
填你自己的 Team ID 后重新 `xcodegen generate`，或者在 Xcode 的 *Signing & Capabilities* 里选
（选完记得回填 yml，别只改工程）。Bundle ID `com.aimfind.app` 如已被他人占用，换成自己的前缀即可。

> `project.yml` 是工程事实源：不要在 Xcode 里改 target/资源后忘了回流。
> `Support/Info/AimFind-Info.plist` 会被 xcodegen 按 yml 的 `info.properties` 回写，权限文案改 yml。

## 3. 跑起来

- **真机（唯一有效路径）**：插上 iPhone → 选设备 → Run。首次点「打开相机」会弹系统权限窗，
  之后应看到实时取景 + 检测框 + 底部类别读数。帧率/延迟/框对齐只能在这里量（见 `docs/DETECTION.md` §7）。
- **模拟器**：能装能跑，但点按钮只会提示「相机不可用」（模拟器无摄像头），这不是 bug。
- **只想验证编译**（无模拟器 runtime 时可用）：

```sh
xcodebuild build-for-testing -project AimFind.xcodeproj -scheme AimFind \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

## 4. 测试

```sh
xcodebuild test -project AimFind.xcodeproj -scheme AimFind \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

测试都用 Swift Testing（`#expect`），全部不依赖摄像头：
`CameraGateTests`（能力 + 授权 → 结果）、`YoloPostprocessorTests`（喂假张量，覆盖
`[84,8400]` / `[25200,85]` / `[300,6]` 三种导出布局的解码、objectness 推断、同类 NMS、letterbox 反映射）、
`ViewportMapperTests`（aspect-fill 框对齐）。若报找不到设备，先 `xcrun simctl list devices available` 看可用模拟器名；
一台 iOS 模拟器 runtime 都没装时，去 Xcode › Settings › Components 下载。

**没有模拟器 runtime 也能跑纯逻辑测试**（`YoloPostprocessor` / `ViewportMapper` / `Detection`
只依赖 Foundation + CoreGraphics，不碰 UIKit/AVFoundation），临时包到 `/tmp` 用 SwiftPM 跑：

```sh
mkdir -p /tmp/aimfind-pure/Sources/AimFindPure /tmp/aimfind-pure/Tests/AimFindPureTests
cp iPhone/Detection/{Detection,YoloPostprocessor,ViewportMapper,COCOClassLabels}.swift /tmp/aimfind-pure/Sources/AimFindPure/
cp Tests/{YoloPostprocessorTests,ViewportMapperTests}.swift /tmp/aimfind-pure/Tests/AimFindPureTests/
sed -i '' 's/@testable import AimFind$/@testable import AimFindPure/' /tmp/aimfind-pure/Tests/AimFindPureTests/*.swift
cd /tmp/aimfind-pure && swift test
```

（`Package.swift` 用 tools 6.2，testTarget 要显式 `dependencies: ["AimFindPure"]`，
两边都设 `.swiftLanguageMode(.v5)` 与工程一致。相机/overlay 层不在其中，仍需模拟器或真机。）

## 5. 加下一个模块

按 WristEcho 的分层习惯放：界面进 `iPhone/UI/<Feature>/`，能力进 `iPhone/<Feature>/`，
需要在 iPhone/Watch 之间共享时再建 `Shared/Core/`。资源统一挂 `Resources/`（已在 `project.yml`
的 `buildPhase: resources` 里声明）。新文案同步补 `Resources/*.lproj/Localizable.strings`。

## 6. 现场调参对照表（真机试用时按症状改这里）

所有阈值都是命名常量，改完 `xcodebuild` 重装即可生效（不用重新 `xcodegen`，除非加了新文件）。

| 现象 | 改哪个 | 在哪 |
|---|---|---|
| 明明是那件却不标/标错 | `confidences`、混淆表 | `iPhone/Code/CodeGrammar.swift` |
| 远处读不到码 | 识别档 `prefersAccurate`、会话预设 | `iPhone/Code/VisionTextReader.swift`、`CameraPageModel.configureSession` |
| 标得太快/误标 | `stableHits`（连续几帧才算找到） | `iPhone/Camera/CameraPageModel.swift` |
| 画面抽动、焦点乱跳 | `AutoFocus.interval`、`jumpThreshold` | `iPhone/Code/AutoFocus.swift` |
| 「这层没有」乱说 | `enoughToJudge`、`settleInterval`、`ttl` | `iPhone/Code/ShelfCensus.swift` |
| 提示来得太慢 | 同上 `settleInterval`；帧率 `maxFrameRate` | `ShelfCensus.swift`、`DetectionConfig.swift` |
| 耗电/发热 | `maxFrameRate` 降到 6–8、预设回 720p | `DetectionConfig.swift`、`CameraPageModel` |

改完跑一遍纯逻辑回归（本文件 §4 的 SwiftPM 办法），阈值类改动都会被时序用例抓到。

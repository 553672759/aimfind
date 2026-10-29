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
填你自己的 Team ID 后重新 `xcodegen generate`，或者在 Xcode 的 *Signing & Capabilities* 里选。
Bundle ID `com.aimfind.app` 如已被他人占用，换成自己的前缀即可。

仓库里 `DEVELOPMENT_TEAM` 故意留空（不把个人团队 ID 公开）。**只想本机真机自测时，用命令行临时传，
别改文件**：

```sh
xcodebuild -project AimFind.xcodeproj -scheme AimFind \
  -destination 'id=<设备UDID>' -derivedDataPath /tmp/aimfind-dd \
  -allowProvisioningUpdates build DEVELOPMENT_TEAM=你的TeamID
```

两个坑我都踩过：
- 环境变量前缀 `DEVELOPMENT_TEAM=x xcodebuild …` **不生效** —— XcodeGen 把 `DEVELOPMENT_TEAM=""`
  写进了工程设置，工程值优先；必须把 `DEVELOPMENT_TEAM=…` 作为**构建设置覆盖**写在 `build` 之后。
- 忘了 `-derivedDataPath` 会编到默认 DerivedData，而 `devicectl install` 装的还是旧路径里的包 ——
  表现为"构建成功、安装成功、手机上是旧版本"。装之前 `stat` 一下产物的修改时间。

只想验证编译不需要签名：加 `CODE_SIGNING_ALLOWED=NO` 并把 destination 换成 `generic/platform=iOS`。

> `project.yml` 是工程事实源：不要在 Xcode 里改 target/资源后忘了回流。
> `Support/Info/AimFind-Info.plist` 会被 xcodegen 按 yml 的 `info.properties` 回写，权限文案改 yml。

## 3. 跑起来

- **真机（唯一有效路径）**：插上 iPhone → 选设备 → Run。首次点「打开相机」会弹系统权限窗，
  之后应看到实时取景 + 取件码框 + 顶部 `找到 k/N` 进度。命中率、帧率、框对齐只能在这里量。
- **模拟器**：能装能跑，但点按钮只会提示「相机不可用」（模拟器无摄像头），这不是 bug。
- **只想验证编译**（无模拟器 runtime 时可用）：

```sh
xcodebuild build-for-testing -project AimFind.xcodeproj -scheme AimFind \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

## 4. 测试

```sh
swift test          # 在仓库根目录，一条命令跑全部纯逻辑测试（47 条）
```

仓库自带 `Package.swift`，只打包不依赖 UIKit 的部分（`iPhone/Code/` 与授权判定），
所以**不需要 Xcode 工程、不需要模拟器、不需要真机**就能跑。覆盖语法/匹配/合焦/清点/
坐标映射这些真正容易写错的逻辑；相机与界面链路不在其中，仍需真机验证。

想在 iOS 模拟器里跑同一套：

```sh
xcodebuild test -project AimFind.xcodeproj -scheme AimFind -destination 'platform=iOS Simulator,name=iPhone 17'
```

（无模拟器 runtime 时去 Xcode › Settings › Components 下载；`xcrun simctl list devices available`
可看可用机型名。）

## 5. 加下一个模块

按 WristEcho 的分层习惯放：界面进 `iPhone/UI/<Feature>/`，能力进 `iPhone/<Feature>/`，
需要在 iPhone/Watch 之间共享时再建 `Shared/Core/`。资源统一挂 `Resources/`（已在 `project.yml`
的 `buildPhase: resources` 里声明）。新文案同步补 `Resources/*.lproj/Localizable.strings`。

## 6. 现场调参对照表（真机试用时按症状改这里）

所有阈值都是命名常量，改完 `xcodebuild` 重装即可生效（不用重新 `xcodegen`，除非加了新文件）。

| 现象 | 改哪个 | 在哪 |
|---|---|---|
| 明明是那件却不标/标错 | `confidences`、混淆表 | `iPhone/Code/CodeGrammar.swift` |
| 远处读不到码 | `minimumTextHeight`(未设，可加)、`prefersAccurate`、会话预设 | `iPhone/Code/VisionTextReader.swift`、`CameraPageModel.configureSession` |
| 标得太快/误标 | `stableHits`（连续几帧才算找到） | `iPhone/Camera/CameraPageModel.swift` |
| 画面抽动、焦点乱跳 | `AutoFocus.interval`、`jumpThreshold` | `iPhone/Code/AutoFocus.swift` |
| 「这层没有」乱说 | `enoughToJudge`、`settleInterval`、`ttl` | `iPhone/Code/ShelfCensus.swift` |
| 提示来得太慢 | 同上 `settleInterval`；帧率 `maxFrameRate` | `ShelfCensus.swift`、`iPhone/Code/ReadingConfig.swift` |
| 耗电/发热 | `maxFrameRate` 降到 6–8、预设回 720p | `iPhone/Code/ReadingConfig.swift`、`CameraPageModel` |

改完跑一遍纯逻辑回归（本文件 §4 的 SwiftPM 办法），阈值类改动都会被时序用例抓到。

# AimFind

**在驿站货架前，用相机找出你那几件快递。**

驿站给你的通知写着「取件码 B2-4-2073」，货架上几十上百件包裹每件都印着同样醒目的 4 位数字。
你站在那里要做的动作是：抬头、找数字、比对口否 —— 一次一件，高峰期一排架子看下来脖子都酸。
AimFind 把这件事变成：**把通知截图丢进 App，举起手机慢慢扫，系统把你找的那几件框出来。**

<!-- TODO 截图：在相机页停好画面后执行
     xcrun devicectl device capture screenshot --device <UDID> --destination docs/screenshot.png
     再把下面这行取消注释
     ![取景中找到一件](docs/screenshot.png)
-->

## 它能做什么

- **截图变标签**：选取件通知截图（可多选），App 读出「货架-层-尾号」的取件码，做成标签；也能手输一个
- **同时找好几件**：一次带 3–4 个标签进相机，扫到哪个标哪个，顶部显示 `找到 2/3`
- **标位 + 方位**：绿框圈出那一件，底部大字显示码，并告诉你在画面的哪个方位、大概多远（`右上 · 中距`）
- **自动合焦**：镜头对到识别出的那一点上，等效你手指点了一下 —— 远处小标签更看得清
- **没找到也给方向感**：区分「还没扫到」和「这层 5 件里没有你要的，换一层试试」，不让你原地反复扫
- **滑动删标签**、**相机页期间屏幕常亮**、**记住上次那批标签**

## 它不做什么（避免误会）

- 不是条码 / 二维码扫描器 —— 印成条码的码，手机自带相机更快
- 不联网、不上传截图、没有账号，也没有历史记录；换手机标签不会同步
- 读不清时**宁可不说**，不会猜一个给你（下面解释为什么这么设计）

全程只用 Apple 系统自带的文字识别：**零第三方依赖、零模型文件、包体 2.1MB。**

## 三步上手

1. 首页点「从截图导入」，选取件通知截图（或手输 `2073` / `B2-4-2073`）
2. 整理标签 —— 向左或向右滑一个标签即删除
3. 点「打开相机」，对着货架**慢慢横向平移**；停半秒等它确认

App 内右上角「?」就是完整使用说明，与 [docs/USAGE.md](docs/USAGE.md) 同源
（含怎么扫得快、画面上每个标记的含义、常见问题）。

---

> 源码仓库视角的内容在下面：怎么做到不误读、架构、目录、构建、许可证。
> 从 WristEcho 的工程框架（XcodeGen + SwiftUI + 无第三方依赖）收敛出单 iOS target。

## 怎么做到"不误读"

取件码是有语法的东西：`货架(1–2 位字母或数字)-层(1–2 位数字)-尾号(恰好 4 位数字)`。
把"识别对了"变成"匹配上语法"，准确率问题就变成了可验证的规则问题。三条保守规则，每条都有单测钉住：

1. **只做 token 边界匹配，绝不做子串匹配** —— 运单号 `YT8747063366760` 的结尾就是 `6760`，
   子串匹配等于让每个运单号都误命中，这是这个场景里最危险的错法；
2. **只在解释唯一时才修正混淆字符** —— `44S6 → 4456` 可以（S 在数字位只能是 5），
   数字位上的 `0` 可能是 O/D/Q，二义就直接判"没读到"；而且**从不猜测货架/层**：
   搜 `B2-4-2073` 时看到 `B2-5-2073` 会被忽略，标错层会让人拿错件；
3. **OCR 给了分隔符就尊重它的切分** —— `B2-4-20731`（超长）不会被"救"成 `B2-4-2073`。

还有两条针对真实截图文本的：中文一律当分隔符（通知里写的是「取件码**为C5-5-7225**」，
否则会被切成 `为C5` 而丢码）；截图导入侧**只收完整码、拒绝任何需修正的读法**
—— 标签列表里出现一个错码，会让人在货架前白找半天。

**状态表达**：绿实线 = 精确命中；已确认的再加一层淡绿填充、边框更粗；黄虚线 `≈` = 疑似，需人工核对；
同级命中按框高度排序（同一件越近字越大，大字号也更可能是主编号）。

## 架构

```
相册截图 ─┐
          ├─► VisionTextReader ──► 文本行 ──► CodeGrammar / CodeInbox ──► 标签
手输一码 ─┘   (VNRecognizeTextRequest)          取件码语法 + 混淆修正
                                                            │
相机帧 ──► AVCaptureSession ──► 帧闸（一帧没读完就丢，≤12fps）┤
                                                            ▼
                              TargetMatcher（多标签匹配，前缀不符不标）
                                                            ▼
                              连续 3 帧同一结果 → 确认：标位 + 合焦 + 触觉 + k/N
                              ShelfCensus（所有完整码计数）→ "还没扫到" vs "这层没有"
```

分层原则：**读取引擎不认识语义，语义层不碰相机**。所以 `iPhone/Code/` 里除了
`PhotoCodeImporter`，全是只依赖 Foundation/CoreGraphics 的纯函数 —— 43 条测试不需要相机、
不需要模拟器就能跑（见 `docs/BUILD.md §4`）。

## 目录结构

```
project.yml                     工程事实源（1 App + 1 测试 target；.xcodeproj 为生成物，不入库）
iPhone/
  App/AimFindApp.swift            @main 入口 → HomeView
  App/DebugLog.swift              Debug 构建的诊断输出（真机取证用）
  App/SigningStatus.swift         读描述文件：签名类型与安装有效期（如实显示，不写死）
  UI/Home/HomeView.swift          首页：导入截图/手输 → 标签墙 → 「打开相机」
  UI/Tags/TagChip.swift           标签（滑动删除）与相机页的进度状态
  UI/Help/HelpView.swift          页内使用说明
  UI/Detection/DetectionOverlay.swift  Canvas 描框：绿=精确，黄虚线=疑似，淡填充=已找到
  Camera/CameraPage.swift         取景页：预览 + 码框 + 进度 + 方位读数
  Camera/CameraPageModel.swift    会话 → 帧闸 → 识别 → 多标签稳定判定 → 合焦
  Camera/CameraAccess.swift       能力/授权判定（纯函数）
  Camera/CameraPreviewView.swift  AVCaptureVideoPreviewLayer 宿主 + 点击/自动合焦坐标换算
  Code/                           读码层（唯一在跑的引擎，零模型零依赖）
    CodeGrammar.swift             取件码语法 + ASCII token 边界 + 唯一解释才修正
    CodeInbox.swift               截图文本 → 标签：只收完整码、拒绝修正
    TargetMatcher.swift           多目标匹配 + 命中强度/前缀三态 + 字号排序
    ShelfCensus.swift             货架清点："没扫到" vs "这层没有"
    AutoFocus.swift               何时重新合焦（移动阈值 + 冷却）
    PositionHint.swift            九宫格方位 + 远近
    TextReader.swift / VisionTextReader.swift   读取引擎接口与实现（取景帧、静态图两条入口）
    ViewportMapper.swift / PixelBufferGeometry.swift / AsyncQueue.swift
                                  坐标映射 / 帧尺寸 / 把 Vision 的同步 perform 桥成 async
    ReadingConfig.swift           帧率上限
Resources/
  Assets/AimFind-iOS.xcassets     AppIcon（tools/make_icon.py 生成）+ AccentColor
  zh-Hans.lproj / en.lproj        Localizable.strings
Support/
  Info/AimFind-Info.plist         含 NSCameraUsageDescription
  Entitlements/AimFind.entitlements
Tests/                            47 条纯逻辑测试（Swift Testing，不依赖相机与模拟器）
Package.swift                   `swift test` 直接可用的测试目标
.github/workflows/tests.yml     CI：每次 push 自动跑 swift test
tools/make_icon.py                生成 AppIcon（纯标准库，改常量重跑）
docs/                             USAGE / BUILD / CODE_READING
```

## 技术栈

| 项 | 取值 |
|---|---|
| 工程生成 | XcodeGen（`project.yml` 是事实源，**不提交** `.xcodeproj`） |
| UI | SwiftUI，iOS 17.0 起 |
| Swift | 5.10 |
| Bundle ID | `com.aimfind.app` |
| 开发语言 | zh-Hans（英文只覆盖基础界面，帮助正文仍是中文） |
| 第三方依赖 | **无** |
| 测试 | Swift Testing（`Tests/`，47 条；`swift test` 一条命令，不需要 Xcode/模拟器） |

## 跑测试

```sh
swift test
```

一条命令跑完全部 47 条纯逻辑测试，不需要装 Xcode 工程、不需要模拟器或真机。
GitHub 上 push 后也会自动跑一遍（`.github/workflows/tests.yml`）。

## 构建

```sh
cd aimfind && xcodegen generate && open AimFind.xcodeproj
```

仓库里 `DEVELOPMENT_TEAM` 故意留空（不公开个人团队 ID），真机自测怎么临时传、
以及没有模拟器 runtime 怎么跑纯逻辑测试，都写在 [docs/BUILD.md](docs/BUILD.md)。
相机链路必须真机验证 —— 模拟器没有摄像头。

## 设计记录

- [docs/CODE_READING.md](docs/CODE_READING.md) —— 取码方案：L0–L5 分档、训练触发判据、
  四条备选路线的成本对比，以及"为什么最后不需要训练模型"。
  其中一条 YOLO 检测实现（CoreML 输出解码、letterbox 反映射、NMS，含 10 条单测）**已删除**，
  因为它要解决的问题（远处读不到码）还没被验证，而更便宜的手段一个都没试；
  代码留在 git 历史 `1ea5f92`，需要时按 §5 接回。
- [docs/USAGE.md](docs/USAGE.md) —— 使用说明（App 内「?」同源）。

## 许可证

MIT（见 [LICENSE](LICENSE)）。四条对使用者真正有用的说明：

1. **零第三方依赖** —— 没有 SPM 包、没有 CocoaPods，只调用 Apple 系统框架，
   所以不存在"仓库写着 MIT、但某个依赖带来传染性条款"的隐藏坑。
2. **你自己加模型时要看清楚** —— 如果接回 YOLO 并使用 **ultralytics** 的权重：
   v5/v8/v11 权重是 **AGPL-3.0**，把它提交进这个 MIT 仓库或塞进闭源 App 都与许可冲突。
   三条出路：换 **Apache-2.0** 的检测模型（YOLOX、NanoDet-Plus、PP-YOLOE）、
   整个项目改 AGPL-3.0、或让每个使用者自己导出模型本地放（仓库不分发）。
3. **素材来源干净** —— 图标由 `tools/make_icon.py` 生成，不是网络素材；
   测试与文档里的收件地址、驿站名是**编造样本**，只保留取件码的文法特征。
4. **开源许可 ≠ 苹果的分发许可** —— 装到别人手机（TestFlight / App Store）
   仍需你自己的 Apple Developer Program 账号；本仓库不含证书或描述文件。

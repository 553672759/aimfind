# AimFind

> 从 WristEcho 的工程框架复制出来的独立项目：**导入取件截图 → 认出取件码变成标签 → 打开相机，同时找好几件**。
> 场景是驿站/货架找件：通知里写「取件码 B2-4-2073」，标签上印着同样的码，你要在一堆包裹里认出那一件。
> 不做训练、不装模型：Vision 本地文本识别 + 一套针对真实标签的语法校验（误读优先被否决）。
> 目标检测（YOLO/Core ML）作为 L3 备选路线保留，有测试有文档，暂未接进相机页。
> **要用的话看 [docs/USAGE.md](docs/USAGE.md)**（App 内右上角「?」也是同一份）；方案见 [docs/CODE_READING.md](docs/CODE_READING.md)，
> 检测层设计见 [docs/DETECTION.md](docs/DETECTION.md)，构建与调参见 [docs/BUILD.md](docs/BUILD.md)。

## 技术栈（沿用 WristEcho 约定）

| 项 | 取值 |
|---|---|
| 工程生成 | XcodeGen（`project.yml` 是事实源，**不提交** `.xcodeproj`） |
| UI | SwiftUI，iOS 17.0 起 |
| Swift | 5.10 |
| Bundle ID | `com.aimfind.app` |
| 开发语言 | zh-Hans（附 en 翻译） |
| 第三方依赖 | 无 |
| 测试 | Swift Testing（`Tests/`） |

## 目录结构

```
project.yml                 工程规范（1 App + 1 测试 target）
iPhone/
  App/AimFindApp.swift          @main 入口 → HomeView
  UI/Home/HomeView.swift        唯一页面：导入截图/手输 → 标签墙 → 「打开相机」
  UI/Help/HelpView.swift        页内使用说明（首页与相机页右上角「?」）
  App/SigningStatus.swift       读描述文件：签名类型与安装有效期（如实显示，不写死）
  UI/Tags/TagChip.swift         标签（滑动删除）与相机页的进度状态
  UI/Detection/DetectionOverlay.swift  Canvas 描框：绿=精确，黄虚线=疑似，淡填充=已找到
  Camera/CameraAccess.swift     能力/授权判定（可单测的纯函数）
  Camera/CameraPage.swift       取景页：预览 + 码框 + 目标/方位读数
  Camera/CameraPageModel.swift  AVCaptureSession → 帧闸 → 识别 → 连续帧稳定判定
  Camera/CameraPreviewView.swift AVCaptureVideoPreviewLayer 宿主
  Code/                         读码层（当前接线的引擎）
    CodeGrammar.swift           取件码语法 + ASCII token 边界 + 唯一解释才修正（纯函数）
    CodeInbox.swift             截图文本 → 标签：只收完整码、拒绝修正（纯函数）
    ShelfCensus.swift           货架清点："没扫到" vs "这层没有"（纯函数）
    TargetMatcher.swift         多目标匹配 + 命中强度/前缀三态 + 字号排序（纯函数）
    PhotoCodeImporter.swift     图片 → 文本行 → CodeInbox
    VisionTextReader.swift      VNRecognizeTextRequest（取景帧与静态图两条入口）
    PositionHint.swift          九宫格方位 + 远近（纯函数）
    AutoFocus.swift             何时重新合焦（纯函数，时间由调用方传入）
    TextReader.swift            读取引擎接口（只回原文行 + 框）

  Detection/                    目标检测层（L3 备选，未接进相机页）
    Detector 协议 + VisionYoloDetector（Core ML + Vision）
    YoloPostprocessor（布局判定/解码/NMS/letterbox，纯函数）
    ViewportMapper（图像归一化 → 视口，aspect-fill cover）
    Detection.swift / COCOClassLabels.swift / DetectionConfig.swift
Resources/
  Assets/AimFind-iOS.xcassets  AppIcon + AccentColor
  Models/                      放 YOLOv8n.mlpackage（缺模型也能跑，见该目录 README）
  zh-Hans.lproj / en.lproj     Localizable.strings
Support/
  Info/AimFind-Info.plist      含 NSCameraUsageDescription
  Entitlements/AimFind.entitlements
Tests/
  CameraGateTests.swift        能力 + 授权 → 结果
  YoloPostprocessorTests.swift 三种 YOLO 导出布局的解码/NMS/letterbox
  ViewportMapperTests.swift    aspect-fill 框对齐
tools/make_icon.py        生成 AppIcon（纯标准库，改常量重跑：python3 tools/make_icon.py）
docs/USAGE.md               使用说明（给实际用它的人看）
docs/BUILD.md               从零构建指引
docs/DETECTION.md           检测层设计（分层/坐标契约/帧闸/降级/校准点）
docs/CODE_READING.md        取码方案（读 C3-4-4483 这类码：L0–L5 分档/校验/训练判据）
```

## 一次找件的完整链路

```
相册截图 ──VisionTextReader──► 文本行 ──CodeInbox──► 标签墙（滑动删除）
   └─ 或手输 B2-4-2073 ───────────────────────────────┘
                       ↓ 打开相机（整组标签一起带上）
CameraPage：AVCaptureSession 取帧
   → 帧闸（一帧没读完就丢，≤12fps）
   → VisionTextReader：VNRecognizeTextRequest 读出所有文本行（原文 + 置信度 + 左上原点归一化框）
   → CodeGrammar.readings：按 token 边界切，产出「完整码 / 裸尾号」解读
   → TargetMatcher.locate：只留目标尾号；前缀不符的直接不标
   → 新找到的一个：大字 + 「右上 · 中距」+ 触觉；全部找到显示「全部找到」
   → 一直没找到时给方向感：「已扫到 N 件…」／「这层 N 件里没有你要的，换一层试试」
   → 相机页期间屏幕常亮
   → 识别到哪就合焦到哪（与手指点同一条坐标路径，带 6% 移动阈值 + 0.7s 冷却）
```

**语法**（脱敏样本，见 `docs/CODE_READING.md`）：段1 货架 = 1–2 位字母或数字，段2 层 = 1–2 位数字，
段3 尾号 = **恰好 4 位数字**。定长尾号是把它和日期、价格、距离区分开的依据。

**三条"宁可不出，不出错"的规则**（每条都有单测钉住）：
1. 只做 token 边界匹配，**绝不做子串匹配** —— `YT8747063366760` 结尾就是 `6760`，子串匹配等于每个运单号都误命中；
2. 某一位只有在"该位字符集下解释唯一"时才修正 —— 数字位上的 `0` 可能是 O/D/Q，二义就放弃；
   且只修尾号，**从不猜测货架/层**（标错货架比不标更糟）；
3. OCR 给了分隔符就尊重它的切分 —— `C-2-44567` 不会被"救"成 `C-24-4567`。

**强度与远近**：绿实线 = 尾号精确；黄虚线 `≈` = 需一位混淆修正（提示人工核对）；
同级命中按**框高度**排序（同一件包裹越近字越大，且大字号更可能是主编号）；
同尾号出现两处 = 两件包裹，都标出来，锁定用最大的那个。

## 构建

```sh
cd aimfind && xcodegen generate && open AimFind.xcodeproj
```

详见 [docs/BUILD.md](docs/BUILD.md)。相机链路**必须真机**验证。

# Resources/Models — YOLO 模型放置处

工程默认找 **`YOLOv8n.mlpackage`**（名字在 `iPhone/Detection/DetectionConfig.swift` 的
`modelResourceName`）。没有模型时 App 照常运行，相机页会显示「未内置检测模型」，其它功能不受影响。

## 放进来

```bash
pip install ultralytics
yolo export model=yolov8n.pt format=coreml imgsz=640
mv yolov8n.mlpackage YOLOv8n.mlpackage
mv YOLOv8n.mlpackage Resources/Models/
xcodegen generate && xcodebuild ...   # 见 docs/BUILD.md
```

`.mlpackage` 目录名必须以资源名开头（`YOLOv8n.mlpackage`），Xcode 会把它编成 `YOLOv8n.mlmodelc`
放进 bundle；`VisionYoloDetector` 也接受原样拷贝的 `.mlpackage` / `.mlmodel`（运行时 `MLModel.compileModel` 兜底）。

## 三种输出布局都能解

`YoloPostprocessor` 按张量形状自动选择解码路线，不需要告诉它模型是哪一代：

| 导出 | 形状 | 走哪条 |
|---|---|---|
| YOLOv8 / v11 默认 | `[1, 84, 8400]` | `.anchorsFirst`（无 objectness） |
| YOLOv5 风格 / 转置导出 | `[1, 25200, 85]` | `.anchorsLast`（第 5 列是 objectness） |
| `nms=True` 端到端 | `[1, 300, 6]` | `.endToEnd`（x1,y1,x2,y2,score,class） |

类别数用类名表对齐（`attrs - 5 == 类数` 判定 objectness）；模型 metadata 里没有类名时回退到
`COCOClassLabels.coco80`。自训模型（自己的类别）请把类名导出到 metadata，或改 `COCOClassLabels`。

## 许可证（商用前必看）

- **ultralytics YOLOv8/v11**：AGPL-3.0。开源发布或接受 AGPL 义务即可；闭源商用需要 Ultralytics 商业授权。
- **Apache-2.0 替代**：YOLOX、PP-YOLOE、NanoDet-Plus 等，走 `onnx → coremltools` 转换，输出同样是上面三种布局之一。
- 转换示例：

```bash
pip install coremltools onnx
python3 -c "import coremltools as ct; ct.converters.onnx.convert(model='yolox_nano.onnx', minimum_deployment_target=ct.target.iOS17)"
```

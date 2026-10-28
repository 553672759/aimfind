// AimFind — 相机页：取景 + 命中框 + 标签进度 + 「要找的东西在哪」读数。由 HomeView 全屏呈现。

import SwiftUI
import UIKit

struct CameraPage: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: CameraPageModel
    @State private var focusMark: CGPoint?
    @State private var zoomBase: CGFloat = 1
    @State private var showHelp = false
    let onClose: () -> Void

    init(targets: [SearchTarget], onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: CameraPageModel(targets: targets))
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            CameraPreviewView(session: model.session,
                              imageAspect: model.imageAspect,
                              autoFocusCenter: model.autoFocusCenter) { layerPoint, devicePoint in
                model.focus(at: devicePoint)
                focusMark = layerPoint
                clearFocusMarkLater()
            }
            .ignoresSafeArea()
            .gesture(
                MagnificationGesture()
                    .onChanged { model.setZoom(zoomBase * $0) }
                    .onEnded { _ in zoomBase = model.zoomFactor }
            )

            DetectionOverlay(codes: model.hits, imageAspect: model.imageAspect, found: model.found)
                .ignoresSafeArea()

            if let mark = focusMark {
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 58, height: 58)
                    .position(mark)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 10) {
                header
                Spacer()
                tagStrip
                readout
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .task { model.start() }
        .onAppear {
            // 在货架前扫码时不能锁屏；离开页面就交还系统默认行为
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.stop()
        }
        // 切到后台/回桌面时必须停会话，否则相机指示灯会一直亮着
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .accessibilityLabel(Text("关闭相机"))
                    .font(.body.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .accessibilityLabel(Text("使用说明"))
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            (Text("找到") + Text(verbatim: " \(model.found.count)/\(model.targets.count)"))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            if model.zoomFactor > 1.05 {
                Text("变焦 \(String(format: "%.1f", model.zoomFactor))×")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Text(engineLabel)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 20)
        .foregroundStyle(.white)
    }

    /// 横向标签条：找到的变绿沉到后面，视线自然留在还没找到的那几个上。
    private var tagStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedTargets, id: \.id) { target in
                    TagChip(title: target.id, state: state(of: target), onDelete: nil)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder private var readout: some View {
        VStack(spacing: 10) {
            if model.allFound {
                Label("全部找到", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            } else if let found = model.lastFound {
                VStack(spacing: 4) {
                    Text(found.strength == .exact ? "已找到" : "疑似，请核对")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(found.strength == .exact ? Color.green : Color.yellow)
                    Text(found.display)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    positionLine(for: found)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if found.prefix == .absent {
                        Text("只读到尾号，货架/层请自己看一眼")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            } else if let sweep = model.sweep {
                sweepLine(sweep)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            } else if case .ready = model.engine, model.isStreaming {
                Text("对准货架慢慢扫")
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if case .failed(let reason) = model.engine {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
        .foregroundStyle(.white)
    }

    // MARK: - 计算

    private var sortedTargets: [SearchTarget] {
        model.targets.sorted { left, right in
            let (a, b) = (model.found.contains(left.id), model.found.contains(right.id))
            return a == b ? left.id < right.id : !a && b
        }
    }

    private func state(of target: SearchTarget) -> TagState {
        if model.found.contains(target.id) { return .found }
        if model.hits.contains(where: { $0.target.id == target.id && $0.strength == .probable }) { return .probable }
        return .pending
    }

    private func sweepLine(_ verdict: ShelfCensus.Verdict) -> Text {
        switch verdict {
        case .sweeping(let seen): return Text("已扫到 \(seen) 件…")
        case .notHere(let seen): return Text("这层 \(seen) 件里没有你要的，换一层试试")
        }
    }

    /// 引擎名（Vision Text · accurate）挪进「使用说明 › 关于这个包」——
    /// 主界面这块只说状态，调试要看的技术名在帮助页和日志里都有。
    private var engineLabel: String {
        switch model.engine {
        case .loading: return "识别准备中"
        case .ready: return "识别就绪"
        case .failed: return "识别不可用"
        }
    }

    private func positionLine(for code: LocatedCode) -> Text {
        let strength = code.strength == .exact ? Text("") : Text("疑似 · ")
        return strength + Text(code.region.label) + Text(" · ") + Text(code.approach.label)
    }

    private func clearFocusMarkLater() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            focusMark = nil
        }
    }
}

private extension ScreenRegion {
    var label: LocalizedStringKey {
        switch self {
        case .upperLeft: return "左上"
        case .upperCenter: return "上中"
        case .upperRight: return "右上"
        case .middleLeft: return "左中"
        case .middleCenter: return "正中"
        case .middleRight: return "右中"
        case .lowerLeft: return "左下"
        case .lowerCenter: return "下中"
        case .lowerRight: return "右下"
        }
    }
}

private extension Approach {
    var label: LocalizedStringKey {
        switch self {
        case .far: return "远，走近点"
        case .middle: return "中距"
        case .close: return "就在眼前"
        }
    }
}

// AimFind — 唯一页面：从截图导入取件码（也可手输）→ 标签墙管理 → 一个「打开相机」按钮。

import PhotosUI
import SwiftUI

struct HomeView: View {

    /// fullScreenCover(item:) 的载体：一次搜索带一组标签
    private struct SearchSession: Identifiable {
        let id = UUID()
        let targets: [SearchTarget]
    }

    private static let maxTags = 12

    @AppStorage(SearchTarget.storageKey) private var savedCodes = ""
    @State private var targets: [SearchTarget] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var manual = ""
    @State private var session: SearchSession?
    @State private var notice: Notice?
    @State private var showHelp = false

    enum Notice: Equatable {
        case noCamera
        case denied
        case badFormat
        case noCodeFound

        var title: Text {
            switch self {
            case .noCamera: return Text("相机不可用")
            case .denied: return Text("没有相机权限")
            case .badFormat: return Text("码格式不对")
            case .noCodeFound: return Text("没找到取件码")
            }
        }

        var message: Text {
            switch self {
            case .noCamera: return Text("这台设备没有可用的摄像头。")
            case .denied: return Text("请在「设置 › AimFind › 相机」中允许后重试。")
            case .badFormat: return Text("输入 4 位尾号（如 6760），或完整取件码（如 B2-4-2073）。")
            case .noCodeFound: return Text("截图里没认出「货架-层-尾号」这种完整取件码，换一张更清晰的试试。")
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                helpButton
            }

            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("AimFind")
                    .font(.largeTitle.weight(.semibold))
                Text("导入取件截图，一次找好几件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            controls

            tagArea

            Spacer(minLength: 16)

            Button {
                startSearch()
            } label: {
                Text(targets.isEmpty ? "先添加取件码" : "打开相机")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(targets.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear(perform: restoreSavedCodes)
        .fullScreenCover(item: $session) { search in
            CameraPage(targets: search.targets) { session = nil }
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importFromPhotos(items) }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .alert(notice?.title ?? Text(""), isPresented: noticePresented) {
            Button("好", role: .cancel) {}
        } message: {
            if let notice { notice.message } else { Text("") }
        }
    }

    // MARK: - 子视图

    private var helpButton: some View {
        Button {
            showHelp = true
        } label: {
            Image(systemName: "questionmark")
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.quaternary.opacity(0.6), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("使用说明"))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickedItems, maxSelectionCount: 9, matching: .images) {
                if importing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                } else {
                    Label("从截图导入", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
            }
            .buttonStyle(.bordered)

            TextField("2073 或 B2-4-2073", text: $manual)
                .accessibilityLabel(Text("手输一个取件码"))
                .font(.system(.subheadline, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .onSubmit(addManualCode)
                .frame(width: 104)
                .padding(.vertical, 11)
                .padding(.horizontal, 10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var tagArea: some View {
        if targets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("还没有标签：选几张取件通知截图，或者手输一个码")
                Text("标签做好后点「打开相机」，扫到就标出来；滑一下标签即可删除")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(targets.count) 个标签 · 滑动删除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TagWall(states: Dictionary(uniqueKeysWithValues: targets.map { ($0.id, TagState.plain) }),
                        onDelete: remove)
            }
        }
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    // MARK: - 动作

    private func importFromPhotos(_ items: [PhotosPickerItem]) async {
        importing = true
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
        }
        let found = await PhotoCodeImporter.codes(from: datas)
        importing = false
        pickedItems = []
        if found.isEmpty {
            notice = .noCodeFound
        } else {
            add(found)
        }
    }

    private func addManualCode() {
        guard let target = SearchTarget.parse(manual) else {
            if !manual.isEmpty { notice = .badFormat }
            return
        }
        manual = ""
        add([target])
    }

    private func add(_ incoming: [SearchTarget]) {
        for target in incoming where targets.count < Self.maxTags {
            guard !targets.contains(where: { $0.id == target.id }) else { continue }
            targets.append(target)
        }
        persist()
    }

    private func remove(_ id: String) {
        targets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        savedCodes = targets.map(\.display).joined(separator: " ")
    }

    private func restoreSavedCodes() {
        guard targets.isEmpty, !savedCodes.isEmpty else { return }
        targets = savedCodes.split(separator: " ").compactMap { SearchTarget.parse(String($0)) }
    }

    private func startSearch() {
        guard !targets.isEmpty else { return }
        Task { @MainActor in
            switch await CameraLauncher.prepare() {
            case .ready:
                session = SearchSession(targets: targets)
            case .noCamera:
                notice = .noCamera
            case .denied:
                notice = .denied
            }
        }
    }
}

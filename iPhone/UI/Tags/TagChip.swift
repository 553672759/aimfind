// AimFind — 标签：横滑即可删除（首页），相机页复用同一枚 chip 显示查找状态。

import SwiftUI

enum TagState {
    case plain
    case pending
    case probable
    case found

    var tint: Color {
        switch self {
        case .plain, .pending: return .primary
        case .probable: return .yellow
        case .found: return .green
        }
    }
}

struct TagChip: View {
    let title: String
    var state: TagState = .plain
    var onDelete: (() -> Void)?

    @State private var drag: CGFloat = 0

    var body: some View {
        Text(marker + title)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(state.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(chipBackground)
            .overlay(Capsule().strokeBorder(state == .found ? Color.green.opacity(0.6) : .clear, lineWidth: 1.5))
            .offset(x: drag)
            .opacity(onDelete == nil ? 1 : max(0.15, 1 - abs(drag) / 120))
            .gesture(deleteGesture())
    }

    /// 状态不只靠颜色（色盲与反光下分不清），再叠一个符号
    private var marker: String {
        switch state {
        case .found: return "✓ "
        case .probable: return "≈ "
        case .plain, .pending: return ""
        }
    }

    private var chipBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.quaternary.opacity(state == .found ? 0.9 : 0.55))
    }

    /// 没给 onDelete 的场合（相机页只读展示）滑动只是弹回去，不会误删标签。
    private func deleteGesture() -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation.width }
            .onEnded { _ in
                if onDelete != nil, abs(drag) > 56 {
                    onDelete?()
                } else {
                    withAnimation(.spring(response: 0.25)) { drag = 0 }
                }
            }
    }
}

/// 自适应换行的标签墙。首页用它管理待找的码，相机页用它显示进度。
struct TagWall: View {
    let states: [String: TagState]
    var onDelete: ((String) -> Void)?

    var body: some View {
        // 字典无序，排序保证：找到的沉底，待找的排在视线前面
        let ids = states.keys.sorted {
            rank(states[$0] ?? .plain) == rank(states[$1] ?? .plain) ? $0 < $1
                                                                     : rank(states[$0] ?? .plain) < rank(states[$1] ?? .plain)
        }
        FlowLayout(horizontal: 8, vertical: 8) {
            ForEach(ids, id: \.self) { id in
                TagChip(title: id, state: states[id] ?? .plain) {
                    onDelete?(id)
                }
            }
        }
    }

    /// 找到的沉底、待找的排在前面，视线自然落在还没找到的东西上。
    private func rank(_ state: TagState) -> Int {
        switch state {
        case .pending, .plain: return 0
        case .probable: return 1
        case .found: return 2
        }
    }
}

/// 左对齐流式排布：按每个标签的实际宽度紧凑换行。
/// 用 Grid/LazyVGrid 会按最长者定列宽，短标签右边就留一片空洞。
struct FlowLayout: Layout {
    var horizontal: CGFloat = 8
    var vertical: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + vertical
                rowHeight = 0
            }
            x += size.width + horizontal
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? max(x - horizontal, 0) : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x - bounds.minX + size.width > bounds.width {
                x = bounds.minX
                y += rowHeight + vertical
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + horizontal
            rowHeight = max(rowHeight, size.height)
        }
    }
}

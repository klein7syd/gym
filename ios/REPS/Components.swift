import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 长按连加按钮

/// 点一下执行一次；按住 0.45 秒后开始连续触发，越按越快。
final class RepeatController: ObservableObject {
    var delay: Timer?
    var repeating: Timer?
    @Published var pressing = false

    func begin(_ action: @escaping () -> Void) {
        guard delay == nil && repeating == nil else { return }
        pressing = true
        action()
        delay = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.repeating = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                action()
            }
        }
    }

    func end() {
        pressing = false
        delay?.invalidate(); delay = nil
        repeating?.invalidate(); repeating = nil
    }
}

struct RepeatButton: View {
    let systemImage: String
    var tint: Color = .primary
    let action: () -> Void

    @StateObject private var controller = RepeatController()

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 46, height: 46)
            .background(Color(UIColor.tertiarySystemFill))
            .clipShape(Circle())
            .scaleEffect(controller.pressing ? 0.92 : 1)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in controller.begin(action) }
                    .onEnded { _ in controller.end() }
            )
    }
}

// MARK: - 步进输入（重量 / 次数）

struct StepperField: View {
    let label: String
    let unit: String
    let value: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                RepeatButton(systemImage: "minus", action: onMinus)
                Spacer()
                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                RepeatButton(systemImage: "plus", action: onPlus)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

// MARK: - 折线图（自绘，不依赖 iOS 16 的 Charts）

struct Sparkline: View {
    let values: [Double]
    var lineColor: Color = .accentColor
    var height: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count >= 2 {
                ZStack {
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let last = pts.last {
                        Circle()
                            .fill(lineColor)
                            .frame(width: 7, height: 7)
                            .position(last)
                    }
                }
            } else {
                Text("数据还不够，再练一次就有趋势")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(height: height)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2, size.width > 0 else { return [] }
        let mn = values.min() ?? 0
        let mx = values.max() ?? 1
        let range = (mx - mn) == 0 ? 1 : (mx - mn)
        let padX: CGFloat = 6
        let padY: CGFloat = 8
        return values.enumerated().map { i, v in
            let x = padX + CGFloat(i) / CGFloat(values.count - 1) * (size.width - padX * 2)
            let y = size.height - padY - CGFloat((v - mn) / range) * (size.height - padY * 2)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - 环形休息进度

struct RestRing: View {
    let progress: Double
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(UIColor.tertiarySystemFill), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            VStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("休息中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 190, height: 190)
    }
}

// MARK: - 文件选择器

struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var allowsMultiple: Bool = false
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        vc.allowsMultipleSelection = allowsMultiple
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - 系统分享

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 小组件

struct SectionCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    var unit: String? = nil
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                if let unit = unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let note = note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

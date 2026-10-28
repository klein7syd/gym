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
        .glassInner(cornerRadius: 22)
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
    /// 环内第二行小字：休息时「休息中」，训练中「本组用时」
    var caption: String = "休息中"
    /// 进度弧颜色：训练中用 WorkStyle.ring（蓝），组间歇用 RestStyle.ring（绿）
    var color: Color = RestStyle.ring

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(UIColor.tertiarySystemFill), lineWidth: 12)
            // 进度弧颜色由调用方按阶段决定：working 蓝 / resting 绿
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            VStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 190, height: 190)
    }
}

// MARK: - 迷你休息环（播放页底部用，与训练页同一个 RestTimer）

struct MiniRestRing: View {
    let progress: Double
    let text: String
    var size: CGFloat = 48
    /// 同上：working 蓝 / resting 绿
    var color: Color = RestStyle.ring

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(UIColor.tertiarySystemFill), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            Text(text)
                .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
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
                    .font(.system(size: 15, weight: .semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glass()
    }
}

/// 玻璃卡片里的一行「标题 — 数值」
struct GlassRow: View {
    let title: String
    var subtitle: String? = nil
    let value: String
    var unit: String? = nil
    var note: String? = nil
    var noteColor: Color = .accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                if let s = subtitle {
                    Text(s)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if let note = note {
                    Text(note)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(noteColor)
                        .padding(.leading, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// 卡片内分隔线（比系统 Divider 淡）
struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.8)
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

// MARK: - 多指标双轴折线图

/// 一张图叠多条曲线，每条曲线用各自的 Y 轴刻度（量纲不同也能一起看）。
/// X 轴统一为「健身第几天」，所以体重、体脂、去脂体重、FFMI 可以同屏对比。
struct MetricChartView: View {
    let data: [Store.BodyMetricKey: [Store.ChartPoint]]

    private let leftPad: CGFloat = 46
    private let rightPad: CGFloat = 46
    private let topPad: CGFloat = 14
    private let bottomPad: CGFloat = 30

    private var activeKeys: [Store.BodyMetricKey] {
        Store.BodyMetricKey.allCases.filter { !(data[$0]?.isEmpty ?? true) }
    }

    private var allPoints: [Store.ChartPoint] {
        activeKeys.flatMap { data[$0] ?? [] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allPoints.isEmpty {
                placeholder
            } else {
                chart
                legend
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("还没有身体数据")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("在「我的」里填体重和体脂，每次记录都会变成一个点")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private var chart: some View {
        // 先把所有依赖算成局部常量，避免 Canvas 的 escaping 闭包捕获 self
        let keys = activeKeys
        let points = allPoints
        let seriesData = data
        var rangeMap: [Store.BodyMetricKey: (low: Double, high: Double)] = [:]
        for k in keys {
            if let r = yRange(for: k) { rangeMap[k] = r }
        }
        let days = points.map { $0.day }
        let minDay = days.min() ?? 1
        let maxDay = days.max() ?? 2
        let daySpan = max(1, maxDay - minDay)
        let padL = leftPad
        let padR = rightPad
        let padT = topPad
        let padB = bottomPad
        let ranges = rangeMap

        return Canvas { context, size in
            let plot = CGRect(x: padL, y: padT,
                              width: max(1, size.width - padL - padR),
                              height: max(1, size.height - padT - padB))
            guard !keys.isEmpty else { return }

            let gridCount = 4
            for i in 0...gridCount {
                let ratio = CGFloat(i) / CGFloat(gridCount)
                let y = plot.maxY - ratio * plot.height

                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y))
                line.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(line,
                               with: .color(Color.primary.opacity(i == 0 ? 0.22 : 0.08)),
                               style: StrokeStyle(lineWidth: i == 0 ? 1.2 : 0.8,
                                                  dash: i == 0 ? [] : [3, 4]))

                // 左轴：第一条曲线
                if let key = keys.first, let range = ranges[key] {
                    let v = range.low + (range.high - range.low) * Double(ratio)
                    let label = Text(MetricChartView.formatAxis(v))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(key.color.opacity(0.85))
                    context.draw(label, at: CGPoint(x: plot.minX - 8, y: y), anchor: .trailing)
                }

                // 右轴：第二条曲线
                if keys.count > 1, let key = keys.dropFirst().first, let range = ranges[key] {
                    let v = range.low + (range.high - range.low) * Double(ratio)
                    let label = Text(MetricChartView.formatAxis(v))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(key.color.opacity(0.85))
                    context.draw(label, at: CGPoint(x: plot.maxX + 8, y: y), anchor: .leading)
                }
            }

            // 曲线
            for (index, key) in keys.enumerated() {
                guard let pts = seriesData[key], !pts.isEmpty, let range = ranges[key] else { continue }
                let mapped = pts.map { p -> CGPoint in
                    let x = plot.minX + CGFloat(Double(p.day - minDay) / Double(daySpan)) * plot.width
                    let y = plot.maxY - CGFloat((p.value - range.low) / max(0.0001, range.high - range.low)) * plot.height
                    return CGPoint(x: x, y: y)
                }

                if mapped.count >= 2 {
                    var path = Path()
                    path.move(to: mapped[0])
                    for p in mapped.dropFirst() { path.addLine(to: p) }

                    if index == 0 {
                        var area = path
                        area.addLine(to: CGPoint(x: mapped[mapped.count - 1].x, y: plot.maxY))
                        area.addLine(to: CGPoint(x: mapped[0].x, y: plot.maxY))
                        area.closeSubpath()
                        context.fill(area, with: .color(key.color.opacity(0.12)))
                    }

                    context.stroke(path,
                                   with: .color(key.color),
                                   style: StrokeStyle(lineWidth: index == 0 ? 2.4 : 1.8,
                                                      lineCap: .round, lineJoin: .round))
                }

                let showAll = mapped.count <= 12
                for (i, p) in mapped.enumerated() {
                    let isEdge = i == 0 || i == mapped.count - 1
                    guard showAll || isEdge else { continue }
                    let r: CGFloat = isEdge ? 3 : 2
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(key.color))
                    context.stroke(dot, with: .color(Color(UIColor.systemBackground)), lineWidth: 1.2)
                }
            }

            let left = Text("第 \(minDay) 天")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            context.draw(left, at: CGPoint(x: plot.minX, y: plot.maxY + 16), anchor: .leading)

            if maxDay != minDay {
                let right = Text("第 \(maxDay) 天")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                context.draw(right, at: CGPoint(x: plot.maxX, y: plot.maxY + 16), anchor: .trailing)
            }
        }
        .frame(height: 210)
    }

    static func formatAxis(_ v: Double) -> String {
        if abs(v) >= 100 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(activeKeys) { key in
                HStack(spacing: 5) {
                    Circle().fill(key.color).frame(width: 7, height: 7)
                    Text(key.title + (key.unit.isEmpty ? "" : " (\(key.unit))"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - 计算

    private func yRange(for key: Store.BodyMetricKey) -> (low: Double, high: Double)? {
        let values = (data[key] ?? []).map { $0.value }
        guard let mn = values.min(), let mx = values.max() else { return nil }
        if mn == mx {
            let pad = max(0.5, abs(mn) * 0.05)
            return (mn - pad, mx + pad)
        }
        let pad = (mx - mn) * 0.12
        return (mn - pad, mx + pad)
    }

    private func formatAxis(_ v: Double, key: Store.BodyMetricKey) -> String {
        MetricChartView.formatAxis(v)
    }
}


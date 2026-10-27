import SwiftUI
import UIKit

// MARK: - 液态玻璃设计系统
//
// 目标是 iOS 新版 Liquid Glass 的观感：半透明材质 + 背景色渗透 + 镜面高光描边 +
// 浮动柔和阴影 + 连续大圆角。用 Material 叠加自定义渐变描边实现，不依赖特定系统版本，
// 这样既能保持观感，又能在较低系统上正常安装运行。

enum GlassRadius {
    static let card: CGFloat = 26
    static let control: CGFloat = 18
    static let pill: CGFloat = 30
}

struct GlassBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = GlassRadius.card
    var tint: Double = 0
    var shadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // 让背后色彩渗进玻璃，形成冷暖过渡
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(scheme == .dark ? 0.10 : 0.34),
                                    Color.white.opacity(scheme == .dark ? 0.02 : 0.10),
                                    Color.black.opacity(scheme == .dark ? 0.10 : 0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if tint > 0 {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(tint))
                    }
                }
            }
            .overlay {
                // 镜面高光：左上亮、右下回光，模拟玻璃边缘折射
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(scheme == .dark ? 0.42 : 0.90),
                                Color.white.opacity(scheme == .dark ? 0.06 : 0.22),
                                Color.white.opacity(scheme == .dark ? 0.18 : 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(shadow ? (scheme == .dark ? 0.45 : 0.10) : 0),
                    radius: shadow ? 22 : 0,
                    x: 0,
                    y: shadow ? 10 : 0)
    }
}

extension View {
    /// 液态玻璃卡片
    func glass(cornerRadius: CGFloat = GlassRadius.card, tint: Double = 0, shadow: Bool = true) -> some View {
        modifier(GlassBackgroundModifier(cornerRadius: cornerRadius, tint: tint, shadow: shadow))
    }

    /// 内层玻璃（嵌套在卡片里的次级容器，不投影）
    func glassInner(cornerRadius: CGFloat = GlassRadius.control) -> some View {
        modifier(GlassBackgroundModifier(cornerRadius: cornerRadius, tint: 0, shadow: false))
    }

    /// 页面级点击收起键盘
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
        )
    }
}

// MARK: - 背景

/// 液态玻璃需要有「内容」在背后才通透，所以页面底色是柔和色块而不是纯灰。
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)

            // 三团柔光，制造色彩渗透
            Circle()
                .fill(Color(red: 0.36, green: 0.62, blue: 1.0).opacity(scheme == .dark ? 0.30 : 0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -150, y: -300)

            Circle()
                .fill(Color(red: 0.45, green: 0.95, blue: 0.72).opacity(scheme == .dark ? 0.22 : 0.18))
                .frame(width: 400, height: 400)
                .blur(radius: 120)
                .offset(x: 180, y: -120)

            Circle()
                .fill(Color(red: 0.72, green: 0.52, blue: 1.0).opacity(scheme == .dark ? 0.20 : 0.14))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: -60, y: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 悬浮液态玻璃底部栏

struct LiquidTabItem {
    let title: String
    let icon: String
    let activeIcon: String
}

struct LiquidTabBar: View {
    @Binding var selection: Int
    let items: [LiquidTabItem]

    @Namespace private var pillSpace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                button(index: index, item: item)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .glass(cornerRadius: GlassRadius.pill)
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    private func button(index: Int, item: LiquidTabItem) -> some View {
        let active = selection == index
        return Button {
            if selection != index {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                    selection = index
                }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? item.activeIcon : item.icon)
                    .font(.system(size: 18, weight: active ? .semibold : .regular))
                    .frame(height: 21)
                    .symbolRenderingMode(.hierarchical)
                Text(item.title)
                    .font(.system(size: 10, weight: active ? .semibold : .medium))
            }
            .foregroundColor(active ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(scheme == .dark ? 0.26 : 0.20),
                                    Color.accentColor.opacity(scheme == .dark ? 0.12 : 0.09)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.22 : 0.55), lineWidth: 0.7)
                        )
                        .matchedGeometryEffect(id: "tabpill", in: pillSpace)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// 按下去轻微缩小，抬起回弹
struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 玻璃按钮

struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(prominent ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.75)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                        )
                        .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
                } else {
                    RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                        )
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 键盘工具栏

struct KeyboardDoneBar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
            .fontWeight(.semibold)
        }
    }
}

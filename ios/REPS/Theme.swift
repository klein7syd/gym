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

                    // 纯色薄涂层：不再用渐变，避免页面出现脏色过渡
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.22))

                    if tint > 0 {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(tint))
                    }
                }
            }
            .overlay {
                // 单色细描边：玻璃边缘的实线，不做明暗渐变
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.55),
                                  lineWidth: 1)
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

/// 纯色底：不使用任何渐变与彩色光斑，避免整页泛蓝泛紫。
struct AppBackground: View {
    var body: some View {
        Color(UIColor.systemGroupedBackground)
            .ignoresSafeArea()
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
                        .fill(tint)
                        .overlay(
                            RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                        )
                        .shadow(color: tint.opacity(0.28), radius: 10, y: 5)
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

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

// MARK: - 组间歇配色
//
// 组间歇用绿色，和「训练」本身（accentColor 蓝）区分开：
// 蓝 = 我在练，绿 = 我在歇。只用于休息环的进度弧，
// 不动任何尺寸、线宽与动画参数，也不改训练页的蓝色强调色。

enum RestStyle {
    static let ring = Color.green
}

// MARK: - 训练配色
//
// 训练中（working）一律用蓝色强调色，组间歇（resting）一律用 RestStyle.ring 绿。
// 两阶段状态机：working --完成--> 记录一组 + resting --倒计时归零 / 跳过--> working …
// 「完成」只在 working 出现，「跳过休息」只在 resting 出现。

enum WorkStyle {
    static let ring = Color.accentColor
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

// MARK: - 卡片圆角裁剪（只在需要时才裁）

/// 圆角裁剪：**结构恒定，只有数值在变**。
///
/// 为什么不能直接用 `.clipShape`：
/// SwiftUI 里凡是不 ignore 安全区的容器（TabView、NavigationStack 底下的页面、
/// GeometryReader 也是这样）都是**按安全区布局**的。里面再放一个 `.ignoresSafeArea()` 的背景，
/// 背景是能画到状态栏和底部横条上的；可一旦在这条链路上套
/// `.clipShape(RoundedRectangle(cornerRadius: 0))`，裁剪边就是**安全区矩形**，
/// 连圆角为 0 都会硬切一刀，把铺出去的那部分削平 —— 露出来就是底下那层，
/// 表现为「一进 App 上下两条大黑边」「播放页上下两条大黑边」（4.6 → 4.8 的老 Bug）。
///
/// 为什么用 `mask` 而不是 `clipShape`：
/// mask 里的形状带了 `.ignoresSafeArea()`，圆角为 0 时它就是一块**覆盖整屏（含状态栏与
/// 底部横条）的矩形**，不沿安全区矩形切边，所以静止状态不可能切出黑边；
/// 需要圆角时把半径变大，遮罩自己变成圆角矩形，一切都还在整屏范围内。
///
/// 为什么不能写成 `if active { … } else { … }`：
/// 那是 `_ConditionalContent`，两个分支是不同的结构身份。`active` 一翻转，
/// SwiftUI 会把 `content` 整个销毁重建 —— 对根 TabView 来说就是：选中的 tab 回到第一页、
/// 各页 ScrollView 位置归零、NavigationStack 路径清空，而且过渡退化成淡入淡出而不是连续插值。
/// 现在 `body` 永远返回同一种结构（mask 一层），`active` 只影响 `effectiveRadius` 的数值，
/// 结构身份不变，状态不丢，圆角也能被外层 `.animation(…, value: player.isOpen)` 连续驱动。
struct CardClip: ViewModifier {
    /// false 时圆角按 0 处理（遮罩=整屏矩形，等于不裁）；true 时按 `radius` 裁圆角
    var active: Bool
    var radius: CGFloat

    private var effectiveRadius: CGFloat {
        (active && radius > 0.01) ? radius : 0
    }

    func body(content: Content) -> some View {
        content.mask {
            RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                .ignoresSafeArea()
        }
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

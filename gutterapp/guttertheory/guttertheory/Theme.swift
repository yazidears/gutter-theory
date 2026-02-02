import SwiftUI

enum GTTheme {
    static let void = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let deep = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let graphite = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let steel = Color(red: 0.60, green: 0.64, blue: 0.72)
    static let line = Color.white.opacity(0.10)
    static let accent = Color(red: 0.26, green: 0.96, blue: 0.98)
    static let accentSoft = Color(red: 0.42, green: 1.00, blue: 0.80)
    static let warning = Color(red: 1.00, green: 0.64, blue: 0.24)

    static let midnight = deep
    static let asphalt = graphite
    static let neonGreen = accentSoft
    static let neonCyan = accent
    static let neonPink = Color(red: 0.84, green: 0.40, blue: 0.72)
    static let ember = warning
    static let metal = steel
}

extension View {
    func gtDisplayFont(_ size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .fontWidth(.expanded)
            .tracking(1.1)
    }

    func gtTitleFont(_ size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .fontWidth(.expanded)
            .tracking(0.5)
    }

    func gtCondensedFont(_ size: CGFloat, weight: Font.Weight = .medium) -> some View {
        self
            .font(.system(size: size, weight: weight, design: .monospaced))
            .fontWidth(.condensed)
            .tracking(0.2)
    }

    func gtCaptionFont(_ size: CGFloat = 12) -> some View {
        self
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .fontWidth(.condensed)
            .tracking(0.1)
    }
}

struct GTBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [GTTheme.void, GTTheme.deep],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [GTTheme.accent.opacity(0.12), Color.clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 320
            )

            RadialGradient(
                colors: [Color.white.opacity(0.06), Color.clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

struct Glow: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.35), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.18), radius: radius * 1.6, x: 0, y: 0)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 12) -> some View {
        self.modifier(Glow(color: color, radius: radius))
    }
}

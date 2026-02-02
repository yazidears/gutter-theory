import SwiftUI

struct GTCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(GTTheme.line, lineWidth: 0.8)
                    )
            )
    }
}

struct ModeCard: View {
    let mode: GTGameMode
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.rawValue.uppercased())
                .gtTitleFont(13)
                .foregroundStyle(.white)
            Text(modeDescription)
                .gtCaptionFont(9)
                .foregroundStyle(GTTheme.metal)
            Spacer()
        }
        .padding(14)
        .frame(width: 160, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.06 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? GTTheme.neonCyan : GTTheme.line, lineWidth: 0.9)
                )
        )
    }

    private var modeDescription: String {
        switch mode {
        case .laserTag:
            return "HEADING-LOCKED ARENA"
        case .pulseRush:
            return "ZONE SPRINT + CHARGE"
        case .echoRun:
            return "STEALTH + PROX PINGS"
        }
    }
}

struct PlayerRow: View {
    let player: GTPlayer

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: player.status)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .gtCondensedFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                Text("\(Int(player.distanceMeters))m • \(player.zoneLabel ?? "ZONE-?")")
                    .gtCaptionFont(10)
                    .foregroundStyle(GTTheme.metal)
            }
            Spacer()
            Text(player.status.rawValue.uppercased())
                .gtCaptionFont(9)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(statusColor.opacity(0.15))
                )
        }
    }

    private var statusColor: Color {
        switch player.status {
        case .linked:
            return GTTheme.neonGreen
        case .inRange:
            return GTTheme.ember
        case .outOfRange:
            return GTTheme.metal
        }
    }
}

struct StatusDot: View {
    let status: GTPlayer.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .glow(color, radius: 3)
    }

    private var color: Color {
        switch status {
        case .linked:
            return GTTheme.neonGreen
        case .inRange:
            return GTTheme.ember
        case .outOfRange:
            return GTTheme.metal
        }
    }
}

struct PrimaryActionButton: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .gtTitleFont(14)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .gtCaptionFont(10)
                    .foregroundStyle(GTTheme.metal)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GTTheme.neonCyan)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(GTTheme.neonCyan, lineWidth: 1)
                )
        )
    }
}

struct SecondaryActionButton: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .gtTitleFont(13)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .gtCaptionFont(10)
                    .foregroundStyle(GTTheme.metal)
            }
            Spacer()
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GTTheme.neonCyan)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.01))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(GTTheme.line, lineWidth: 0.8)
                )
        )
    }
}

struct StatusPill: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .gtCaptionFont(9)
                .foregroundStyle(GTTheme.metal)
            Text(value)
                .gtCaptionFont(9)
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.01))
                .overlay(
                    Capsule()
                        .stroke(GTTheme.line, lineWidth: 0.8)
                )
        )
    }
}

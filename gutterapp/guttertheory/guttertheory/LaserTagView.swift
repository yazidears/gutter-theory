import SwiftUI
import CoreMotion
import UIKit

struct LaserTagView: View {
    @ObservedObject var streetPass: StreetPassViewModel
    @StateObject private var viewModel = LaserTagViewModel()
    @State private var motionController = MotionShotController()
    @State private var motionFireEnabled = true

    var body: some View {
        ZStack {
            GTBackground()

            GeometryReader { geo in
                let radarSize = max(220, min(geo.size.width - 32, 360))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        zoneStatus
                        aimAssistCard
                        radar(size: radarSize)
                        statsRow
                        controlDock
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("LASER TAG")
                    .gtCaptionFont(12)
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            streetPass.start()
            viewModel.connect(players: streetPass.nearbyPlayers, heading: streetPass.localHeading)
            configureMotion()
        }
        .onDisappear {
            motionController.setEnabled(false)
        }
        .onReceive(streetPass.$nearbyPlayers) { players in
            viewModel.connect(players: players, heading: streetPass.localHeading)
        }
        .onReceive(streetPass.$localHeading) { heading in
            viewModel.updateHeading(heading)
        }
        .onChange(of: motionFireEnabled) { enabled in
            motionController.setEnabled(enabled)
        }
        .onChange(of: viewModel.aimAssist.state) { newState in
            triggerAimHaptic(for: newState)
        }
    }

    private func configureMotion() {
        motionController.onFire = { handleFire() }
        if !motionController.isAvailable {
            motionFireEnabled = false
            return
        }
        motionController.setEnabled(motionFireEnabled)
    }

    private func handleFire() {
        let target = viewModel.fire()
        streetPass.fireShot(target: target, heading: viewModel.compassHeading)
    }

    private func triggerAimHaptic(for state: AimAssistState) {
        switch state {
        case .locking:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        case .locked:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .tracking, .none:
            break
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow
            headerStack
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            headerLeft
            Spacer()
            headerRight
        }
    }

    private var headerStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerLeft
            headerRight
        }
    }

    private var headerLeft: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HEADING \(Int(viewModel.compassHeading))°")
                .gtTitleFont(20)
                .foregroundStyle(.white)
            Text(viewModel.statusMessage.uppercased())
                .gtCaptionFont(11)
                .foregroundStyle(GTTheme.metal)
            if let lastHit = viewModel.stats.lastHitName {
                Text("LAST HIT: \(lastHit.uppercased())")
                    .gtCaptionFont(10)
                    .foregroundStyle(GTTheme.neonGreen)
            }
        }
    }

    private var headerRight: some View {
        VStack(alignment: .trailing, spacing: 8) {
            StatusPill(label: "AIM", value: aimStateLabel, accent: aimColor)
            StatusPill(label: "MOTION", value: motionEnabledDisplay ? "ON" : "OFF", accent: motionEnabledDisplay ? GTTheme.neonCyan : GTTheme.metal)
        }
    }

    private var statsRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            StatChip(label: "SHOTS", value: "\(viewModel.stats.shotsFired)")
            StatChip(label: "HITS", value: "\(viewModel.stats.hits)")
            StatChip(label: "STREAK", value: "\(viewModel.stats.streak)")
        }
    }

    private var zoneStatus: some View {
        let sameZoneCount = streetPass.nearbyPlayers.filter { $0.zoneKey == streetPass.localZoneKey }.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ZONE LINK")
                    .gtCaptionFont(11)
                    .foregroundStyle(GTTheme.metal)
                Text(streetPass.localZoneLabel ?? "GRID-?")
                    .gtCaptionFont(10)
                    .foregroundStyle(GTTheme.neonCyan)
                Text(sameZoneCount > 0 ? "CREW IN ZONE x\(sameZoneCount)" : "NO CREW IN ZONE")
                    .gtTitleFont(14)
                    .foregroundStyle(.white)
            }
            Spacer()
            Circle()
                .fill(sameZoneCount > 0 ? GTTheme.neonCyan : GTTheme.warning)
                .frame(width: 12, height: 12)
                .glow(sameZoneCount > 0 ? GTTheme.neonCyan : GTTheme.warning, radius: 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(GTTheme.line, lineWidth: 1)
                )
        )
    }

    private var aimAssistCard: some View {
        GTCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AIM ASSIST")
                        .gtCaptionFont(10)
                        .foregroundStyle(GTTheme.metal)
                    Text(aimHeadline)
                        .gtTitleFont(16)
                        .foregroundStyle(aimColor)
                    Text(aimSubline)
                        .gtCaptionFont(10)
                        .foregroundStyle(.white)
                }
                Spacer()
                AimDial(progress: viewModel.aimAssist.progress, state: viewModel.aimAssist.state)
            }
        }
    }

    private func radar(size: CGFloat) -> some View {
        RadarView(
            heading: viewModel.compassHeading,
            targets: viewModel.targets,
            aimTargetID: viewModel.aimAssist.targetID,
            aimState: viewModel.aimAssist.state,
            aimProgress: viewModel.aimAssist.progress
        )
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
    }

    private var controlDock: some View {
        VStack(spacing: 12) {
            fireButton
            motionToggle
        }
    }

    private var fireButton: some View {
        Button {
            handleFire()
        } label: {
            HStack {
                Text("FIRE")
                    .gtTitleFont(18)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "scope")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GTTheme.neonCyan)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(GTTheme.neonCyan, lineWidth: 1.4)
                    )
            )
        }
    }

    private var motionToggle: some View {
        let motionAvailable = motionController.isAvailable
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MOTION FIRE")
                    .gtCaptionFont(10)
                    .foregroundStyle(GTTheme.metal)
                Text(motionAvailable ? "Flick forward to shoot" : "Motion sensors unavailable")
                    .gtCaptionFont(9)
                    .foregroundStyle(motionAvailable ? .white : GTTheme.metal)
            }
            Spacer()
            Toggle("", isOn: $motionFireEnabled)
                .labelsHidden()
                .tint(GTTheme.neonCyan)
                .disabled(!motionAvailable)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(GTTheme.line, lineWidth: 0.9)
                )
        )
    }

    private var aimHeadline: String {
        switch viewModel.aimAssist.state {
        case .locked:
            return "LOCKED ON"
        case .locking:
            return "HOLD STEADY"
        case .tracking:
            return "TARGET NEAR"
        case .none:
            return "NO TARGET"
        }
    }

    private var aimSubline: String {
        guard viewModel.aimAssist.state != .none else {
            return "SWEEP TO ACQUIRE"
        }

        let name = viewModel.aimAssist.targetName?.uppercased() ?? "UNKNOWN"
        let distance = viewModel.aimAssist.distanceMeters.map { "\(Int($0))m" } ?? "--m"
        let angle = viewModel.aimAssist.angleDifference.map { "\(Int($0))°" } ?? "--°"
        return "\(name) • \(distance) • \(angle)"
    }

    private var aimStateLabel: String {
        switch viewModel.aimAssist.state {
        case .locked:
            return "LOCKED"
        case .locking:
            return "LOCKING"
        case .tracking:
            return "TRACKING"
        case .none:
            return "SEARCH"
        }
    }

    private var aimColor: Color {
        switch viewModel.aimAssist.state {
        case .locked:
            return GTTheme.neonGreen
        case .locking:
            return GTTheme.neonCyan
        case .tracking:
            return GTTheme.ember
        case .none:
            return GTTheme.metal
        }
    }

    private var motionEnabledDisplay: Bool {
        motionFireEnabled && motionController.isAvailable
    }
}

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .gtCaptionFont(10)
                .foregroundStyle(GTTheme.metal)
            Text(value)
                .gtTitleFont(14)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(GTTheme.line, lineWidth: 1)
                )
        )
    }
}

private struct AimDial: View {
    let progress: Double
    let state: AimAssistState

    var body: some View {
        let color = dialColor

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
            Text(label)
                .gtCaptionFont(9)
                .foregroundStyle(color)
        }
        .frame(width: 64, height: 64)
    }

    private var label: String {
        switch state {
        case .locked:
            return "LOCK"
        case .locking:
            return "AIM"
        case .tracking:
            return "SCAN"
        case .none:
            return "--"
        }
    }

    private var dialColor: Color {
        switch state {
        case .locked:
            return GTTheme.neonGreen
        case .locking:
            return GTTheme.neonCyan
        case .tracking:
            return GTTheme.ember
        case .none:
            return GTTheme.metal
        }
    }
}

private struct RadarView: View {
    let heading: Double
    let targets: [GTPlayer]
    let aimTargetID: UUID?
    let aimState: AimAssistState
    let aimProgress: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.02))
                Circle()
                    .stroke(GTTheme.neonCyan.opacity(0.4), lineWidth: 1.6)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    .frame(width: size * 0.66, height: size * 0.66)
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                    .frame(width: size * 0.33, height: size * 0.33)

                RadarSweep()
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0, to: aimProgress)
                    .stroke(aimColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size * 0.62, height: size * 0.62)
                    .opacity(aimState == .none ? 0 : 0.9)
                    .animation(.easeOut(duration: 0.2), value: aimProgress)

                if aimState == .locked {
                    LockPulse(color: aimColor)
                        .frame(width: size * 0.7, height: size * 0.7)
                }

                ForEach(targets) { target in
                    let point = targetPoint(target, radius: radius)
                    TargetBlip(
                        name: target.name,
                        status: target.status,
                        isTracked: aimTargetID == target.id,
                        isLocked: aimTargetID == target.id && aimState == .locked
                    )
                    .position(x: radius + point.x, y: radius + point.y)
                }

                Crosshair(color: aimColor, isLocked: aimState == .locked)
                    .frame(width: size * 0.5, height: size * 0.5)
            }
            .frame(width: size, height: size)
        }
    }

    private var aimColor: Color {
        switch aimState {
        case .locked:
            return GTTheme.neonGreen
        case .locking:
            return GTTheme.neonCyan
        case .tracking:
            return GTTheme.ember
        case .none:
            return GTTheme.neonCyan.opacity(0.6)
        }
    }

    private func targetPoint(_ target: GTPlayer, radius: CGFloat) -> CGPoint {
        let maxDistance: Double = 40
        let distanceRatio = min(target.distanceMeters, maxDistance) / maxDistance
        let angle = (target.heading - heading - 90) * Double.pi / 180
        let r = Double(radius) * distanceRatio
        let x = cos(angle) * r
        let y = sin(angle) * r
        return CGPoint(x: x, y: y)
    }
}

private struct TargetBlip: View {
    let name: String
    let status: GTPlayer.Status
    let isTracked: Bool
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .glow(color, radius: 8)
                if isTracked {
                    Circle()
                        .stroke(color.opacity(isLocked ? 1 : 0.7), lineWidth: isLocked ? 2 : 1)
                        .frame(width: isLocked ? 26 : 20, height: isLocked ? 26 : 20)
                }
            }
            Text(name)
                .gtCaptionFont(9)
                .foregroundStyle(.white)
        }
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

private struct Crosshair: View {
    let color: Color
    let isLocked: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color.opacity(0.22))
                .frame(width: isLocked ? 3 : 2)
            Rectangle()
                .fill(color.opacity(0.22))
                .frame(height: isLocked ? 3 : 2)
        }
        .glow(color, radius: isLocked ? 10 : 6)
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }
}

private struct LockPulse: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.6), lineWidth: 2)
            .scaleEffect(pulse ? 1.1 : 0.9)
            .opacity(pulse ? 0.0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

private struct RadarSweep: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(
                LinearGradient(
                    colors: [GTTheme.neonCyan.opacity(0.0), GTTheme.neonCyan.opacity(0.3)],
                    startPoint: .center,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 16, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

final class MotionShotController {
    private let motionManager = CMMotionManager()
    private var isActive = false
    private var lastFireTime: TimeInterval = 0

    var onFire: (() -> Void)?
    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    func setEnabled(_ enabled: Bool) {
        guard enabled, motionManager.isDeviceMotionAvailable else {
            stop()
            return
        }
        guard !isActive else { return }
        isActive = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    private func handle(_ motion: CMDeviceMotion) {
        let accel = motion.userAcceleration
        let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
        let forwardThrust = -accel.z
        let now = Date().timeIntervalSince1970

        guard magnitude > 0.9, forwardThrust > 0.6 else { return }
        guard now - lastFireTime > 0.55 else { return }
        lastFireTime = now
        onFire?()
    }

    private func stop() {
        guard isActive else { return }
        motionManager.stopDeviceMotionUpdates()
        isActive = false
    }

    deinit {
        stop()
    }
}

#Preview {
    LaserTagView(streetPass: StreetPassViewModel())
}

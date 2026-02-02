import SwiftUI

struct HomeView: View {
    @ObservedObject var streetPass: StreetPassViewModel
    @State private var selectedMode: GTGameMode = .laserTag

    var body: some View {
        ZStack {
            GTBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    streetPassCard
                    modeToggle
                    statusStrip
                    modeSelector
                    lobbyPreview
                    actionRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GUTTER THEORY")
                .gtDisplayFont(28)
                .foregroundStyle(.white)

            Text("PROXIMITY MESH")
                .gtCaptionFont(11)
                .foregroundStyle(GTTheme.neonCyan)
        }
    }

    private var streetPassCard: some View {
        GTCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("STREETPASS")
                        .gtCaptionFont(10)
                        .foregroundStyle(GTTheme.metal)
                    Text(streetPass.isScanning ? "ON" : "OFF")
                        .gtTitleFont(16)
                        .foregroundStyle(.white)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { streetPass.isScanning },
                    set: { isOn in
                        if isOn {
                            streetPass.start()
                        } else {
                            streetPass.stop()
                        }
                    })
                )
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: GTTheme.neonCyan))
            }
        }
    }

    private var modeToggle: some View {
        GTCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("SYNC MODE")
                    .gtCaptionFont(10)
                    .foregroundStyle(GTTheme.metal)

                Picker("", selection: Binding(
                    get: { streetPass.connectivityMode },
                    set: { newValue in
                        streetPass.setConnectivityMode(newValue)
                    })
                ) {
                    ForEach(ConnectivityMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(GTTheme.neonCyan)
            }
        }
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RUN MODES")
                .gtCaptionFont(10)
                .foregroundStyle(GTTheme.metal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GTGameMode.allCases, id: \.self) { mode in
                        ModeCard(mode: mode, isSelected: mode == selectedMode)
                            .onTapGesture {
                                selectedMode = mode
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var statusStrip: some View {
        let zoneLabel = streetPass.localZoneLabel ?? "GRID-?"
        let crewCount = streetPass.nearbyPlayers.filter { $0.zoneKey == streetPass.localZoneKey }.count
        let backendLabel = streetPass.connectivityMode == .meshAndBackend ? streetPass.backendStatus.rawValue.uppercased() : "OFF"
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StatusPill(label: "ZONE", value: zoneLabel, accent: GTTheme.neonCyan)
                StatusPill(label: "CREW", value: "\(crewCount)", accent: crewCount > 0 ? GTTheme.neonCyan : GTTheme.metal)
                StatusPill(label: "MESH", value: "\(streetPass.meshPeerCount)", accent: GTTheme.neonCyan)
                StatusPill(label: "BACKEND", value: backendLabel, accent: GTTheme.metal)
            }
            .padding(.vertical, 4)
        }
    }

    private var lobbyPreview: some View {
        GTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CREW FEED")
                        .gtCaptionFont(10)
                        .foregroundStyle(GTTheme.metal)
                    Spacer()
                    Text("\(streetPass.nearbyPlayers.count) ONLINE")
                        .gtCaptionFont(10)
                        .foregroundStyle(GTTheme.neonCyan)
                }

                if streetPass.nearbyPlayers.isEmpty {
                    Text("No links yet. Start StreetPass to ping your crew.")
                        .gtCondensedFont(11, weight: .medium)
                        .foregroundStyle(GTTheme.metal)
                } else {
                    ForEach(streetPass.nearbyPlayers.prefix(4)) { player in
                        PlayerRow(player: player)
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        VStack(spacing: 12) {
            NavigationLink {
                LobbyView(mode: selectedMode, streetPass: streetPass)
            } label: {
                PrimaryActionButton(title: "CREATE RUN", subtitle: "MODE: \(selectedMode.rawValue)")
            }

            NavigationLink {
                LaserTagView(streetPass: streetPass)
            } label: {
                SecondaryActionButton(title: "ENTER LASER TAG", subtitle: "Instant session")
            }
        }
    }
}

#Preview {
    HomeView(streetPass: StreetPassViewModel())
}

import SwiftUI

struct LobbyView: View {
    let mode: GTGameMode
    @ObservedObject var streetPass: StreetPassViewModel
    @State private var isReady = false
    @State private var isCreating = false

    var body: some View {
        ZStack {
            GTBackground()
            VStack(alignment: .leading, spacing: 20) {
                header
                lobbyInfo
                roster
                Spacer()
                actionBar
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard streetPass.lobbyCode == nil else { return }
            if !isCreating {
                isCreating = true
                Task { @MainActor in
                    await streetPass.createLobby(mode: mode)
                    isCreating = false
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("LOBBY")
                    .gtCaptionFont(12)
                    .foregroundStyle(.white)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.rawValue.uppercased())
                .gtTitleFont(22)
                .foregroundStyle(.white)
            Text("ROOM CODE \(streetPass.lobbyCode ?? "----")")
                .gtCaptionFont(11)
                .foregroundStyle(GTTheme.metal)
        }
    }

    private var lobbyInfo: some View {
        GTCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CREW LINKED")
                        .gtCaptionFont(11)
                        .foregroundStyle(GTTheme.metal)
                    Text("\(streetPass.nearbyPlayers.filter { $0.status == .linked }.count) READY")
                        .gtTitleFont(16)
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("SESSION")
                        .gtCaptionFont(11)
                        .foregroundStyle(GTTheme.metal)
                    Text("URBAN NIGHT")
                        .gtTitleFont(16)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ROSTER")
                .gtCaptionFont(12)
                .foregroundStyle(GTTheme.metal)

            GTCard {
                VStack(spacing: 12) {
                    if streetPass.nearbyPlayers.isEmpty {
                        Text("Start StreetPass to pull players into the lobby.")
                            .gtCondensedFont(12, weight: .medium)
                            .foregroundStyle(GTTheme.metal)
                    } else {
                        ForEach(streetPass.nearbyPlayers) { player in
                            PlayerRow(player: player)
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            Toggle("READY TO DEPLOY", isOn: $isReady)
                .toggleStyle(SwitchToggleStyle(tint: GTTheme.neonCyan))
                .foregroundStyle(.white)
                .gtCaptionFont(12)

            NavigationLink {
                LaserTagView(streetPass: streetPass)
            } label: {
                PrimaryActionButton(title: "START RUN", subtitle: "Launch when crew is ready")
            }
        }
    }
}

#Preview {
    LobbyView(mode: .laserTag, streetPass: StreetPassViewModel())
}

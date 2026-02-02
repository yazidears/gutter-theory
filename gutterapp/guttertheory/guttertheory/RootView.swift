import SwiftUI

struct RootView: View {
    @StateObject private var streetPass = StreetPassViewModel()

    var body: some View {
        NavigationStack {
            HomeView(streetPass: streetPass)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
}

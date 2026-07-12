import SwiftUI

@main
struct PanoApp: App {
    @State private var session = Session()
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.scheme)
                .task { await session.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    // Uygulama öne gelince durumu tazele ve canlı senkron kanalını yeniden kur.
                    if phase == .active, session.isLoggedIn {
                        Task { await session.refresh() }
                        session.startEvents()
                    }
                }
        }
    }
}

struct ContentView: View {
    @Environment(Session.self) private var session

    var body: some View {
        if session.isBootstrapping {
            ProgressView()
        } else if session.isLoggedIn {
            RootView()
        } else {
            AuthView()
        }
    }
}

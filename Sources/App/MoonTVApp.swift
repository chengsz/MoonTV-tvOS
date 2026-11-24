import SwiftUI

@main
struct MoonTVApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isConfigured {
                    MainTabView()
                } else {
                    ServerSetupView(isInitialSetup: true)
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.dark)
        }
    }
}

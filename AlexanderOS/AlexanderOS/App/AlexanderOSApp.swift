import SwiftUI

@main
struct AlexanderOSApp: App {
    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(environment)
                .task {
                    // Auto-start pipeline when models are ready
                    if environment.modelStatus == .ready {
                        await environment.startPipeline()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task { await environment.refreshStatus() }
                    case .background:
                        // Pipeline continues running in background
                        break
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}

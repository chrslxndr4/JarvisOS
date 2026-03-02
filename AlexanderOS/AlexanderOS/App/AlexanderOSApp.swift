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
                    // Give App Intents access to the pipeline
                    PipelineAccessor.shared.environment = environment

                    // Auto-start pipeline when models are ready
                    if environment.modelStatus == .ready {
                        await environment.startPipeline()
                    }
                }
                .onOpenURL { url in
                    JARVISURLHandler.shared.handleURL(url)
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

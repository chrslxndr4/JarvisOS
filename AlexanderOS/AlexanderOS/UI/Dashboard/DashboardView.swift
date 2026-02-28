import SwiftUI
import JARVISCore

struct DashboardView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Card
                    StatusCard(
                        relayConnected: environment.relayConnected,
                        whatsappConnected: environment.whatsappConnected,
                        modelStatus: environment.modelStatus
                    )

                    // Processing indicator
                    if environment.isProcessing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Processing command...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Last Command Card
                    if let lastCommand = environment.lastCommand {
                        LastCommandCard(
                            command: lastCommand,
                            result: environment.lastResult
                        )
                    }

                    // Quick Actions
                    QuickActionsCard()

                    // Navigation
                    NavigationCard()
                }
                .padding()
            }
            .navigationTitle("Alexander OS")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .refreshable {
                await environment.refreshStatus()
            }
        }
    }
}

// MARK: - Status Card

private struct StatusCard: View {
    let relayConnected: Bool
    let whatsappConnected: Bool
    let modelStatus: AppEnvironment.ModelStatus

    var allGreen: Bool {
        relayConnected && whatsappConnected && modelStatus == .ready
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: allGreen ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(allGreen ? .green : .orange)
                Text(allGreen ? "All Systems Online" : "Setup Required")
                    .font(.headline)
                Spacer()
            }

            Divider()

            StatusRow(icon: "network", label: "Relay", connected: relayConnected)
            StatusRow(icon: "message.fill", label: "WhatsApp", connected: whatsappConnected)
            ModelStatusRow(status: modelStatus)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatusRow: View {
    let icon: String
    let label: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(connected ? "Connected" : "Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ModelStatusRow: View {
    let status: AppEnvironment.ModelStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain")
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text("AI Model")
            Spacer()
            switch status {
            case .notDownloaded:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.orange)
                Text("Not Downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 60)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .ready:
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Last Command Card

private struct LastCommandCard: View {
    let command: String
    let result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.blue)
                Text("Last Command")
                    .font(.headline)
                Spacer()
            }

            Text(command)
                .font(.body.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let result {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: result.hasPrefix("Error") ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(result.hasPrefix("Error") ? .red : .green)
                        .font(.caption)
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Quick Actions

private struct QuickActionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                QuickActionButton(icon: "lightbulb", label: "Lights", color: .yellow)
                QuickActionButton(icon: "lock", label: "Locks", color: .blue)
                QuickActionButton(icon: "thermometer", label: "Climate", color: .orange)
                QuickActionButton(icon: "wand.and.stars", label: "Scenes", color: .purple)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Navigation Card

private struct NavigationCard: View {
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: CommandLogView()) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 24)
                    Text("Command History")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 44)

            NavigationLink(destination: SettingsView()) {
                HStack {
                    Image(systemName: "gearshape")
                        .frame(width: 24)
                    Text("Settings")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .buttonStyle(.plain)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

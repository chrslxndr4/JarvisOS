import SwiftUI
import JARVISCore
import CommandCatalog

struct SettingsView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var showingAddShortcut = false
    @State private var newShortcutName = ""
    @State private var newShortcutDescription = ""

    var body: some View {
        Form {
            // Relay Connection
            Section {
                TextField("WebSocket URL", text: $environment.relayURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                HStack {
                    Text("Status")
                    Spacer()
                    Circle()
                        .fill(environment.relayConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(environment.relayConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Reconnect") {
                    Task { await environment.reconnect() }
                }
            } header: {
                Text("Relay Connection")
            } footer: {
                Text("The relay runs on your Mac and bridges WhatsApp messages to this app.")
            }

            // AI Models
            Section {
                switch environment.modelStatus {
                case .notDownloaded:
                    HStack {
                        Text("Status")
                        Spacer()
                        Text("Not Downloaded")
                            .foregroundStyle(.secondary)
                    }
                    Button("Download Models") {
                        Task { await environment.downloadModels() }
                    }
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Downloading...")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress)
                    }
                case .ready:
                    HStack {
                        Text("Status")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Ready")
                            .foregroundStyle(.secondary)
                    }
                    Button("Delete Models", role: .destructive) {
                        Task { await environment.deleteModels() }
                    }
                case .error(let msg):
                    HStack {
                        Text("Error")
                        Spacer()
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    Button("Retry Download") {
                        Task { await environment.downloadModels() }
                    }
                }
            } header: {
                Text("AI Models")
            } footer: {
                Text("Qwen 2.5 1.5B (~1 GB) for intent classification, Whisper Base (~148 MB) for voice transcription. Models are stored locally.")
            }

            // Service Shortcuts (Built-in)
            Section {
                ForEach(ShortcutDiscovery.builtInShortcuts) { shortcut in
                    ServiceShortcutRow(shortcut: shortcut)
                }
            } header: {
                Text("Service Shortcuts")
            } footer: {
                Text("These shortcuts connect JARVIS to services it can't reach natively. Create each one in the Apple Shortcuts app with the exact name shown. Each shortcut should accept text input and open the callback URL with the result.")
            }

            // Custom Shortcuts Registry
            Section {
                if environment.registeredShortcuts.isEmpty {
                    Text("No custom shortcuts registered")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(environment.registeredShortcuts, id: \.self) { shortcut in
                        Text(shortcut)
                    }
                    .onDelete { offsets in
                        environment.registeredShortcuts.remove(atOffsets: offsets)
                    }
                }

                Button("Add Shortcut") {
                    showingAddShortcut = true
                }
            } header: {
                Text("Custom Shortcuts")
            } footer: {
                Text("Register your own Siri Shortcuts so JARVIS can trigger them by name.")
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Codename")
                    Spacer()
                    Text("JARVIS")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Add Shortcut", isPresented: $showingAddShortcut) {
            TextField("Shortcut Name", text: $newShortcutName)
            TextField("Description (optional)", text: $newShortcutDescription)
            Button("Add") {
                if !newShortcutName.isEmpty {
                    environment.registeredShortcuts.append(newShortcutName)
                    Task { await environment.saveShortcut(name: newShortcutName, description: newShortcutDescription) }
                    newShortcutName = ""
                    newShortcutDescription = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newShortcutName = ""
                newShortcutDescription = ""
            }
        }
    }
}

// MARK: - Service Shortcut Row

private struct ServiceShortcutRow: View {
    let shortcut: JARVISCore.CatalogShortcut

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortcut.name)
                    .font(.body)
                Spacer()
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
            }
            if let description = shortcut.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch shortcut.id {
        case "builtin-weather": return "cloud.sun"
        case "builtin-music": return "music.note"
        case "builtin-whatsapp": return "message"
        case "builtin-timer": return "timer"
        case "builtin-dnd": return "moon.fill"
        case "builtin-findmy": return "location"
        case "builtin-text": return "bubble.left"
        case "builtin-translate": return "globe"
        default: return "arrow.right.circle"
        }
    }
}

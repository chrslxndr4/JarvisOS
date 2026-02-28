import SwiftUI
import MemorySystem

struct CommandLogView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var commands: [CommandLogEntry] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if commands.isEmpty {
                ContentUnavailableView(
                    "No Commands Yet",
                    systemImage: "text.bubble",
                    description: Text("Commands from your Ray-Ban glasses will appear here.")
                )
            } else {
                List(commands) { entry in
                    CommandLogRow(entry: entry)
                }
            }
        }
        .navigationTitle("Command Log")
        .task {
            await loadCommands()
        }
        .refreshable {
            await loadCommands()
        }
    }

    private func loadCommands() async {
        do {
            let records = try await environment.fetchRecentCommands()
            commands = records.map { CommandLogEntry(record: $0) }
        } catch {
            commands = []
        }
        isLoading = false
    }
}

struct CommandLogEntry: Identifiable {
    let id: String
    let rawText: String
    let source: String
    let intentAction: String?
    let resultType: String?
    let resultMessage: String?
    let timestamp: Date

    init(record: CommandLogRecord) {
        self.id = record.id
        self.rawText = record.rawText
        self.source = record.source
        self.intentAction = record.intentAction
        self.resultType = record.resultType
        self.resultMessage = record.resultMessage
        self.timestamp = record.timestamp
    }
}

private struct CommandLogRow: View {
    let entry: CommandLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: sourceIcon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(entry.rawText)
                    .font(.body)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let action = entry.intentAction {
                    Label(action, systemImage: "arrow.right.circle")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                Label(resultLabel, systemImage: resultIcon)
                    .font(.caption2)
                    .foregroundStyle(resultColor)

                Spacer()

                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let message = entry.resultMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceIcon: String {
        switch entry.source {
        case "whatsappVoice": return "mic"
        case "whatsappText": return "message"
        case "siri": return "waveform"
        case "appUI": return "hand.tap"
        default: return "questionmark.circle"
        }
    }

    private var resultLabel: String {
        switch entry.resultType {
        case "success": return "Done"
        case "failure": return "Failed"
        case "confirmation": return "Pending"
        case "ambiguous": return "Ambiguous"
        default: return "Unknown"
        }
    }

    private var resultIcon: String {
        switch entry.resultType {
        case "success": return "checkmark.circle"
        case "failure": return "xmark.circle"
        case "confirmation": return "questionmark.circle"
        case "ambiguous": return "list.bullet"
        default: return "circle"
        }
    }

    private var resultColor: Color {
        switch entry.resultType {
        case "success": return .green
        case "failure": return .red
        case "confirmation": return .orange
        case "ambiguous": return .yellow
        default: return .gray
        }
    }
}

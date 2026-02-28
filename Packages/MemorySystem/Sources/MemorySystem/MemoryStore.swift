import Foundation
import GRDB
import JARVISCore

public actor MemoryStore: MemoryStoring {
    private let db: DatabaseManager

    public init(databasePath: String? = nil) throws {
        self.db = try DatabaseManager(path: databasePath)
    }

    // MARK: - Command Logging

    public func storeCommandLog(command: JARVISCommand, intent: JARVISIntent?, result: ExecutionResult?) async throws {
        let record = CommandLogRecord.from(command: command, intent: intent, result: result)
        try await db.writer.write { db in
            try record.insert(db)
        }

        // Also store as context memory for AI prompt context
        let contextEntry = ContextMemoryRecord.create(
            role: "user",
            content: command.rawText
        )
        try await db.writer.write { db in
            try contextEntry.insert(db)
        }

        if let resultMsg = result?.displayMessage {
            let responseEntry = ContextMemoryRecord.create(
                role: "assistant",
                content: resultMsg
            )
            try await db.writer.write { db in
                try responseEntry.insert(db)
            }
        }
    }

    // MARK: - Notes

    public func storeNote(content: String, tags: [String]) async throws {
        let record = NoteRecord.create(content: content, tags: tags)
        try await db.writer.write { db in
            try record.insert(db)
        }
    }

    // MARK: - Context

    public func queryContext(limit: Int) async throws -> [String] {
        try await db.reader.read { db in
            let records = try ContextMemoryRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
            return records.reversed().map { "\($0.role): \($0.content)" }
        }
    }

    // MARK: - Search (FTS5)

    public func search(query: String) async throws -> [String] {
        try await db.reader.read { db in
            let noteResults = try String.fetchAll(db, sql: """
                SELECT note.content FROM note
                JOIN noteFts ON noteFts.rowid = note.rowid
                WHERE noteFts MATCH ?
                ORDER BY rank
                LIMIT 10
                """, arguments: [query])

            let contextResults = try String.fetchAll(db, sql: """
                SELECT contextMemory.content FROM contextMemory
                JOIN contextMemoryFts ON contextMemoryFts.rowid = contextMemory.rowid
                WHERE contextMemoryFts MATCH ?
                ORDER BY rank
                LIMIT 10
                """, arguments: [query])

            return noteResults + contextResults
        }
    }

    // MARK: - Pending Responses

    public func storePendingResponse(commandId: UUID, intent: JARVISIntent, prompt: String) async throws {
        let record = PendingResponseRecord.from(commandId: commandId, intent: intent, prompt: prompt)
        try await db.writer.write { db in
            try record.insert(db)
        }
    }

    public func fetchLatestPendingResponse() async throws -> PendingResponseRecord? {
        try await db.reader.read { db in
            try PendingResponseRecord
                .filter(Column("expiresAt") > Date())
                .order(Column("createdAt").desc)
                .fetchOne(db)
        }
    }

    public func deletePendingResponse(id: String) async throws {
        try await db.writer.write { db in
            _ = try PendingResponseRecord
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }

    // MARK: - Shortcuts Registry

    public func storeShortcut(name: String, description: String?) async throws {
        let record = CatalogShortcutRecord(
            id: UUID().uuidString,
            name: name,
            description: description,
            createdAt: Date()
        )
        try await db.writer.write { db in
            try record.insert(db)
        }
    }

    public func fetchShortcuts() async throws -> [CatalogShortcutRecord] {
        try await db.reader.read { db in
            try CatalogShortcutRecord.order(Column("name")).fetchAll(db)
        }
    }

    // MARK: - Command History

    public func fetchRecentCommands(limit: Int = 50) async throws -> [CommandLogRecord] {
        try await db.reader.read { db in
            try CommandLogRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}

// MARK: - Private helpers

private extension ExecutionResult {
    var displayMessage: String? {
        switch self {
        case .success(let msg): return msg
        case .failure(let err): return "Error: \(err)"
        case .confirmationRequired(let prompt, _): return prompt
        case .ambiguous(let options): return "Options: \(options.joined(separator: ", "))"
        }
    }
}

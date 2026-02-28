import Foundation
import GRDB

public final class DatabaseManager: Sendable {
    private let dbPool: DatabasePool

    public init(path: String? = nil) throws {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbDir = appSupport.appendingPathComponent("AlexanderOS", isDirectory: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            dbPath = dbDir.appendingPathComponent("jarvis.sqlite").path
        }

        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL mode for better concurrent read performance
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        dbPool = try DatabasePool(path: dbPath, configuration: config)
        try migrator.migrate(dbPool)
    }

    var reader: DatabaseReader { dbPool }
    var writer: DatabaseWriter { dbPool }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial") { db in
            // Command log
            try db.create(table: "commandLog") { t in
                t.primaryKey("id", .text).notNull()
                t.column("rawText", .text).notNull()
                t.column("source", .text).notNull()
                t.column("intentAction", .text)
                t.column("intentTarget", .text)
                t.column("intentParameters", .text) // JSON
                t.column("intentConfidence", .double)
                t.column("resultType", .text) // success, failure, confirmation, ambiguous
                t.column("resultMessage", .text)
                t.column("timestamp", .datetime).notNull().indexed()
            }

            // Notes
            try db.create(table: "note") { t in
                t.primaryKey("id", .text).notNull()
                t.column("content", .text).notNull()
                t.column("tags", .text) // JSON array
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Tasks
            try db.create(table: "task") { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
                t.column("dueDate", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }

            // Context memory (recent interactions for AI prompt context)
            try db.create(table: "contextMemory") { t in
                t.primaryKey("id", .text).notNull()
                t.column("role", .text).notNull() // user, assistant, system
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull().indexed()
            }

            // Catalog shortcuts (user-registered shortcuts)
            try db.create(table: "catalogShortcut") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Pending responses (for confirmation flow)
            try db.create(table: "pendingResponse") { t in
                t.primaryKey("id", .text).notNull()
                t.column("commandId", .text).notNull()
                t.column("intentAction", .text).notNull()
                t.column("intentTarget", .text)
                t.column("intentParameters", .text) // JSON
                t.column("prompt", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("expiresAt", .datetime).notNull()
            }

            // FTS5 for full-text search on notes
            try db.create(virtualTable: "noteFts", using: FTS5()) { t in
                t.synchronize(withTable: "note")
                t.tokenizer = .unicode61()
                t.column("content")
                t.column("tags")
            }

            // FTS5 for context memory search
            try db.create(virtualTable: "contextMemoryFts", using: FTS5()) { t in
                t.synchronize(withTable: "contextMemory")
                t.tokenizer = .unicode61()
                t.column("content")
            }
        }

        return migrator
    }
}

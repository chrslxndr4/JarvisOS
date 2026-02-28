import Foundation
import GRDB

struct ContextMemoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "contextMemory"

    var id: String
    var role: String
    var content: String
    var timestamp: Date

    static func create(role: String, content: String) -> ContextMemoryRecord {
        ContextMemoryRecord(
            id: UUID().uuidString,
            role: role,
            content: content,
            timestamp: Date()
        )
    }
}

import Foundation
import GRDB

struct NoteRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "note"

    var id: String
    var content: String
    var tags: String? // JSON array
    var createdAt: Date
    var updatedAt: Date

    static func create(content: String, tags: [String]) -> NoteRecord {
        let tagsJSON = try? String(data: JSONEncoder().encode(tags), encoding: .utf8)
        let now = Date()
        return NoteRecord(
            id: UUID().uuidString,
            content: content,
            tags: tagsJSON,
            createdAt: now,
            updatedAt: now
        )
    }
}

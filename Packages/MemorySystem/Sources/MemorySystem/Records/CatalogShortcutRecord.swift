import Foundation
import GRDB

public struct CatalogShortcutRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "catalogShortcut"

    public var id: String
    public var name: String
    public var description: String?
    public var createdAt: Date

    public init(id: String, name: String, description: String?, createdAt: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
    }
}

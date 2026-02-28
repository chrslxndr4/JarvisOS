import Foundation
import GRDB

struct TaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "task"

    var id: String
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var createdAt: Date
    var completedAt: Date?
}

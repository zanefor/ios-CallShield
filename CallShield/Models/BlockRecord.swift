import Foundation

struct BlockRecord: Codable, Identifiable {
    var id: UUID
    var number: String
    var label: String
    var blockedAt: Date

    init(id: UUID = UUID(), number: String, label: String = "", blockedAt: Date = Date()) {
        self.id = id
        self.number = number
        self.label = label
        self.blockedAt = blockedAt
    }
}

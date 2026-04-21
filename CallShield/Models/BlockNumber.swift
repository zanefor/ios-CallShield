import Foundation

struct BlockNumber: Codable, Identifiable, Hashable {
    var id: UUID
    var number: String
    var label: String
    var group: String
    var isPrefix: Bool // true = 前缀匹配, false = 精确匹配
    var createdAt: Date
    var isPreset: Bool // 是否为预置数据

    init(id: UUID = UUID(), number: String, label: String = "", group: String = "默认", isPrefix: Bool = false, createdAt: Date = Date(), isPreset: Bool = false) {
        self.id = id
        self.number = number
        self.label = label
        self.group = group
        self.isPrefix = isPrefix
        self.createdAt = createdAt
        self.isPreset = isPreset
    }
}

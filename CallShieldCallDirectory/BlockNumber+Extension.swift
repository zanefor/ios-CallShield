import Foundation

// Extension 需要访问的共享模型，独立副本
struct BlockNumber: Codable {
    var id: UUID
    var number: String
    var label: String
    var group: String
    var isPrefix: Bool
    var createdAt: Date
    var isPreset: Bool
}

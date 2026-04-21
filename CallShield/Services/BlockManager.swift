import Foundation
import CallKit

class BlockManager: ObservableObject {
    @Published var blockNumbers: [BlockNumber] = []
    @Published var blockRecords: [BlockRecord] = []

    private let appGroup = AppGroupManager.shared

    init() {
        loadAllData()
    }

    /// 预置数据版本号（每次更新预置数据时递增，触发自动合并）
    private static let presetVersion = 12

    func loadAllData() {
        blockNumbers = appGroup.loadBlockNumbers()
        blockRecords = appGroup.loadBlockRecords()

        // 首次启动（从未写入过数据），加载预置数据
        if blockNumbers.isEmpty && !appGroup.hasDataFile {
            blockNumbers = PresetNumbers.presetNumbers
            saveAll()
            markPresetVersion()
        } else if needsPresetUpdate() {
            // 预置数据版本更新，自动合并新预置（保留自定义号码）
            mergeUpdatedPresets()
        }
    }

    private func needsPresetUpdate() -> Bool {
        let savedVersion = appGroup.sharedDefaults?.integer(forKey: "presetVersion") ?? 0
        return savedVersion < BlockManager.presetVersion
    }

    private func markPresetVersion() {
        appGroup.sharedDefaults?.set(BlockManager.presetVersion, forKey: "presetVersion")
    }

    /// 合并新预置数据：删除旧预置，加入新预置，保留自定义号码
    private func mergeUpdatedPresets() {
        let customNumbers = blockNumbers.filter { !$0.isPreset }
        blockNumbers = customNumbers + PresetNumbers.presetNumbers
        saveAll()
        reloadExtension()
        markPresetVersion()
    }

    // MARK: - Number Management

    func addNumber(_ number: String, label: String, group: String = "自定义", isPrefix: Bool = false) {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 检查是否已存在
        if blockNumbers.contains(where: { $0.number == trimmed }) { return }

        let item = BlockNumber(number: trimmed, label: label, group: group, isPrefix: isPrefix)
        blockNumbers.append(item)

        // 同时创建拦截记录
        let record = BlockRecord(number: trimmed, label: label.isEmpty ? "自定义号码" : label)
        blockRecords.insert(record, at: 0)
        if blockRecords.count > 500 {
            blockRecords = Array(blockRecords.prefix(500))
        }

        saveAll()
        appGroup.saveBlockRecords(blockRecords)
        reloadExtension()
    }

    func removeNumber(_ number: BlockNumber) {
        blockNumbers.removeAll { $0.id == number.id }
        saveAll()
        reloadExtension()
    }

    func removeNumbers(at offsets: IndexSet) {
        blockNumbers.remove(atOffsets: offsets)
        saveAll()
        reloadExtension()
    }

    func togglePrefix(for number: BlockNumber) {
        if let index = blockNumbers.firstIndex(where: { $0.id == number.id }) {
            blockNumbers[index].isPrefix.toggle()
            saveAll()
            reloadExtension()
        }
    }

    // MARK: - Preset Management

    func resetToPresets() {
        let customNumbers = blockNumbers.filter { !$0.isPreset }
        blockNumbers = customNumbers + PresetNumbers.presetNumbers
        saveAll()
        reloadExtension()
        markPresetVersion()
    }

    func removePresetNumbers() {
        let customNumbers = blockNumbers.filter { !$0.isPreset }
        blockNumbers = customNumbers
        saveAll()
        reloadExtension()
    }

    // MARK: - Records

    func clearRecords() {
        blockRecords = []
        appGroup.saveBlockRecords(blockRecords)
    }

    var todayBlockCount: Int {
        let calendar = Calendar.current
        return blockRecords.filter { calendar.isDateInToday($0.blockedAt) }.count
    }

    var totalBlockCount: Int {
        blockRecords.count
    }

    // MARK: - Groups

    var groups: [(name: String, count: Int)] {
        let grouped = Dictionary(grouping: blockNumbers) { $0.group }
        return grouped.map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    func numbersInGroup(_ group: String) -> [BlockNumber] {
        blockNumbers.filter { $0.group == group }
    }

    // MARK: - Private

    private func saveAll() {
        appGroup.saveBlockNumbers(blockNumbers)
    }

    func reloadExtension() {
        CXCallDirectoryManager.sharedInstance.reloadExtension(
           withIdentifier: "com.callshield.CallShield.CallDirectory"
        ) { error in
            if let error = error {
                print("Reload extension 失败: \(error)")
            } else {
                print("Reload extension 成功")
            }
        }
    }
}

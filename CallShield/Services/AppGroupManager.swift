import Foundation

class AppGroupManager {
    static let shared = AppGroupManager()

    let appGroupIdentifier = "group.com.callshield.RH6MHK8BB6.shared"

    var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    // MARK: - Numbers Data

    private var numbersFileURL: URL? {
        sharedContainerURL?.appendingPathComponent("blockNumbers.json")
    }

    func saveBlockNumbers(_ numbers: [BlockNumber]) {
        guard let url = numbersFileURL else { return }
        do {
            let data = try JSONEncoder().encode(numbers)
            try data.write(to: url, options: .atomicWrite)
            // 通知 Extension 重新加载数据
            sharedDefaults?.set(Date(), forKey: "numbersUpdatedTime")
            notifyExtensionReload()
        } catch {
            print("保存拦截号码失败: \(error)")
        }
    }

    func loadBlockNumbers() -> [BlockNumber] {
        guard let url = numbersFileURL else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([BlockNumber].self, from: data)
        } catch {
            print("加载拦截号码失败: \(error)")
            return []
        }
    }

    /// 数据文件是否存在（区分"从未写入过"和"写入后为空"）
    var hasDataFile: Bool {
        guard let url = numbersFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Block Records

    private var recordsFileURL: URL? {
        sharedContainerURL?.appendingPathComponent("blockRecords.json")
    }

    func saveBlockRecords(_ records: [BlockRecord]) {
        guard let url = recordsFileURL else { return }
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: .atomicWrite)
        } catch {
            print("保存拦截记录失败: \(error)")
        }
    }

    func loadBlockRecords() -> [BlockRecord] {
        guard let url = recordsFileURL else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([BlockRecord].self, from: data)
        } catch {
            return []
        }
    }

    func addBlockRecord(number: String, label: String) {
        var records = loadBlockRecords()
        let record = BlockRecord(number: number, label: label)
        records.insert(record, at: 0)
        // 只保留最近 500 条记录
        if records.count > 500 {
            records = Array(records.prefix(500))
        }
        saveBlockRecords(records)
    }

    // MARK: - Extension Reload

    private func notifyExtensionReload() {
        // 通过改变 UserDefaults 触发 Extension 重新加载
        sharedDefaults?.set(true, forKey: "needsReload")
    }

    // MARK: - Settings

    var isBlockEnabled: Bool {
        get { sharedDefaults?.object(forKey: "isBlockEnabled") as? Bool ?? true }
        set { sharedDefaults?.set(newValue, forKey: "isBlockEnabled") }
    }
}

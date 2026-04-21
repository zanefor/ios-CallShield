import Foundation
import CallKit

/// 拦截验证服务
///
/// 由于 iOS 系统限制：
/// - CallKit 拦截来电时不会回调 App
/// - CXCallObserver 可以监听来电状态但不提供号码
/// - 无法直接获取"被拦截了多少来电"的统计数据
///
/// 可行的验证方案：
/// 1. 检查 Extension 是否被系统启用（getEnabledStatusForExtension）
/// 2. 检查数据完整性（数据是否正确写入 App Group）
/// 3. 检查 Extension 最后加载时间（验证退出 App 后是否仍被系统唤起）
/// 4. 检查 Extension 是否有过错误（帮助排查问题）
/// 5. 提供"拦截测试"指引（用另一台电话拨打验证）
class BlockCheckService: ObservableObject {
    static let shared = BlockCheckService()

    @Published var extensionStatus: ExtensionStatus = .unknown
    @Published var dataCheckResult: DataCheckResult?
    @Published var extensionRuntimeInfo: ExtensionRuntimeInfo?
    @Published var isChecking = false

    enum ExtensionStatus {
        case unknown
        case enabled       // Extension 已启用
        case disabled      // Extension 未启用
        case notFound      // Extension 未找到
        case checking
    }

    struct DataCheckResult {
        let totalRules: Int
        let exactRules: Int
        let prefixRules: Int
        let presetRules: Int
        let customRules: Int
        let estimatedExpandedNumbers: Int
        let dataFileSize: Int64
        let isDataAccessible: Bool
        let lastUpdated: Date?
    }

    /// Extension 运行时信息（从 App Group UserDefaults 读取）
    struct ExtensionRuntimeInfo {
        let lastLoadTime: Date?          // Extension 最后一次被系统唤起的时间
        let lastErrorTime: Date?         // 最后一次错误时间
        let lastErrorMessage: String?    // 最后一次错误信息
        let hasRecentLoad: Bool          // 是否有最近的加载记录
        let hasError: Bool               // 是否有未处理的错误
    }

    private let extensionIdentifier = "com.callshield.CallShield.CallDirectory"
    private let appGroup = AppGroupManager.shared

    // MARK: - Extension 启用状态检查

    func checkExtensionStatus() {
        extensionStatus = .checking

        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
            withIdentifier: extensionIdentifier
        ) { [weak self] status, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("BlockCheck: 检查 Extension 状态失败: \(error)")
                    self?.extensionStatus = .notFound
                } else {
                    switch status {
                    case .enabled:
                        self?.extensionStatus = .enabled
                    case .disabled:
                        self?.extensionStatus = .disabled
                    case .unknown:
                        self?.extensionStatus = .unknown
                    @unknown default:
                        self?.extensionStatus = .unknown
                    }
                }
            }
        }
    }

    // MARK: - 数据完整性检查

    func checkDataIntegrity() {
        isChecking = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let numbers = self.appGroup.loadBlockNumbers()
            let exactRules = numbers.filter { !$0.isPrefix }.count
            let prefixRules = numbers.filter { $0.isPrefix }.count
            let presetRules = numbers.filter { $0.isPreset }.count
            let customRules = numbers.filter { !$0.isPreset }.count

            // 估算展开后的号码数量（与 CallDirectoryHandler 逻辑一致）
            // padCount 最大为3，每个前缀最多 1000 条
            let budget = 50_000
            var estimatedCount = min(exactRules * 2, budget) // 精确号码可能生成2种格式
            var remaining = budget - estimatedCount
            // 按前缀长度降序估算
            let sortedPrefixes = numbers.filter { $0.isPrefix }
                .map { $0.number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
            for prefix in sortedPrefixes {
                guard remaining > 0 else { break }
                let perPrefix = min(1000, remaining) // padCount 最大3
                estimatedCount += perPrefix
                remaining -= perPrefix
            }

            // 检查数据文件大小
            var fileSize: Int64 = 0
            var lastUpdated: Date?
            if let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: self.appGroup.appGroupIdentifier) {
                let fileURL = containerURL.appendingPathComponent("blockNumbers.json")
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int64 {
                    fileSize = size
                }
                lastUpdated = self.appGroup.sharedDefaults?.object(forKey: "numbersUpdatedTime") as? Date
            }

            let result = DataCheckResult(
                totalRules: numbers.count,
                exactRules: exactRules,
                prefixRules: prefixRules,
                presetRules: presetRules,
                customRules: customRules,
                estimatedExpandedNumbers: estimatedCount,
                dataFileSize: fileSize,
                isDataAccessible: !numbers.isEmpty,
                lastUpdated: lastUpdated
            )

            DispatchQueue.main.async {
                self.dataCheckResult = result
                self.isChecking = false
            }
        }
    }

    // MARK: - 完整检查

    func runFullCheck() {
        checkExtensionStatus()
        checkDataIntegrity()
        checkExtensionRuntime()
    }

    // MARK: - Extension 运行时状态检查

    /// 检查 Extension 的运行时信息
    /// 关键：如果 lastLoadTime 存在且是最近的，说明系统在来电时会唤起 Extension
    /// 即使主 App 已退出，Extension 也能正常工作
    func checkExtensionRuntime() {
        let defaults = appGroup.sharedDefaults

        let lastLoadTime = defaults?.object(forKey: "lastExtensionLoadTime") as? Date
        let lastErrorTime = defaults?.object(forKey: "lastExtensionErrorTime") as? Date
        let lastErrorMessage = defaults?.object(forKey: "lastExtensionErrorMessage") as? String

        // 判断是否有"最近的"加载记录（30天内）
        let hasRecentLoad: Bool
        if let loadTime = lastLoadTime {
            hasRecentLoad = Date().timeIntervalSince(loadTime) < 30 * 24 * 3600
        } else {
            hasRecentLoad = false
        }

        let hasError = lastErrorTime != nil

        let info = ExtensionRuntimeInfo(
            lastLoadTime: lastLoadTime,
            lastErrorTime: lastErrorTime,
            lastErrorMessage: lastErrorMessage,
            hasRecentLoad: hasRecentLoad,
            hasError: hasError
        )

        DispatchQueue.main.async { [weak self] in
            self?.extensionRuntimeInfo = info
        }
    }

    /// 清除 Extension 错误记录（在主 App 处理完错误后调用）
    func clearExtensionError() {
        appGroup.sharedDefaults?.removeObject(forKey: "lastExtensionErrorTime")
        appGroup.sharedDefaults?.removeObject(forKey: "lastExtensionErrorMessage")
        checkExtensionRuntime()
    }

    // MARK: - 重新加载 Extension

    func reloadExtension() {
        CXCallDirectoryManager.sharedInstance.reloadExtension(
            withIdentifier: extensionIdentifier
        ) { error in
            if let error = error {
                print("BlockCheck: 重新加载 Extension 失败: \(error)")
            } else {
                print("BlockCheck: 重新加载 Extension 成功")
            }
        }
    }
}

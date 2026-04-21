import Foundation
import CallKit

class CallDirectoryHandler: CXCallDirectoryProvider {

    // ============================================================
    // CallKit 拦截方案（v12 — 首位号段+无maxPad限制）
    // ============================================================
    //
    // ★★★ 根本性策略变更 ★★★
    //
    // CallKit只支持精确匹配（addBlockingEntry），无前缀/通配符匹配
    // 座机8位号需要pad=8(1亿条/区号)才能全覆盖——4M预算不可能
    //
    // 新策略：按骚扰高发首位号段展开
    // 座机首位3/5/6/8是商业办公号段，骚扰电话集中
    // PresetNumbers提供 区号+首位(如0203) 作为前缀
    // 前缀4位(2位区号)或5位(3位区号) + pad=7或6 ≈ 100万条/前缀
    //
    // ★ 关键：去掉maxPad限制，让预算自然截断 ★
    // 4M预算 / (326区号×4首位×2格式=2608组合) ≈ 1535条/组合
    // 每组合1535条 → 覆盖首位号段的前1535个号码
    // 虽然不能全覆盖(需1百万)，但比区号级pad≤3覆盖更精准
    //
    // 双格式：本地格式(02032445445) + E.164格式(862032445445)
    // 确保无论iOS用哪种格式匹配都能拦截
    // ============================================================

    private let appGroupIdentifier = "group.com.callshield.RH6MHK8BB6.shared"
    private let extensionIdentifier = "com.callshield.CallShield.CallDirectory"

    // 预算：4,000,000 条（约 31MB）
    // 326区号 × 4首位 × 2格式 = 2608组合
    // 每组合约1535条，自然截断
    private let totalBudget = 4_000_000

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        do {
            let count = try loadAndAddNumbers(context: context)
            recordSuccess(count: count)
            print("CallDirectory: 成功加载 \(count) 个拦截号码")
        } catch {
            recordError(error)
            print("CallDirectory beginRequest 异常: \(error)")
        }

        context.completeRequest()
    }

    // MARK: - 核心加载逻辑

    private func loadAndAddNumbers(context: CXCallDirectoryExtensionContext) throws -> Int {
        let numbers = try loadBlockNumbers()

        let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        let isEnabled = sharedDefaults?.object(forKey: "isBlockEnabled") as? Bool ?? true
        if !isEnabled {
            print("CallDirectory: 拦截已关闭")
            return 0
        }

        var allNumbers = Set<Int64>()
        var budget = totalBudget

        // 精确匹配优先
        let exactItems = numbers.filter { !$0.isPrefix }
        for item in exactItems {
            guard budget > 0 else { break }
            let intNums = phoneNumberToInt64(item.number)
            for num in intNums where num > 0 {
                if !allNumbers.contains(num) && budget > 0 {
                    allNumbers.insert(num)
                    budget -= 1
                }
            }
        }

        // 前缀匹配 - 按区号+首位排序，021优先
        let prefixItems = numbers.filter { $0.isPrefix }

        let twoDigitSet: Set<String> = ["010","020","021","022","023","024","025","027","028","029"]
        func areaCode(of number: String) -> String {
            let d = extractDigits(number)
            if d.count >= 3 && twoDigitSet.contains(String(d.prefix(3))) {
                return String(d.prefix(3))
            } else if d.count >= 4 {
                return String(d.prefix(4))
            }
            return d
        }

        let sortedPrefixItems = prefixItems.sorted { a, b in
            let acA = areaCode(of: a.number)
            let acB = areaCode(of: b.number)
            if acA == "021" { return true }
            if acB == "021" { return false }
            return acA < acB
        }

        for item in sortedPrefixItems {
            guard budget > 0 else { break }
            let expanded = expandPrefixToNumbers(item.number, budget: &budget)
            for num in expanded where num > 0 {
                if !allNumbers.contains(num) && budget > 0 {
                    allNumbers.insert(num)
                    budget -= 1
                } else if !allNumbers.contains(num) {
                    break
                }
            }
        }

        let sortedNumbers = allNumbers.sorted()

        var addedCount = 0
        for phoneNumber in sortedNumbers {
            do {
                try context.addBlockingEntry(withNextSequentialPhoneNumber: phoneNumber)
                addedCount += 1
            } catch {
                print("CallDirectory: addBlockingEntry 失败 at \(phoneNumber): \(error)")
                break
            }
        }

        return addedCount
    }

    // MARK: - 号码格式转换（精确匹配）

    /// 座机号同时生成本地格式和E.164格式
    /// iOS不一定将来电号码规范化为E.164！必须两种都覆盖
    private func phoneNumberToInt64(_ number: String) -> [Int64] {
        let digits = extractDigits(number)
        guard !digits.isEmpty else { return [] }

        var results = [Int64]()

        if digits.hasPrefix("1") && digits.count == 11 {
            if let num = Int64("86" + digits) { results.append(num) }
        } else if digits.hasPrefix("0") && digits.count >= 3 {
            // 座机号：同时生成两种格式
            if let num = Int64(digits) { results.append(num) }
            let without0 = String(digits.dropFirst())
            if let num = Int64("86" + without0) { results.append(num) }
        } else if digits.hasPrefix("400") || digits.hasPrefix("800") {
            if let num = Int64(digits) { results.append(num) }
        } else if digits.hasPrefix("95") {
            if let num = Int64(digits) { results.append(num) }
        } else if digits.hasPrefix("106") {
            if let num = Int64(digits) { results.append(num) }
        } else {
            if let num = Int64("86" + digits) { results.append(num) }
            if let num = Int64(digits) { results.append(num) }
        }

        return results.filter { $0 > 0 }
    }

    // MARK: - 前缀展开

    private func expandPrefixToNumbers(_ prefix: String, budget: inout Int) -> [Int64] {
        let digits = extractDigits(prefix)
        guard !digits.isEmpty else { return [] }

        if digits.hasPrefix("1") && digits.count >= 3 {
            return expandMobilePrefix(digits, budget: &budget)
        } else if digits.hasPrefix("0") {
            return expandLandlinePrefix(digits, budget: &budget)
        } else if digits.hasPrefix("400") || digits.hasPrefix("800") {
            return expandTollFreePrefix(digits, budget: &budget)
        } else if digits.hasPrefix("95") {
            return expand95Prefix(digits, budget: &budget)
        } else if digits.hasPrefix("106") {
            return expand106Prefix(digits, budget: &budget)
        } else {
            return expandGenericPrefix(digits, budget: &budget)
        }
    }

    private func expandMobilePrefix(_ digits: String, budget: inout Int) -> [Int64] {
        let e164Prefix = "86" + digits
        let totalLen = 13
        let padCount = totalLen - e164Prefix.count
        guard padCount > 0 else {
            if let num = Int64(e164Prefix), num > 0, budget > 0 {
                budget -= 1; return [num]
            }
            return []
        }
        return expandRange(prefix: e164Prefix, padCount: padCount, budget: &budget)
    }

    // ★★★ 座机号前缀展开 — v12 首位号段+无maxPad限制 ★★★
    //
    // 前缀是区号+首位(如0203/0216/07553)
    // 目标：8位座机号 = 区号(2-3位) + 8位号码
    // 本地格式总长：2位区号+8位=11位, 3位区号+8位=12位
    // E.164格式总长：86+2位区号(去0)+8位=12位, 86+3位区号(去0)+8位=13位
    //
    // ★ 无maxPad限制，让预算自然截断 ★
    // 每前缀大约能分到1535条(4M/2608组合)
    // 覆盖首位号段的前1535个号码
    private func expandLandlinePrefix(_ digits: String, budget: inout Int) -> [Int64] {
        var results = [Int64]()
        // ★ 不限制maxPad，让预算自然截断

        // 确定区号长度
        let areaCodeLen: Int
        if digits.hasPrefix("010") || digits.hasPrefix("020") || digits.hasPrefix("021") ||
           digits.hasPrefix("022") || digits.hasPrefix("023") || digits.hasPrefix("024") ||
           digits.hasPrefix("025") || digits.hasPrefix("027") || digits.hasPrefix("028") ||
           digits.hasPrefix("029") {
            areaCodeLen = 2
        } else {
            areaCodeLen = 3
        }

        let without0 = String(digits.dropFirst())
        let e164Prefix = "86" + without0

        // ① 本地格式展开
        // 2位区号8位座机: (1+2)+8=11位本地格式
        // 3位区号8位座机: (1+3)+8=12位本地格式
        if budget > 0 {
            let targetLen8_local = 1 + areaCodeLen + 8
            let pad8_local = targetLen8_local - digits.count
            if pad8_local > 0 {
                results.append(contentsOf: expandRange(prefix: digits, padCount: pad8_local, budget: &budget))
            } else if pad8_local == 0, budget > 0, let num = Int64(digits), num > 0 {
                results.append(num); budget -= 1
            }
        }

        // ② E.164格式展开
        // 2位区号8位座机: 2+2+8=12位E.164
        // 3位区号8位座机: 2+3+8=13位E.164
        if budget > 0 {
            let targetLen8_e164 = 2 + areaCodeLen + 8
            let pad8_e164 = targetLen8_e164 - e164Prefix.count
            if pad8_e164 > 0 {
                results.append(contentsOf: expandRange(prefix: e164Prefix, padCount: pad8_e164, budget: &budget))
            } else if pad8_e164 == 0, budget > 0, let num = Int64(e164Prefix), num > 0 {
                results.append(num); budget -= 1
            }
        }

        return results
    }

    private func expandTollFreePrefix(_ digits: String, budget: inout Int) -> [Int64] {
        let padCount = 10 - digits.count
        guard padCount > 0 else {
            if let num = Int64(digits), num > 0, budget > 0 { budget -= 1; return [num] }
            return []
        }
        return expandRange(prefix: digits, padCount: padCount, budget: &budget)
    }

    private func expand95Prefix(_ digits: String, budget: inout Int) -> [Int64] {
        var results = [Int64]()
        for targetLen in [5, 6, 7, 8] {
            guard budget > 0 else { break }
            let padCount = targetLen - digits.count
            if padCount > 0 {
                results.append(contentsOf: expandRange(prefix: digits, padCount: padCount, budget: &budget))
            } else if padCount == 0, budget > 0, let num = Int64(digits), num > 0 {
                results.append(num); budget -= 1
            }
        }
        return results
    }

    private func expand106Prefix(_ digits: String, budget: inout Int) -> [Int64] {
        var results = [Int64]()
        for targetLen in [10, 11, 12] {
            guard budget > 0 else { break }
            let padCount = targetLen - digits.count
            if padCount > 0 {
                results.append(contentsOf: expandRange(prefix: digits, padCount: padCount, budget: &budget))
            } else if padCount == 0, budget > 0, let num = Int64(digits), num > 0 {
                results.append(num); budget -= 1
            }
        }
        return results
    }

    private func expandGenericPrefix(_ digits: String, budget: inout Int) -> [Int64] {
        let padCount = min(max(11 - digits.count, 1), 3)
        return expandRange(prefix: digits, padCount: padCount, budget: &budget)
    }

    // MARK: - 区间展开核心

    private func expandRange(prefix: String, padCount: Int, budget: inout Int) -> [Int64] {
        guard padCount > 0, budget > 0 else { return [] }
        guard let prefixVal = Int64(prefix), prefixVal > 0 else { return [] }

        let count = min(pow10(padCount), budget)
        guard count > 0 else { return [] }

        let multiplier = Int64(pow10(padCount))
        guard prefixVal <= Int64.max / multiplier else { return [] }

        let baseNumber = prefixVal * multiplier
        guard baseNumber > 0 else { return [] }

        var results = [Int64]()
        results.reserveCapacity(min(count, 1000))

        for i in 0..<count {
            let num = baseNumber + Int64(i)
            guard num > 0, num >= baseNumber else { break }
            results.append(num)
        }

        budget -= results.count
        return results
    }

    // MARK: - 数据加载

    private func loadBlockNumbers() throws -> [BlockNumber] {
        guard let sharedContainerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ExtensionError.containerNotFound
        }

        let numbersFileURL = sharedContainerURL.appendingPathComponent("blockNumbers.json")

        guard FileManager.default.fileExists(atPath: numbersFileURL.path) else {
            print("CallDirectory: 数据文件不存在")
            return []
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: numbersFileURL.path),
           let fileSize = attrs[.size] as? Int64 {
            if fileSize > 50 * 1024 * 1024 { throw ExtensionError.dataTooLarge }
            if fileSize == 0 { return [] }
        }

        let data: Data
        do {
            data = try Data(contentsOf: numbersFileURL)
        } catch {
            throw ExtensionError.fileReadFailed
        }

        do {
            return try JSONDecoder().decode([BlockNumber].self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: numbersFileURL)
            throw ExtensionError.dataCorrupted
        }
    }

    // MARK: - 状态记录

    private func recordSuccess(count: Int) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(Date(), forKey: "lastExtensionLoadTime")
        defaults?.set(count, forKey: "lastExtensionLoadCount")
        defaults?.set(nil, forKey: "lastExtensionErrorTime")
        defaults?.set(nil, forKey: "lastExtensionErrorMessage")
    }

    private func recordError(_ error: Error) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(Date(), forKey: "lastExtensionErrorTime")
        defaults?.set(error.localizedDescription, forKey: "lastExtensionErrorMessage")
    }

    // MARK: - 工具方法

    private func extractDigits(_ input: String) -> String {
        input.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    private func pow10(_ n: Int) -> Int {
        guard n >= 0 else { return 0 }
        guard n <= 9 else { return 1_000_000_000 }
        var result = 1
        for _ in 0..<n { result *= 10 }
        return result
    }
}

// MARK: - 错误类型

extension CallDirectoryHandler {
    enum ExtensionError: LocalizedError {
        case containerNotFound
        case fileReadFailed
        case dataCorrupted
        case dataTooLarge

        var errorDescription: String? {
            switch self {
            case .containerNotFound: return "App Group 容器不可访问"
            case .fileReadFailed: return "号码数据文件读取失败"
            case .dataCorrupted: return "号码数据已损坏"
            case .dataTooLarge: return "号码数据文件过大"
            }
        }
    }
}

// MARK: - CXCallDirectoryExtensionContextDelegate

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        print("CallDirectory request 失败: \(error)")
        let defaults = UserDefaults(suiteName: "group.com.callshield.RH6MHK8BB6.shared")
        defaults?.set(Date(), forKey: "lastExtensionErrorTime")
        defaults?.set("requestFailed: \(error.localizedDescription)", forKey: "lastExtensionErrorMessage")
    }
}

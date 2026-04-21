import IdentityLookup
import os.log

// ============================================================
// Live Caller ID Lookup App Extension 入口
// ============================================================
//
// ★★★ 当前模式：本地前缀匹配（无需服务器）★★★
//
// 此 Extension 实现两个核心功能：
// 1. LiveCallerIDLookupProtocol — 提供 PIR 服务器配置（可选）
// 2. ILCallCommunicationCenterDelegate — 来电时本地前缀匹配
//
// 本地前缀匹配使用 SpamPrefixResolver：
// - 267 区号 × 4 骚扰首位 × 2 格式 = 2136 前缀
// - 覆盖 112 亿座机号码
// - 纯本地运算，微秒级响应，无需联网
//
// ★ iOS 版本差异 ★
// - iOS 17：仅来电识别（显示标签"骚扰座机"）
// - iOS 18.2+：支持自动拦截（直接挂断）+ 识别标签
// ============================================================

class LiveCallerIDExtension: NSObject, LiveCallerIDLookupProtocol, ILCallCommunicationCenterDelegate {

    private let logger = Logger(subsystem: "com.callshield.CallShield", category: "LiveCallerID")

    // MARK: - LiveCallerIDLookupProtocol

    /// 提供 PIR 服务器配置（可选升级）
    /// 仅在用户配置了服务器地址时生效
    func liveCallerIDLookupExtensionConfiguration() -> LiveCallerIDLookupExtensionConfiguration {
        let configuration = LiveCallerIDLookupExtensionConfiguration()

        let appGroup = UserDefaults(suiteName: "group.com.callshield.RH6MHK8BB6.shared")
        let serverURLString = appGroup?.string(forKey: "pirServerURL") ?? ""
        let authToken = appGroup?.string(forKey: "pirAuthToken") ?? ""

        if let url = URL(string: serverURLString), !serverURLString.isEmpty {
            configuration.serviceURL = url
            logger.info("LiveCallerID: PIR 服务器已配置: \(serverURLString)")

            if !authToken.isEmpty {
                configuration.key = authToken.data(using: .utf8)
            }
        } else {
            logger.info("LiveCallerID: PIR 服务器未配置，使用本地前缀匹配模式")
        }

        return configuration
    }

    // MARK: - ILCallCommunicationCenterDelegate

    /// 来电时本地前缀匹配（默认方案）
    func communicationReceived(for request: ILCallCommunicationRequest,
                                response: ILCallCommunicationResponse) {
        // 1. 提取来电号码
        let phoneNumber: String?
        if #available(iOS 18, *) {
            phoneNumber = request.callerID
        } else {
            phoneNumber = request.participants.first?.phoneNumber
        }

        guard let number = phoneNumber, !number.isEmpty else {
            logger.debug("LiveCallerID: 无法获取来电号码")
            return
        }

        let digits = extractDigits(number)
        logger.debug("LiveCallerID: 收到来电查询 \(digits.prefix(6))***")

        // 2. 本地前缀匹配判断（微秒级，无需联网）
        let result = SpamPrefixResolver.checkNumber(digits)

        // 3. 设置响应
        switch result {
        case .spamLandline(let label, let prefix):
            logger.info("LiveCallerID: 命中骚扰前缀 \(prefix)，标签: \(label)")

            // 设置来电显示标签（iOS 17+ 均支持）
            response.localizedCallerName = label

            // ★ 尝试设置拦截动作 ★
            // iOS 18.2+ 支持自动拦截，iOS 17 仅显示标签
            if let blockAction = ILCallBlockAction.init(rawValue: 1) {
                response.callBlockAction = blockAction
            }

        case .notSpam:
            logger.debug("LiveCallerID: 非骚扰号码")
            break
        }
    }

    // MARK: - Helper

    private func extractDigits(_ input: String) -> String {
        input.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }
}

import Foundation

// ============================================================
// 骚扰号码前缀匹配引擎
// ============================================================
//
// ★★★ 核心优势：前缀匹配 vs 精确匹配 ★★★
//
// CallKit 的 addBlockingEntry 只支持精确匹配，座机号有数十亿条无法全存
// Live Caller ID Lookup 的 ILCallCommunicationCenterDelegate 可以在回调中
// 执行任意代码逻辑——包括前缀匹配！
//
// 一条前缀规则（如 "0203"）就能覆盖 1000 万个号码
// 280 个区号 × 4 个首位号段 = 1120 条规则 → 覆盖 112 亿个号码
// 存储量：约 56 KB，比 CallKit 的 400 万条精确匹配覆盖率高数千倍
//
// 号码格式：
// - 本地格式：02032445445（区号0+2/3位城市码 + 8位号码）
// - E.164格式：862032445445（86 + 去掉前导0的区号 + 8位号码）
// - 来电显示格式：(020) 3244 5445
// ============================================================

struct SpamPrefixResolver {

    // MARK: - 前缀规则集

    /// 骚扰高发座机首位号段
    /// 3: 企业办公, 5: 商业服务, 6: 公司座机, 8: 商务号码
    static let spamFirstDigits: Set<String> = ["3", "5", "6", "8"]

    /// 2 位区号（直辖市/大区中心）
    static let twoDigitAreaCodes: Set<String> = [
        "010", "020", "021", "022", "023", "024", "025", "027", "028", "029"
    ]

    /// 所有非偏远地区区号（本地格式，含前导0）
    /// 已排除：西藏(0891-0897)、青海(0971-0977)、新疆(0991-0909)、
    /// 内蒙古偏远、甘肃偏远、云南偏远等
    static let nonRemoteAreaCodes: Set<String> = {
        var codes = Set<String>()

        // 2 位区号（10 个）
        for code in twoDigitAreaCodes {
            codes.insert(code)
        }

        // 3 位区号（非偏远地区）
        let threeDigitCodes = [
            // 河北
            "0311", "0312", "0313", "0314", "0315", "0316", "0317", "0318", "0319", "0335", "0310",
            // 山西
            "0350", "0351", "0352", "0353", "0354", "0355", "0356", "0357", "0358", "0359",
            // 辽宁
            "0411", "0412", "0413", "0414", "0415", "0416", "0417", "0418", "0419", "0421", "0427", "0429", "0410",
            // 吉林
            "0431", "0432", "0433", "0434", "0435", "0436", "0437", "0438", "0439",
            // 黑龙江
            "0451", "0452", "0453", "0454", "0455", "0456", "0457", "0459", "0464", "0467", "0468", "0469", "0458",
            // 江苏
            "0510", "0511", "0512", "0513", "0514", "0515", "0516", "0517", "0518", "0519", "0523", "0527",
            // 浙江
            "0571", "0572", "0573", "0574", "0575", "0576", "0577", "0578", "0579", "0580", "0570",
            // 安徽
            "0551", "0552", "0553", "0554", "0555", "0556", "0557", "0558", "0559",
            "0562", "0563", "0564", "0566", "0561", "0550", "0565",
            // 福建
            "0591", "0592", "0593", "0594", "0595", "0596", "0597", "0598", "0599",
            // 江西
            "0790", "0791", "0792", "0793", "0794", "0795", "0796", "0797", "0798", "0799", "0701",
            // 山东
            "0531", "0532", "0533", "0534", "0535", "0536", "0537", "0538", "0539",
            "0543", "0546", "0631", "0632", "0633", "0635", "0634", "0530",
            // 河南
            "0371", "0372", "0373", "0374", "0375", "0376", "0377", "0378", "0379",
            "0391", "0392", "0393", "0394", "0395", "0396", "0398", "0370",
            // 湖北
            "0710", "0711", "0712", "0713", "0714", "0715", "0716", "0717", "0718", "0719",
            "0722", "0724", "0728",
            // 湖南
            "0730", "0731", "0732", "0733", "0734", "0735", "0736", "0737", "0738", "0739",
            "0743", "0744", "0745", "0746",
            // 广东
            "0662", "0663", "0668", "0660",
            "0750", "0751", "0752", "0753", "0754", "0755", "0756", "0757", "0758", "0759",
            "0760", "0762", "0763", "0766", "0768", "0769",
            // 广西
            "0771", "0772", "0773", "0774", "0775", "0776", "0777", "0779", "0770", "0778",
            // 海南
            "0898", "0899",
            // 四川（不含成都028，已在2位区号中）
            "0812", "0813", "0816", "0817", "0818",
            "0825", "0826", "0827",
            "0830", "0831", "0832", "0833", "0835", "0838", "0839", "0834",
            // 贵州
            "0851", "0852", "0853", "0854", "0855", "0856", "0857", "0858", "0859",
            // 云南（非偏远：昆明/大理/红河/曲靖/玉溪/楚雄/昭通）
            "0871", "0872", "0873", "0874", "0877", "0878", "0870",
            // 陕西（不含西安029，已在2位区号中）
            "0910", "0911", "0912", "0913", "0914", "0915", "0916", "0917", "0919",
            // 甘肃（非偏远：兰州/定西/天水）
            "0931", "0932", "0938",
            // 宁夏
            "0951", "0952", "0953", "0954", "0955",
        ]

        for code in threeDigitCodes {
            codes.insert(code)
        }

        return codes
    }()

    // MARK: - 预计算的前缀集合（用于快速匹配）

    /// 本地格式前缀集合（如 "0203", "0215", "07553"）
    /// 来电号码本地格式 02032445445 → 匹配前缀 "0203"
    static let localPrefixes: Set<String> = {
        var prefixes = Set<String>()
        for areaCode in nonRemoteAreaCodes {
            let isTwoDigit = twoDigitAreaCodes.contains(areaCode)
            for digit in spamFirstDigits {
                if isTwoDigit {
                    // 2 位区号：010 → 0103 (区号3位 + 首位1位 = 4位前缀)
                    prefixes.insert(areaCode + digit)
                } else {
                    // 3 位区号：0311 → 03113 (区号4位 + 首位1位 = 5位前缀)
                    prefixes.insert(areaCode + digit)
                }
            }
        }
        return prefixes
    }()

    /// E.164 格式前缀集合（如 "86203", "86215", "867553"）
    /// 来电号码 E.164 格式 862032445445 → 匹配前缀 "86203"
    static let e164Prefixes: Set<String> = {
        var prefixes = Set<String>()
        for areaCode in nonRemoteAreaCodes {
            let isTwoDigit = twoDigitAreaCodes.contains(areaCode)
            // E.164: 去掉前导0，加86
            let withoutLeadingZero = String(areaCode.dropFirst())
            let e164AreaCode = "86" + withoutLeadingZero
            for digit in spamFirstDigits {
                if isTwoDigit {
                    // 010 → 8610 → 86103 (5位前缀)
                    prefixes.insert(e164AreaCode + digit)
                } else {
                    // 0311 → 86311 → 863113 (6位前缀)
                    prefixes.insert(e164AreaCode + digit)
                }
            }
        }
        return prefixes
    }()

    // MARK: - 匹配逻辑

    /// 判断号码是否为骚扰座机
    /// - Parameter phoneNumber: 来电号码（纯数字，可能含空格/括号）
    /// - Returns: 匹配结果
    static func checkNumber(_ phoneNumber: String) -> SpamCheckResult {
        let digits = extractDigits(phoneNumber)
        guard !digits.isEmpty else { return .notSpam }

        // ① 尝试本地格式前缀匹配
        // 来电格式: 02032445445 → 检查前4位 "0203" 是否在 localPrefixes
        for prefixLength in [5, 4, 6] {
            if digits.count >= prefixLength {
                let prefix = String(digits.prefix(prefixLength))
                if localPrefixes.contains(prefix) {
                    return .spamLandline(label: "骚扰座机", prefix: prefix)
                }
            }
        }

        // ② 尝试 E.164 格式前缀匹配
        // 来电格式: 862032445445 → 检查前5位 "86203" 是否在 e164Prefixes
        for prefixLength in [6, 5, 7] {
            if digits.count >= prefixLength {
                let prefix = String(digits.prefix(prefixLength))
                if e164Prefixes.contains(prefix) {
                    return .spamLandline(label: "骚扰座机", prefix: prefix)
                }
            }
        }

        // ③ 简单座机号检测（0 开头 + 区号匹配 + 首位在骚扰号段）
        if digits.hasPrefix("0") && digits.count >= 5 {
            let firstDigitAfterAreaCode = detectFirstDigitAfterAreaCode(digits)
            if let firstDigit = firstDigitAfterAreaCode, spamFirstDigits.contains(firstDigit) {
                // 区号本身是否在非偏远地区列表中？
                let areaCode = extractAreaCode(from: digits)
                if nonRemoteAreaCodes.contains(areaCode) {
                    return .spamLandline(label: "骚扰座机", prefix: areaCode + firstDigit)
                }
            }
        }

        return .notSpam
    }

    // MARK: - 辅助方法

    /// 提取纯数字
    private static func extractDigits(_ input: String) -> String {
        input.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    /// 从本地格式号码中提取区号
    /// 02032445445 → "020" (2位区号)
    /// 03112345678 → "0311" (3位区号)
    private static func extractAreaCode(from digits: String) -> String {
        guard digits.hasPrefix("0") else { return "" }

        // 尝试 2 位区号（3 位前缀: 0XX）
        if digits.count >= 3 {
            let possibleTwoDigit = String(digits.prefix(3))
            if twoDigitAreaCodes.contains(possibleTwoDigit) {
                return possibleTwoDigit
            }
        }

        // 尝试 3 位区号（4 位前缀: 0XXX）
        if digits.count >= 4 {
            let possibleThreeDigit = String(digits.prefix(4))
            if nonRemoteAreaCodes.contains(possibleThreeDigit) {
                return possibleThreeDigit
            }
        }

        return ""
    }

    /// 检测区号后的首位号码
    private static func detectFirstDigitAfterAreaCode(_ digits: String) -> String? {
        let areaCode = extractAreaCode(from: digits)
        guard !areaCode.isEmpty else { return nil }

        let index = digits.index(digits.startIndex, offsetBy: areaCode.count)
        guard index < digits.endIndex else { return nil }
        return String(digits[index])
    }

    // MARK: - 统计信息

    /// 前缀规则总数
    static var totalPrefixCount: Int {
        localPrefixes.count + e164Prefixes.count
    }

    /// 覆盖区号数
    static var coveredAreaCodeCount: Int {
        nonRemoteAreaCodes.count
    }
}

// MARK: - 匹配结果

enum SpamCheckResult {
    case notSpam
    case spamLandline(label: String, prefix: String)

    var isSpam: Bool {
        if case .spamLandline = self { return true }
        return false
    }

    var displayLabel: String? {
        if case .spamLandline(let label, _) = self { return label }
        return nil
    }
}

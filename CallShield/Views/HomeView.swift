import SwiftUI

struct HomeView: View {
    @EnvironmentObject var blockManager: BlockManager
    @StateObject private var checkService = BlockCheckService.shared
    @State private var showPermissionAlert = false
    @State private var showTestSheet = false

    private var isBlockEnabled: Bool {
        AppGroupManager.shared.isBlockEnabled
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 拦截状态卡片
                    statusCard

                    // 拦截验证卡片
                    verificationCard

                    // 规则统计
                    statsSection

                    // 分组概览
                    groupOverview

                    // 快捷操作
                    quickActions
                }
                .padding()
            }
            .navigationTitle("来电护盾")
            .onAppear {
                checkService.runFullCheck()
            }
            .alert("需要开启权限", isPresented: $showPermissionAlert) {
                Button("去设置") {
                    openPhoneSettings()
                }
                Button("稍后", role: .cancel) {}
            } message: {
                Text("请在「设置 → 电话 → 来电阻止与身份识别」中开启「来电护盾拦截」")
            }
            .sheet(isPresented: $showTestSheet) {
                BlockTestView()
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isBlockEnabled ? [.blue.opacity(0.1), .blue.opacity(0.3)] : [.gray.opacity(0.1), .gray.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: isBlockEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 50))
                    .foregroundStyle(isBlockEnabled ? .blue : .gray)
            }

            Text(isBlockEnabled ? "拦截保护已开启" : "拦截保护已关闭")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(isBlockEnabled ? "正在守护您的来电安全" : "请在设置中开启来电拦截")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }

    // MARK: - Verification Card

    private var verificationCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(extensionStatusColor)
                Text("拦截验证")
                    .font(.headline)
                Spacer()
                if checkService.extensionStatus == .checking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(extensionStatusText)
                        .font(.caption.bold())
                        .foregroundStyle(extensionStatusColor)
                }
            }

            Divider()

            // Extension 状态
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("系统权限")
                        .font(.subheadline.bold())
                    Text(extensionStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(extensionStatusColor)
                    .frame(width: 12, height: 12)
            }

            // 数据完整性
            if let dataCheck = checkService.dataCheckResult {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("数据完整性")
                            .font(.subheadline.bold())
                        Text("\(dataCheck.totalRules) 条规则已加载")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(dataCheck.isDataAccessible ? .green : .red)
                        .frame(width: 12, height: 12)
                }
            }

            // Extension 运行状态（退出App后是否仍生效的关键指标）
            if let runtimeInfo = checkService.extensionRuntimeInfo {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("后台运行状态")
                            .font(.subheadline.bold())
                        if let lastLoad = runtimeInfo.lastLoadTime {
                            Text("上次响应: \(formatDate(lastLoad))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("等待首次来电触发")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Circle()
                        .fill(runtimeInfo.hasRecentLoad ? .green : (runtimeInfo.lastLoadTime != nil ? .orange : .gray))
                        .frame(width: 12, height: 12)
                }

                // 如果有错误，显示错误信息
                if runtimeInfo.hasError, let errMsg = runtimeInfo.lastErrorMessage {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近错误")
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                            Text(errMsg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Circle()
                            .fill(.red)
                            .frame(width: 12, height: 12)
                    }
                }
            }

            Divider()

            // 测试按钮
            Button {
                showTestSheet = true
            } label: {
                HStack {
                    Image(systemName: "phone.down.fill")
                    Text("拦截测试")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }

    private var extensionStatusColor: Color {
        switch checkService.extensionStatus {
        case .enabled: return .green
        case .disabled: return .red
        case .notFound: return .orange
        case .unknown, .checking: return .gray
        }
    }

    private var extensionStatusText: String {
        switch checkService.extensionStatus {
        case .enabled: return "已启用"
        case .disabled: return "未启用"
        case .notFound: return "未找到"
        case .unknown: return "未知"
        case .checking: return "检查中"
        }
    }

    private var extensionStatusDescription: String {
        switch checkService.extensionStatus {
        case .enabled: return "来电护盾拦截已在系统设置中启用"
        case .disabled: return "请在「设置→电话→来电阻止」中开启"
        case .notFound: return "Extension 未正确安装，请重新安装 App"
        case .unknown: return "无法检测启用状态，请手动确认"
        case .checking: return "正在检查..."
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 12) {
            // CallKit 拦截统计
            HStack(spacing: 16) {
                StatCard(title: "CallKit规则", value: "\(blockManager.blockNumbers.count)", icon: "list.bullet.fill", color: .blue)
                StatCard(title: "拦截模式", value: "精确匹配", icon: "number.fill", color: .blue)
            }

            // 前缀规则（待激活）
            HStack(spacing: 16) {
                StatCard(title: "前缀规则", value: "\(SpamPrefixResolver.totalPrefixCount)", icon: "bolt.shield.fill", color: .orange)
                StatCard(title: "覆盖区号", value: "\(SpamPrefixResolver.coveredAreaCodeCount)", icon: "building.2.fill", color: .orange)
            }
        }
    }

    // MARK: - Group Overview

    private var groupOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拦截分组")
                .font(.headline)

            let groups = blockManager.groups
            ForEach(groups, id: \.name) { group in
                HStack {
                    Image(systemName: PresetNumbers.groupIcon(for: group.name))
                        .foregroundStyle(.blue)
                        .frame(width: 30)
                    Text(group.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(group.count) 条规则")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷操作")
                .font(.headline)

            Button {
                AppGroupManager.shared.saveBlockNumbers(blockManager.blockNumbers)
                blockManager.loadAllData()
                checkService.reloadExtension()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    checkService.runFullCheck()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("刷新拦截服务")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .foregroundStyle(.primary)

            Button {
                showPermissionAlert = true
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("检查拦截权限")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .foregroundStyle(.primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }

    // MARK: - Permission Check

    private func openPhoneSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
    }
}

// MARK: - Block Test View

struct BlockTestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var blockManager: BlockManager
    @StateObject private var checkService = BlockCheckService.shared
    @State private var testNumber = ""
    @State private var testAdded = false
    @State private var extensionReloaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 一键测试
                    quickTestSection

                    // 手动测试步骤
                    stepsSection

                    // 说明
                    explanationSection
                }
                .padding()
            }
            .navigationTitle("拦截测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var quickTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一键测试拦截")
                .font(.headline)

            Text("输入一个你能控制的号码（如座机），我们将其加入黑名单并刷新拦截服务，然后你用该号码拨打来验证")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("输入号码（如座机号）", text: $testNumber)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)

                Button {
                    addTestNumber()
                } label: {
                    Text(testAdded ? "已添加" : "添加")
                        .font(.subheadline.bold())
                }
                .disabled(testNumber.isEmpty || testAdded)
                .buttonStyle(.borderedProminent)
            }

            if testAdded && !extensionReloaded {
                Button {
                    reloadAndCheck()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("刷新拦截服务")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            if extensionReloaded {
                VStack(alignment: .leading, spacing: 8) {
                    Label("测试号码已添加到黑名单", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)

                    Label("拦截服务已刷新", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)

                    Label("现在用该号码拨打你的 iPhone", systemImage: "phone.fill")
                        .foregroundStyle(.blue)
                        .font(.subheadline)

                    Label("如果不响铃 = 拦截成功！", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.blue)
                        .font(.subheadline.bold())
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func addTestNumber() {
        let trimmed = testNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blockManager.addNumber(trimmed, label: "测试号码", group: "测试")
        testAdded = true
    }

    private func reloadAndCheck() {
        checkService.reloadExtension()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            checkService.runFullCheck()
            extensionReloaded = true
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("测试步骤")
                .font(.headline)

            TestStepRow(
                number: 1,
                title: "添加一个测试号码",
                description: "在黑名单中添加一个你能控制的号码（如座机或朋友手机），开启前缀匹配",
                icon: "plus.circle.fill"
            )

            TestStepRow(
                number: 2,
                title: "用该号码拨打你的 iPhone",
                description: "用刚才添加的号码拨打电话",
                icon: "phone.fill"
            )

            TestStepRow(
                number: 3,
                title: "观察结果",
                description: "如果 iPhone 没有响铃、没有来电显示 → 拦截成功！\n如果 iPhone 正常响铃 → 拦截失败，请检查系统权限",
                icon: "checkmark.circle.fill"
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关于拦截统计")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "lock.shield.fill", text: "iOS 系统不提供拦截回调通知")
                InfoRow(icon: "phone.down.fill", text: "被拦截的来电不会响铃、不出现在通话记录中")
                InfoRow(icon: "eye.slash.fill", text: "App 无法获知具体哪些来电被拦截")
                InfoRow(icon: "checkmark.shield.fill", text: "通过系统权限状态 + 测试验证确认拦截生效")
            }

            Divider()

            Text("退出 App 后拦截是否生效？")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "checkmark.circle.fill", text: "拦截功能由系统级 Extension 提供，不依赖主 App 运行")
                InfoRow(icon: "checkmark.circle.fill", text: "退出 App 后，来电时系统会自动唤起 Extension 执行拦截")
                InfoRow(icon: "checkmark.circle.fill", text: "即使重启手机，拦截规则也会在首次来电时自动加载")
                InfoRow(icon: "exclamationmark.triangle.fill", text: "唯一例外：在系统设置中关闭了「来电阻止与身份识别」权限")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct TestStepRow: View {
    let number: Int
    let title: String
    let description: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.body.bold())
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

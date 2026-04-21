import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var isBlockEnabled = AppGroupManager.shared.isBlockEnabled
    @State private var showResetAlert = false
    @State private var showRemovePresetAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // CallKit 拦截（当前可用方案）
                Section(header: Text("来电拦截")) {
                    Toggle(isOn: $isBlockEnabled) {
                        VStack(alignment: .leading) {
                            Text("CallKit 号码库拦截")
                            Text(isBlockEnabled ? "已开启" : "已关闭")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: isBlockEnabled) { newValue in
                        AppGroupManager.shared.isBlockEnabled = newValue
                        blockManager.reloadExtension()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CallKit 使用精确匹配，通过预置号码库拦截已知骚扰号码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 前缀规则统计（为未来 Live Caller ID 升级预留）
                Section(header: Text("前缀规则引擎")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bolt.shield.fill")
                                .foregroundStyle(.orange)
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("本地前缀匹配引擎")
                                    .font(.subheadline.bold())
                                Text("2136 条前缀 · 覆盖112亿号码 · 等待激活")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("前缀匹配引擎已就绪（267 区号 × 4 骚扰首位 × 2 格式 = 2136 规则），但需要 Live Caller ID Lookup 扩展才能激活。开通 Apple Developer Program 后可启用。")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(SpamPrefixResolver.totalPrefixCount) 条")
                                    .font(.subheadline.bold())
                                Text("前缀规则")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(SpamPrefixResolver.coveredAreaCodeCount) 个")
                                    .font(.subheadline.bold())
                                Text("覆盖区号")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 权限引导
                Section(header: Text("权限设置")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("开启拦截权限")
                                .font(.subheadline.bold())
                        }

                        Text("请前往「设置 → 电话 → 来电阻止与身份识别」中开启 CallShield：")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("来电护盾拦截 — CallKit 号码库")
                                .font(.caption)
                        }

                        Button {
                            openPhoneSettings()
                        } label: {
                            Text("前往设置")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                // 数据管理
                Section(header: Text("数据管理")) {
                    Button {
                        showResetAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("恢复预置号码")
                            Spacer()
                            Text("\(PresetNumbers.presetNumbers.count) 条")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        showRemovePresetAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("删除所有预置号码")
                            Spacer()
                            Text("\(blockManager.blockNumbers.filter { $0.isPreset }.count) 条")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.red)
                }

                // 关于
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("2.1.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("拦截模式")
                        Spacer()
                        Text("CallKit 精确匹配")
                            .foregroundStyle(.blue)
                    }

                    HStack {
                        Text("CallKit 规则数")
                        Spacer()
                        Text("\(blockManager.blockNumbers.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("拦截记录数")
                        Spacer()
                        Text("\(blockManager.totalBlockCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("前缀规则（待激活）")
                        Spacer()
                        Text("\(SpamPrefixResolver.totalPrefixCount) 条")
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Text("覆盖区号")
                        Spacer()
                        Text("\(SpamPrefixResolver.coveredAreaCodeCount) 个")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .alert("确认恢复预置号码？", isPresented: $showResetAlert) {
                Button("取消", role: .cancel) {}
                Button("恢复") {
                    blockManager.resetToPresets()
                }
            } message: {
                Text("这将重置所有拦截规则为初始预置数据，您自定义添加的号码将被清除。")
            }
            .alert("确认删除所有预置号码？", isPresented: $showRemovePresetAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    blockManager.removePresetNumbers()
                }
            } message: {
                Text("将删除所有预置的拦截规则，仅保留您手动添加的号码。")
            }
        }
    }

    private func openPhoneSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

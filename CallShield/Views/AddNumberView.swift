import SwiftUI

struct AddNumberView: View {
    @EnvironmentObject var blockManager: BlockManager
    @Environment(\.dismiss) private var dismiss

    @State private var number = ""
    @State private var label = ""
    @State private var group = "自定义"
    @State private var isPrefix = false

    private let groups = ["自定义", "骚扰座机", "骚扰手机号", "400电话", "800电话", "骚扰号段"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("号码信息")) {
                    TextField("输入号码或号段", text: $number)
                        .keyboardType(.phonePad)
                        .font(.body.monospacedDigit())

                    TextField("备注标签（如：推销、诈骗）", text: $label)
                }

                Section(header: Text("拦截规则")) {
                    Picker("分组", selection: $group) {
                        ForEach(groups, id: \.self) { g in
                            Text(g).tag(g)
                        }
                    }

                    Toggle(isOn: $isPrefix) {
                        VStack(alignment: .leading) {
                            Text("前缀匹配")
                            Text(isPrefix ? "拦截以此号码开头的所有来电" : "仅拦截完全匹配的号码")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        addNumber()
                    } label: {
                        HStack {
                            Spacer()
                            Text("添加到黑名单")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("添加号码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func addNumber() {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blockManager.addNumber(trimmed, label: label.isEmpty ? "自定义号码" : label, group: group, isPrefix: isPrefix)
        dismiss()
    }
}

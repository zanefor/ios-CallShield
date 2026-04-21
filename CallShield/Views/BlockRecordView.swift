import SwiftUI

struct BlockRecordView: View {
    @EnvironmentObject var blockManager: BlockManager

    var body: some View {
        NavigationStack {
            Group {
                if blockManager.blockRecords.isEmpty {
                    emptyView
                } else {
                    recordsList
                }
            }
            .navigationTitle("拦截记录")
            .toolbar {
                if !blockManager.blockRecords.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                blockManager.clearRecords()
                            } label: {
                                Label("清空记录", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无拦截记录")
                .font(.title3.bold())
            Text("添加号码到黑名单时会自动记录。iOS 系统不提供被拦截来电的回调通知，被拦截的来电不会响铃且不出现在通话记录中。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordsList: some View {
        List {
            // 今日
            let todayRecords = blockManager.blockRecords.filter { Calendar.current.isDateInToday($0.blockedAt) }
            if !todayRecords.isEmpty {
                Section("今天") {
                    ForEach(todayRecords) { record in
                        RecordRow(record: record)
                    }
                }
            }

            // 更早
            let olderRecords = blockManager.blockRecords.filter { !Calendar.current.isDateInToday($0.blockedAt) }
            if !olderRecords.isEmpty {
                Section("更早") {
                    ForEach(olderRecords) { record in
                        RecordRow(record: record)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct RecordRow: View {
    let record: BlockRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.down.fill")
                .foregroundStyle(.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.number)
                    .font(.body.monospacedDigit().bold())
                Text(record.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.blockedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.blockedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

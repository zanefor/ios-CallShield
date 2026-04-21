import SwiftUI

struct BlockListView: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var selectedGroup: String?

    var filteredNumbers: [BlockNumber] {
        // 搜索时全局搜索，不受分组筛选限制
        if !searchText.isEmpty {
            return blockManager.blockNumbers.filter {
                $0.number.contains(searchText) || $0.label.contains(searchText)
            }
        }

        if let group = selectedGroup {
            return blockManager.numbersInGroup(group)
        }

        return blockManager.blockNumbers
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 分组筛选
                groupFilter

                // 号码列表
                listContent
            }
            .navigationTitle("黑名单")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索号码或标签")
            .sheet(isPresented: $showAddSheet) {
                AddNumberView()
                    .environmentObject(blockManager)
            }
        }
    }

    // MARK: - Group Filter

    private var groupFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                GroupFilterChip(title: "全部", count: blockManager.blockNumbers.count, isSelected: selectedGroup == nil) {
                    selectedGroup = nil
                }

                ForEach(blockManager.groups, id: \.name) { group in
                    GroupFilterChip(
                        title: group.name,
                        count: group.count,
                        isSelected: selectedGroup == group.name
                    ) {
                        selectedGroup = group.name
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            ForEach(filteredNumbers) { number in
                NumberRow(number: number)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            blockManager.removeNumber(number)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Group Filter Chip

struct GroupFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Number Row

struct NumberRow: View {
    let number: BlockNumber

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(number.number)
                        .font(.body.monospacedDigit().bold())
                    if number.isPrefix {
                        Text("前缀")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    if number.isPreset {
                        Text("预置")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text("\(number.label) · \(number.group)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "phone.down.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

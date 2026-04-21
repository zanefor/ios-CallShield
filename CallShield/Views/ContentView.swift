import SwiftUI

struct ContentView: View {
    @EnvironmentObject var blockManager: BlockManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "shield.fill")
                }
                .tag(0)

            BlockListView()
                .tabItem {
                    Label("黑名单", systemImage: "phone.down.fill")
                }
                .tag(1)

            BlockRecordView()
                .tabItem {
                    Label("拦截记录", systemImage: "clock.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.blue)
    }
}

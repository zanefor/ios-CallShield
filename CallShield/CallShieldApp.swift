import SwiftUI

@main
struct CallShieldApp: App {
    @StateObject private var blockManager = BlockManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(blockManager)
        }
    }
}

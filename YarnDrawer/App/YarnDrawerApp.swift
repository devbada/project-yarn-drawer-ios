import SwiftUI

@main
struct YarnDrawerApp: App {
    @StateObject private var store = PatternStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .task {
                    await store.load()
                }
        }
    }
}


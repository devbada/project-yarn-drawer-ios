import SwiftUI

@main
struct YarnDrawerApp: App {
    @StateObject private var store = PatternStore()

    init() {
        YDFont.registerFonts()
        YDFont.configureNavigationFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .font(YDFont.font(size: 15))
                .task {
                    await store.load()
                }
        }
    }
}

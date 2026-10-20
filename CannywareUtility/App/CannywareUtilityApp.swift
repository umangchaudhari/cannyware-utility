import SwiftUI

@main
struct CannywareUtilityApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
            .tint(CannywareTheme.forest)
        }
    }
}

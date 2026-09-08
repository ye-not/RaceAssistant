import SwiftUI

@main
struct Race_Assistant_WatchApp: App {

    @StateObject private var connectivity =
        WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
        }
    }
}

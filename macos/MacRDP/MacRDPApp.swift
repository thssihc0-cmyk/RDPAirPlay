import SwiftUI

@main
struct MacRDPApp: App {
    @StateObject private var hostStore = HostStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hostStore)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

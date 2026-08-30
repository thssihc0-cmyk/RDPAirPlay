import SwiftUI

@main
struct RDPAirPlayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var hostStore = HostStore()
    @StateObject private var externalDisplay = ExternalDisplayManager()

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environmentObject(hostStore)
                .environmentObject(externalDisplay)
        }
    }
}

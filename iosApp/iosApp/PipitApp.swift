import SwiftUI

@main
struct PipitApp: App {
    @StateObject private var bleService = IosBleProximityService()
    
    init() {
        #if DEBUG
        // During debug previews, mock connected state so the Disconnect overlay does not block the UI.
        bleService.connectionState = .connectedUnlocked
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bleService)
        }
    }
}

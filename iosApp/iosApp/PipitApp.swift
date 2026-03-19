import SwiftUI

@main
struct PipitApp: App {
    @StateObject private var bleService = IosBleProximityService()
    
    init() {
        #if targetEnvironment(simulator)
        // During simulator runs, start in a connected state so the disconnect overlay does not block the UI.
        bleService.simulatorSetConnectionState(.connected)
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bleService)
        }
    }
}

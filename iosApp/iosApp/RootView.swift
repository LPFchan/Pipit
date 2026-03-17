import SwiftUI

#if canImport(shared)
import shared
#endif

enum NavigationRoute: Hashable {
    case settings
}

struct RootView: View {
    @EnvironmentObject private var bleService: IosBleProximityService
    
    @State private var hasProvisionedKey: Bool = false
    @State private var path = NavigationPath()
    
    var body: some View {
        Group {
            if hasProvisionedKey {
                NavigationStack(path: $path) {
                    HomeView()
                        .navigationDestination(for: NavigationRoute.self) { route in
                            switch route {
                            case .settings:
                                SettingsView(bleService: bleService, onLocalKeyDeleted: {
                                    hasProvisionedKey = false
                                    path.removeLast(path.count)
                                })
                            }
                        }
                }
                .modifier(DisconnectOverlayModifier(
                    connectionState: bleService.connectionState,
                    isOverlayEnabled: true
                ))
            } else {
                OnboardingView(bleService: bleService, onProvisioned: {
                    hasProvisionedKey = true
                })
                .modifier(DisconnectOverlayModifier(
                    connectionState: bleService.connectionState,
                    isOverlayEnabled: false
                ))
            }
        }
        .onAppear {
            checkProvisioningState()
        }
    }
    
    private func checkProvisioningState() {
        #if canImport(shared)
        let gate = OnboardingGate()
        hasProvisionedKey = gate.hasAnyProvisionedKey()
        #else
        hasProvisionedKey = false
        #endif
    }
}

// A simple modifier to manage the disconnect overlay 
struct DisconnectOverlayModifier: ViewModifier {
    var connectionState: ConnectionState
    var isOverlayEnabled: Bool

    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isOverlayEnabled && shouldShowOverlay {
                DisconnectOverlaySwiftUIView()
                    
            }
        }
    }
    
    private var shouldShowOverlay: Bool {
        switch connectionState {
        case .connectedLocked, .connectedUnlocked:
            return false
        default:
            return true
        }
    }
}

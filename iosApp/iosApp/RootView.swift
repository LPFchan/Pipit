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
    @State private var showSettings = false
    @State private var flipDegrees = 0.0
    
    var body: some View {
        Group {
            if hasProvisionedKey {
                ZStack {
                    ZStack {
                        HomeView(onTapSettings: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                flipDegrees = 180
                                showSettings = true
                            }
                        })
                        .opacity(showSettings ? 0 : 1)
                        .modifier(DisconnectOverlayModifier(
                            connectionState: bleService.connectionState,
                            isOverlayEnabled: true,
                            isBluetoothPoweredOff: bleService.isBluetoothPoweredOff
                        ))
                    }
                    .rotation3DEffect(.degrees(flipDegrees), axis: (x: 0, y: 1, z: 0))
                    
                    if showSettings {
                        SettingsView(bleService: bleService, onLocalKeyDeleted: {
                            hasProvisionedKey = false
                            showSettings = false
                            flipDegrees = 0
                        })
                        .rotation3DEffect(.degrees(flipDegrees - 180), axis: (x: 0, y: 1, z: 0))
                        .transition(.opacity) // ensure it doesn't animate position incorrectly
                        // Cross-fade close button via navigation or overlay 
                        .overlay(
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    flipDegrees = 0
                                    showSettings = false
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .padding()
                                    .background(Circle().fill(Color(uiColor: .systemBackground).opacity(0.8)))
                                    .foregroundColor(.primary)
                            }
                            .padding(.top, 16)
                            .padding(.trailing, 16),
                            alignment: .topTrailing
                        )
                    }
                }
            } else {
                OnboardingView(bleService: bleService, onProvisioned: {
                    hasProvisionedKey = true
                })
                .modifier(DisconnectOverlayModifier(
                    connectionState: bleService.connectionState,
                    isOverlayEnabled: false,
                    isBluetoothPoweredOff: bleService.isBluetoothPoweredOff
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
    var isBluetoothPoweredOff: Bool

    #if targetEnvironment(simulator)
    @AppStorage("DEV_BYPASS_OVERLAY") private var devBypassOverlay = false
    #endif

    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isOverlayEnabled && shouldShowOverlay {
                DisconnectOverlaySwiftUIView(isBluetoothPoweredOff: isBluetoothPoweredOff)
                    
            }
        }
    }
    
    private var shouldShowOverlay: Bool {
        #if targetEnvironment(simulator)
        if devBypassOverlay { return false }
        #endif
        
        switch connectionState {
        case .connectedLocked, .connectedUnlocked:
            return false
        default:
            return true
        }
    }
}

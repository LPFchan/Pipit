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
    
    var body: some View {
        Group {
            if hasProvisionedKey {
                ZStack(alignment: .topLeading) {
                    Color(uiColor: .systemBackground).edgesIgnoringSafeArea(.all)
                    
                    ZStack {
                        HomeView()
                            .opacity(showSettings ? 0 : 1)
                            .allowsHitTesting(!showSettings)
                        
                        if showSettings {
                            SettingsView(bleService: bleService, onLocalKeyDeleted: {
                                hasProvisionedKey = false
                                showSettings = false
                            })
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                )
                            )
                            .zIndex(1)
                            .overlay(
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.28)) {
                                        showSettings = false
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 16)
                                .padding(.trailing, 16),
                                alignment: .topTrailing
                            )
                        }
                    }
                    .modifier(DisconnectOverlayModifier(
                        connectionState: bleService.connectionState,
                        isOverlayEnabled: true,
                        isBluetoothPoweredOff: bleService.isBluetoothPoweredOff
                    ))

                    // Persistent Gear Button above everything else
                    if !showSettings {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                showSettings = true
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 16)
                        .padding(.top, 16)
                        .transition(.opacity)
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

    /// Same dev escape hatch as simulator: set from the disconnect overlay’s “Bypass” control (or UserDefaults).
    @AppStorage("DEV_BYPASS_OVERLAY") private var devBypassOverlay = false

    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isOverlayEnabled && shouldShowOverlay {
                DisconnectOverlaySwiftUIView(isBluetoothPoweredOff: isBluetoothPoweredOff)
                    
            }
        }
    }
    
    private var shouldShowOverlay: Bool {
        if devBypassOverlay { return false }

        switch connectionState {
        case .connected:
            return false
        default:
            return true
        }
    }
}

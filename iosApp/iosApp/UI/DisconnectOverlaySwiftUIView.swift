import SwiftUI

struct DisconnectOverlaySwiftUIView: View {
    var isBluetoothPoweredOff: Bool = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 56)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false) // Let touches pass through to gear button
                
                Color(uiColor: .systemBackground)
                    .opacity(0.6)
                    // Defaults to allowing hit testing, blocking views below
            }
            .ignoresSafeArea()
            
            if isBluetoothPoweredOff {
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("✕ Bluetooth is off")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            } else {
                Text("○ Disconnected")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .allowsHitTesting(false)
            }
            
            #if targetEnvironment(simulator)
            VStack {
                Spacer()
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "DEV_BYPASS_OVERLAY")
                }) {
                    Text("DEV: Bypass Overlay")
                        .padding()
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
                .padding(.bottom, 40)
            }
            #endif
        }
    }
}

import SwiftUI

struct DisconnectOverlaySwiftUIView: View {
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
            
            Text("○ Disconnected")
                .font(.title3)
                .foregroundColor(.primary)
                .allowsHitTesting(false)
        }
    }
}

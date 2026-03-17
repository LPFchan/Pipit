import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var bleService: IosBleProximityService
    @State private var showTapHint: Bool = true
    var onTapSettings: (() -> Void)?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: .systemBackground).edgesIgnoringSafeArea(.all)
            
            // Gear button
            Button(action: {
                onTapSettings?()
            }) {
                Image(systemName: "gearshape.fill")
                    .imageScale(.large)
                    .padding()
                    .contentShape(Rectangle()) // makes tapping area reasonable
            }
            .padding(.leading, 4)
            .padding(.top, 4)
            .foregroundColor(.primary)
            
            // Center content
            VStack(spacing: 8) {
                FobRealityViewWrapper(
                    onTap: {
                        showTapHint = false
                        Task { await bleService.sendUnlockCommand() }
                    },
                    onLongPress: {
                        showTapHint = false
                        Task { await bleService.sendLockCommand() }
                    }
                )
                .frame(width: 200, height: 140)
                
                if showTapHint {
                    Text("Tap · Hold to lock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    // Invisible spacer to maintain layout height after hint disappears
                    Text("Tap · Hold to lock")
                        .font(.caption)
                        .hidden()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarHidden(true)
    }
}

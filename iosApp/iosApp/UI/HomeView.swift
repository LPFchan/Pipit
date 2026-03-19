import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var bleService: IosBleProximityService
    @AppStorage("hasLockedFobAtLeastOnce") private var hasLockedFobAtLeastOnce: Bool = false
    @State private var interactedThisSession: Bool = false

    var body: some View {
        ZStack(alignment: .center) {
            Color.clear.edgesIgnoringSafeArea(.all)

            FobInteractiveViewer(
                onTap: {
                    interactedThisSession = true
                    Task { await bleService.sendUnlockCommand() }
                },
                onLongPress: {
                    hasLockedFobAtLeastOnce = true
                    interactedThisSession = true
                    Task { await bleService.sendLockCommand() }
                }
            )
            .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                Spacer()

                // Educational prompt hint if the user has never locked
                if !hasLockedFobAtLeastOnce && !interactedThisSession {
                    Text("Hold to lock, tap to unlock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground).opacity(0.8), in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.4), value: interactedThisSession)
            .allowsHitTesting(false)
        }
        .navigationBarHidden(true)
    }
}

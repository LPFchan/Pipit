import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var bleService: IosBleProximityService
    @AppStorage("hasLockedFobAtLeastOnce") private var hasLockedFobAtLeastOnce: Bool = false
    @State private var interactedThisSession: Bool = false

    var body: some View {
        ZStack(alignment: .center) {
            Color.clear.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                Spacer()

                // Lock / unlock state badge
                lockStateBadge
                    .padding(.bottom, 36)

                FobRealityViewWrapper(
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
                .frame(width: 220, height: 160)

                // Usage hint — fades out once the user has interacted
                Text("Tap to unlock  ·  Hold to lock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 20)
                    .opacity(!hasLockedFobAtLeastOnce && !interactedThisSession ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: interactedThisSession)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Lock state badge

    private var lockStateBadge: some View {
        let unlocked = bleService.connectionState == .connectedUnlocked
        return HStack(spacing: 6) {
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(unlocked ? "Unlocked" : "Locked")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background((unlocked ? Color.green : Color(.secondaryLabel)).opacity(0.12), in: Capsule())
        .foregroundStyle(unlocked ? Color.green : Color(.secondaryLabel))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: bleService.connectionState)
    }
}

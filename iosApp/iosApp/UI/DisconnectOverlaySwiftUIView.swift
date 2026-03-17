import SwiftUI

struct DisconnectOverlaySwiftUIView: View {
    var isBluetoothPoweredOff: Bool = false

    @State private var appeared = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 88, height: 88)
                        .scaleEffect(pulse ? 1.18 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                            value: pulse
                        )

                    Image(systemName: statusIcon)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                VStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                if isBluetoothPoweredOff {
                    Button(action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Label("Open Settings", systemImage: "gear")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
                }
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.88)

            #if targetEnvironment(simulator)
            VStack {
                Spacer()
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "DEV_BYPASS_OVERLAY")
                }) {
                    Text("DEV: Bypass Overlay")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 52)
            }
            #endif
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 0.6).delay(0.3)) {
                pulse = true
            }
        }
    }

    private var statusIcon: String {
        isBluetoothPoweredOff ? "bluetooth.slash" : "dot.radiowaves.left.and.right"
    }

    private var statusColor: Color {
        isBluetoothPoweredOff ? .orange : Color(.label).opacity(0.5)
    }

    private var statusTitle: String {
        isBluetoothPoweredOff ? "Bluetooth Off" : "Not Connected"
    }

    private var statusSubtitle: String {
        isBluetoothPoweredOff
            ? "Enable Bluetooth to connect to Uguisu."
            : "Searching for Uguisu nearby..."
    }
}

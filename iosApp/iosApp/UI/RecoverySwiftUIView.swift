import SwiftUI

// This is a SwiftUI version of the Recovery Panel you just worked on.
// You can open this file in Xcode and you'll see a live preview on the right side!

enum DemoRecoveryState {
    case waitingForWindowOpen
    case loadingSlots
    case slotPicker
    case ownerProof
    case error
}

struct RecoverySwiftUIView: View {
    // These properties act like your old variables mapped to the UI.
    @State var state: DemoRecoveryState = .waitingForWindowOpen
    @State var selectedSlotId: Int? = 1
    
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                
                // MAIN INSTRUCTION TEXT
                Text(bodyText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // SLOT PICKER LIST (Only visible in 'slotPicker' state)
                if state == .slotPicker {
                    VStack(spacing: 12) {
                        SlotRow(title: "Phone 1", isSelected: selectedSlotId == 1) { selectedSlotId = 1 }
                        SlotRow(title: "Lost iPhone", isSelected: selectedSlotId == 2) { selectedSlotId = 2 }
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // STATUS / ERROR LABEL
                if state == .waitingForWindowOpen || state == .loadingSlots {
                    ProgressView()
                        .padding(.bottom, 8)
                }
                
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(state == .error ? .red : .gray)
                    .multilineTextAlignment(.center)
                
                // PRIMARY ACTION BUTTON
                if state == .slotPicker || state == .ownerProof || state == .error {
                    Button(action: onConfirm) {
                        Text(buttonTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.top, 24)
            .navigationTitle("Recover Key")
            .navigationBarItems(leading: Button("Cancel", action: onCancel))
        }
    }
    
    // MARK: - Dynamic Text Logic (Just like your updateUiForState switch)
    
    var bodyText: String {
        switch state {
        case .slotPicker:
            return "Pick the phone slot you want to replace on this device. Pipit will mint a fresh AES key and revoke the lost phone immediately."
        case .ownerProof:
            return "Recovering Slot 1 requires BLE owner proof. When you continue, iOS should show the system Bluetooth pairing prompt. Enter the 6-digit Guillemot PIN to authorize the recovery."
        default:
            return "Press the button three times on your Uguisu fob."
        }
    }
    
    var statusText: String {
        switch state {
        case .waitingForWindowOpen: return "Scanning for the Window Open beacon..."
        case .loadingSlots: return "Management session ready. Loading slots..."
        case .error: return "Failed to connect. Please try again."
        default: return ""
        }
    }
    
    var buttonTitle: String {
        switch state {
        case .slotPicker: return "Recover this slot"
        case .ownerProof: return "Continue to pairing"
        case .error: return "Try again"
        default: return "Continue"
        }
    }
}

// SwiftUI Subcomponent for a tapable slot row
struct SlotRow: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Live Previews (Xcode displays these automatically!)
struct RecoverySwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview 1: Waiting state
            RecoverySwiftUIView(state: .waitingForWindowOpen, onCancel: {}, onConfirm: {})
                .previewDisplayName("Scanning")
            
            // Preview 2: Slot Picker State
            RecoverySwiftUIView(state: .slotPicker, onCancel: {}, onConfirm: {})
                .previewDisplayName("Slot Picker")
        }
    }
}

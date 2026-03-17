import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: SettingsViewModel
    @EnvironmentObject private var bleService: IosBleProximityService

    init(
        bleService: IosBleProximityService,
        onLocalKeyDeleted: @escaping () -> Void
    ) {
        let vm = SettingsViewModel(
            bleService: bleService,
            onLocalKeyDeleted: onLocalKeyDeleted
        )
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerView
                    statusView
                    
                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }

                    Form {
                        proximitySection
                        
                        if viewModel.isOwnerView {
                            keysSection
                        }

                        yourKeySection

                        if viewModel.isOwnerView {
                            deviceSection
                        }

                        aboutSection
                    }
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -16)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .onAppear {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .alert(
                "Alert",
                isPresented: Binding(
                    get: { viewModel.alertType != nil },
                    set: { if !$0 { viewModel.alertType = nil } }
                ),
                presenting: viewModel.alertType
            ) { alertType in
                switch alertType {
                case .guestProvisionConfirmation:
                    Button("Cancel", role: .cancel) { viewModel.alertType = nil }
                    Button("Create") { viewModel.confirmGuestProvisioning() }
                case .replaceConfirmation:
                    Button("Cancel", role: .cancel) { viewModel.alertType = nil }
                    Button("Replace", role: .destructive) { viewModel.confirmReplace() }
                case .deleteConfirmation:
                    Button("Cancel", role: .cancel) { viewModel.alertType = nil }
                    Button("Delete", role: .destructive) { viewModel.confirmDelete() }
                case .renamePrompt:
                    TextField("Name", text: $viewModel.renameText)
                    Button("Cancel", role: .cancel) { viewModel.alertType = nil }
                    Button("Rename") { viewModel.confirmRename() }
                case .transferConfirmation:
                    Button("Cancel", role: .cancel) { viewModel.alertType = nil }
                    Button("Generate QR") { viewModel.proceedWithTransfer() }
                case .ownerTransferPinPrompt:
                    SecureField("PIN", text: $viewModel.transferPinText).keyboardType(.numberPad)
                    Button("Cancel", role: .cancel) { viewModel.alertType = nil }
                    Button("Generate") { viewModel.proceedWithOwnerTransfer() }
                case .deletionConfirmation:
                    Button("Cancel", role: .cancel) { viewModel.alertType = nil }
                    Button("Delete", role: .destructive) { viewModel.confirmLocalDeletion() }
                case .info:
                    Button("OK", role: .cancel) { viewModel.alertType = nil }
                }
            } message: { alertType in
                Text("Confirmation")
            }
            .sheet(item: $viewModel.showQrSheet) { qrType in
                qrSheetContent(for: qrType)
            }
        }
    }

    // MARK: - View Components
    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title)
                    .fontWeight(.bold)
                Text(viewModel.headerSubtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Text("Close")
            }
        }
    }

    private var statusView: some View {
        HStack(spacing: 10) {
            if viewModel.isLoading {
                ProgressView()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.statusText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
            
            Spacer()
            
            if viewModel.showRetry {
                Button("Retry") {
                    viewModel.retryLoadSlots()
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.body)
            .foregroundColor(.red)
            .lineLimit(nil)
            .padding(12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
    }

    private var proximitySection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Background Unlock")
                            .font(.headline)
                        Text(viewModel.proximityEnabled ? "Automatic unlock and lock are enabled." : "Manual control only.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.proximityEnabled)
                        .onChange(of: viewModel.proximityEnabled) { _ in viewModel.backgroundUnlockToggled() }
                }

                sliderBlock(
                    title: "Unlock RSSI",
                    subtitle: "Closer to 0 unlocks sooner.",
                    value: Double(viewModel.unlockRssi),
                    range: -95...(-35),
                    label: "\(viewModel.unlockRssi) dBm",
                    enabled: viewModel.proximityEnabled,
                    onChange: viewModel.unlockRssiChanged
                )

                sliderBlock(
                    title: "Lock RSSI",
                    subtitle: "Always at least 10 dBm weaker than unlock.",
                    value: Double(viewModel.lockRssi),
                    range: -105...Double(viewModel.unlockRssi - 10),
                    label: "\(viewModel.lockRssi) dBm",
                    enabled: viewModel.proximityEnabled,
                    onChange: viewModel.lockRssiChanged
                )
            }
            .padding(.vertical, 8)
        } header: {
            Text("PROXIMITY")
        } footer: {
            Text("These preferences are stored locally and already feed the existing BLE proximity layer.")
        }
    }

    private var keysSection: some View {
        Section {
            VStack(spacing: 12) {
                switch viewModel.slotLoadState {
                case .idle:
                    Text("Waiting to connect to the vehicle.")
                        .font(.body)
                case .loading:
                    HStack {
                        ProgressView()
                        Text(viewModel.statusText)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                case .loaded:
                    ForEach(viewModel.completedSlots, id: \.id) { slot in
                        slotRowViewOwner(slot: slot)
                    }
                case .error(let message):
                    Text(message)
                        .font(.body)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("KEYS")
        } footer: {
            Text("Live slot data comes from SLOTS? over the existing management transport. Owner writes re-identify before mutating a slot.")
        }
    }

    private var yourKeySection: some View {
        Section {
            VStack(spacing: 12) {
                if let localSlotId = viewModel.localSlotId,
                   let slot = viewModel.completedSlots.first(where: { $0.id == localSlotId }) {
                    slotRowViewGuest(slot: slot)
                    Button(action: { viewModel.showTransferConfirmation() }) {
                        Text("Transfer to New Phone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    switch viewModel.slotLoadState {
                    case .loading:
                        HStack {
                            ProgressView()
                            Text(viewModel.statusText)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    case .error(let message):
                        Text(message)
                            .font(.body)
                            .foregroundColor(.red)
                    case .loaded:
                        Text("Your local phone key could not be matched to a returned slot.")
                            .font(.body)
                    case .idle:
                        Text("Waiting to connect to the vehicle.")
                            .font(.body)
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("YOUR KEY")
        } footer: {
            Text("Your phone slot stays separate from the rest of the vehicle state and owns its transfer flow.")
        }
    }

    private var deviceSection: some View {
        Section {
            VStack(spacing: 12) {
                Button(action: { viewModel.showTransferConfirmation() }) {
                    Text("Transfer to New Phone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("Slot 0 stays read-only on iOS. Use Whimbrel or Android USB OTG flows for Uguisu replacement, PIN changes, and firmware flashing.")
                    .font(.body)

                Text("Current management state: \(managementStatusTextDisplay)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } header: {
            Text("DEVICE")
        } footer: {
            Text("Owner migration stays here. USB-C OTG maintenance remains Android-only and is intentionally hidden on iOS.")
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(spacing: 8) {
                if let localSlotId = viewModel.localSlotId {
                    Text("Local phone slot: \(localSlotId)")
                        .font(.body)
                } else {
                    Text("No local phone slot is currently stored on this device.")
                        .font(.body)
                }

                Text("Management state: \(managementStatusTextDisplay)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !viewModel.isOwnerView {
                    switch viewModel.slotLoadState {
                    case .loaded:
                        ForEach(viewModel.completedSlots, id: \.id) { slot in
                            slotRowViewAbout(slot: slot)
                        }
                    case .loading:
                        HStack {
                            ProgressView()
                            Text("Loading the read-only slot overview.")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    case .error(let message):
                        Text(message)
                            .font(.body)
                            .foregroundColor(.red)
                    case .idle:
                        Text("The slot overview appears here after the first management connection.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("ABOUT")
        } footer: {
            Text("Management session state and slot context.")
        }
    }

    // MARK: - Helper Views
    private func sliderBlock(
        title: String,
        subtitle: String,
        value: Double,
        range: ClosedRange<Double>,
        label: String,
        enabled: Bool,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(nil)
            Slider(value: .constant(value), in: range)
                .disabled(!enabled)
                .onChange(of: value) { newValue in onChange(newValue) }
        }
    }

    private func slotRowViewOwner(slot: BleManagementSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Slot \(slot.id) · \(viewModel.slotTierLabel(for: slot.id))")
                        .font(.headline)
                    Text(viewModel.slotDisplayName(for: slot))
                        .font(.body)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(viewModel.slotBadge(for: slot))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)

                    if viewModel.shouldShowSlotControl(for: slot) {
                        slotMenu(for: slot)
                    }
                }
            }
            Text(viewModel.slotDetailText(for: slot))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func slotRowViewGuest(slot: BleManagementSlot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Slot \(slot.id) · \(viewModel.slotTierLabel(for: slot.id))")
                        .font(.headline)
                    Text(viewModel.slotDisplayName(for: slot))
                        .font(.body)
                }
                Spacer()
                Text(viewModel.slotBadge(for: slot))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            Text(viewModel.slotDetailText(for: slot))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func slotRowViewAbout(slot: BleManagementSlot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Slot \(slot.id) · \(viewModel.slotTierLabel(for: slot.id))")
                        .font(.headline)
                    Text(viewModel.slotDisplayName(for: slot))
                        .font(.body)
                }
                Spacer()
                Text(viewModel.slotBadge(for: slot))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            Text(viewModel.slotDetailTextAbout(for: slot))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func slotMenu(for slot: BleManagementSlot) -> some View {
        Menu {
            Button("Rename") {
                viewModel.showRenamePrompt(for: slot)
            }
            Button("Replace") {
                viewModel.showReplaceConfirmation(for: slot)
            }
            Button("Delete", role: .destructive) {
                viewModel.showDeleteConfirmation(for: slot)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private func qrSheetContent(for qrType: SettingsViewModel.QrType) -> some View {
        switch qrType {
        case .provisioning(let title, let body, let payload, let doneTitle, let deleteLocalKeyOnDone):
            qrSheetView(
                title: title,
                body: body,
                payload: payload,
                doneTitle: doneTitle,
                onDone: {
                    if deleteLocalKeyOnDone {
                        viewModel.alertType = .deletionConfirmation
                    }
                    viewModel.showQrSheet = nil
                }
            )
        case .transfer(let title, let body, let payload):
            qrSheetView(
                title: title,
                body: body,
                payload: payload,
                doneTitle: "Done — I've Scanned",
                onDone: {
                    viewModel.alertType = .deletionConfirmation
                    viewModel.showQrSheet = nil
                }
            )
        }
    }

    private func qrSheetView(
        title: String,
        body: String,
        payload: String,
        doneTitle: String,
        onDone: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(body)
                .font(.body)
                .foregroundColor(.secondary)

            if let qrImage = viewModel.generateQrImage(payload: payload) {
                Image(uiImage: qrImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 280)
                    .background(Color.white)
                    .cornerRadius(20)
            }

            Text("Provisioning payload is hidden for security. Use only the QR code to transfer.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: onDone) {
                Text(doneTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(role: .cancel) {
                viewModel.showQrSheet = nil
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
        .padding(24)
    }

    private var managementStatusTextDisplay: String {
        let state = bleService.managementState
        switch state.connectionState {
        case .disconnected:
            return "Management session disconnected."
        case .scanning:
            return "Scanning for Guillemot management advertising."
        case .connecting:
            return "Connecting to management GATT."
        case .discovering:
            return "Discovering management characteristics."
        case .ready:
            return "Management session ready."
        case .error:
            return state.lastError ?? "Management session failed."
        }
    }
}

#Preview {
    Text("Settings View Preview")
}

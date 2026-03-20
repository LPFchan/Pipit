import SwiftUI

/// MainActor + non-observed `bleService` keep sheet/bindings and the view body on one actor and avoid
/// re-rendering Settings on every `IosBleProximityService` publish (management session churn).
@MainActor
struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    /// Passed from `RootView`; not `@EnvironmentObject` so BLE RSSI / management state updates
    /// do not invalidate this tree (was freezing the UI when opening Settings).
    private let bleService: IosBleProximityService
    /// Mirrors `viewModel.showQrSheet` so `.sheet(item:)` uses a plain `Binding`, not `$viewModel.showQrSheet`
    /// (SwiftUI warns / will crash when a sheet reads MainActor-isolated storage via `Binding` off-actor).
    @State private var presentedQrSheet: SettingsViewModel.QrType?

    private let slotCardStyle = SlotPresentationStyle.settingsGrouped

    init(
        bleService: IosBleProximityService,
        onLocalKeyDeleted: @escaping () -> Void
    ) {
        self.bleService = bleService
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                bleService: bleService,
                onLocalKeyDeleted: onLocalKeyDeleted
            )
        )
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    headerView

                    if viewModel.isLoading || viewModel.showRetry {
                        statusView
                    }

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }

                    proximitySection

                    keysSection

                    #if targetEnvironment(simulator)
                    devSection
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 52)
                .padding(.bottom, 36)
            }
            .onAppear {
                presentedQrSheet = viewModel.showQrSheet
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .onChange(of: viewModel.showQrSheet) { _, new in
                presentedQrSheet = new
            }
            .onChange(of: presentedQrSheet) { _, new in
                if new == nil { viewModel.showQrSheet = nil }
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
                switch alertType {
                case .guestProvisionConfirmation(let slotId):
                    Text("Create a guest key for slot \(slotId) and show a one-time transfer QR code.")
                case .deleteConfirmation(let slot):
                    Text("This will permanently revoke slot \(slot.id) from Uguisu.")
                case .replaceConfirmation:
                    Text("The existing key in this slot will be overwritten.")
                case .deletionConfirmation:
                    Text("Your phone key will be removed from this device.")
                case .transferConfirmation:
                    Text("A one-time QR code will be generated to transfer your key.")
                case .info(_, let message):
                    Text(message)
                default:
                    EmptyView()
                }
            }
            .sheet(item: $presentedQrSheet) { qrType in
                qrSheetContent(for: qrType)
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusView: some View {
        HStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.85)
            } else {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            if viewModel.showRetry {
                Button("Retry") {
                    viewModel.retryLoadSlots()
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var proximitySection: some View {
        settingsSection {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Proximity Unlock")
                            .font(.headline)

                        Text(viewModel.proximityEnabled ? "Enabled" : "Disabled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: proximityToggleBinding)
                        .labelsHidden()
                }
                .padding(16)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if viewModel.proximityEnabled {
                    thresholdPresetControl
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .animation(.snappy(duration: 0.26, extraBounce: 0), value: viewModel.proximityEnabled)
        }
    }

    private var proximityToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.proximityEnabled },
            set: { newValue in
                withAnimation(.snappy(duration: 0.26, extraBounce: 0)) {
                    viewModel.proximityEnabled = newValue
                }
                viewModel.backgroundUnlockToggled()
            }
        )
    }

    private var keysSection: some View {
        settingsSection(
            eyebrow: "Keys"
        ) {
            keysContent
        }
    }

    @ViewBuilder
    private var keysContent: some View {
        switch viewModel.slotLoadState {
        case .idle:
            inlineStateCard(
                icon: "antenna.radiowaves.left.and.right",
                tint: .secondary,
                title: "Waiting for a management session",
                body: "Open Settings near the vehicle to pull the latest slot state."
            )
        case .loading:
            inlineStateCard(
                icon: "dot.radiowaves.left.and.right",
                tint: .secondary,
                title: "Loading slots",
                body: viewModel.statusText,
                showsProgress: true
            )
        case .error(let message):
            inlineStateCard(
                icon: "wifi.exclamationmark",
                tint: .red,
                title: "Unable to load slots",
                body: message,
                actionTitle: "Retry",
                action: viewModel.retryLoadSlots
            )
        case .loaded:
            VStack(spacing: 14) {
                if viewModel.isOwnerView {
                    SlotPresentationCard(
                        rows: settingsSlotRows,
                        style: slotCardStyle,
                        accessoryWidth: 24,
                        accessory: { ownerAccessoryView(for: $0) }
                    )
                } else {
                    SlotPresentationCard(
                        rows: settingsSlotRows,
                        style: slotCardStyle
                    )
                }

                if viewModel.localSlotId != nil {
                    primaryActionButton(title: "Transfer to New Phone", systemImage: "qrcode") {
                        viewModel.showTransferConfirmation()
                    }
                }
            }
        }
    }

    #if targetEnvironment(simulator)
    private var devSection: some View {
        settingsSection(
            eyebrow: "Developer",
            title: "Simulator controls",
            footer: "Simulator-only. Overrides BLE connection state for UI testing."
        ) {
            VStack(spacing: 12) {
                let isConnected = bleService.connectionState == .connected

                secondaryActionButton(
                    title: isConnected ? "Simulate Disconnect" : "Simulate Connected",
                    systemImage: isConnected ? "bolt.slash.fill" : "bolt.fill",
                    tint: Color.yellow.opacity(0.95),
                    foreground: .black
                ) {
                    if isConnected {
                        bleService.simulatorSetConnectionState(.disconnected)
                        UserDefaults.standard.set(false, forKey: "DEV_BYPASS_OVERLAY")
                    } else {
                        bleService.simulatorSetConnectionState(.connected)
                        UserDefaults.standard.set(true, forKey: "DEV_BYPASS_OVERLAY")
                    }
                }

                secondaryActionButton(
                    title: "Hard Reset App and Permissions",
                    systemImage: "trash.fill",
                    tint: Color.red.opacity(0.9),
                    foreground: .white
                ) {
                    if let bundleID = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: bundleID)
                    }
                    viewModel.forceResetAllKeys()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        exit(0)
                    }
                }
            }
        }
    }
    #endif

    private func settingsSection<Content: View>(
        eyebrow: String? = nil,
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
            }

            content()

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
        )
    }

    private var thresholdPresetControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Threshold")
                    .font(.headline)

                Spacer()

                Text(viewModel.selectedProximityPreset.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            Slider(
                value: Binding(
                    get: { Double(viewModel.selectedProximityPresetIndex) },
                    set: { viewModel.setProximityPreset(index: Int($0.rounded())) }
                ),
                in: 0...Double(max(viewModel.proximityPresets.count - 1, 0)),
                step: 1
            )

            HStack(alignment: .top, spacing: 6) {
                ForEach(viewModel.proximityPresets) { preset in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(preset.id == viewModel.selectedProximityPresetIndex ? Color.accentColor : Color(uiColor: .quaternaryLabel))
                            .frame(width: 6, height: 6)

                        Text(preset.title)
                            .font(.caption2.weight(preset.id == viewModel.selectedProximityPresetIndex ? .semibold : .medium))
                            .foregroundStyle(preset.id == viewModel.selectedProximityPresetIndex ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func inlineStateCard(
        icon: String,
        tint: Color,
        title: String,
        body: String,
        showsProgress: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)

                if showsProgress {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(tint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(16)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func primaryActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondaryActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var settingsSlotRows: [SlotPresentationRow] {
        viewModel.completedSlots.map { slot in
            slotPresentationRow(for: slot)
        }
    }

    private func slotPresentationRow(for slot: BleManagementSlot) -> SlotPresentationRow {
        SlotPresentationRow(
            id: slot.id,
            title: slotTitle(for: slot),
            tier: slotTierBadgeText(for: slot.id),
            isActive: slot.id == 0 || slot.used || slot.id == viewModel.localSlotId,
            isCurrentDevice: slot.id == viewModel.localSlotId
        )
    }

    private func slotTitle(for slot: BleManagementSlot) -> String {
        let title = viewModel.slotDisplayName(for: slot).trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return slot.id == 0 ? "Uguisu" : "EMPTY"
        }
        return title
    }

    private func slotTierBadgeText(for slotId: Int) -> String {
        switch slotId {
        case 0:
            return "FOB"
        case 1:
            return "OWNER"
        default:
            return "GUEST"
        }
    }

    private func ownerAccessoryView(for row: SlotPresentationRow) -> AnyView {
        guard let slot = viewModel.completedSlots.first(where: { $0.id == row.id }) else {
            return AnyView(Color.clear.frame(height: 0))
        }

        if slot.id == viewModel.localSlotId {
            return AnyView(
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(slotCardStyle.currentDeviceTint)
                    .offset(x: 2, y: -2)
            )
        }

        if slot.id == 0 {
            return AnyView(Color.clear.frame(height: 0))
        }

        if !slot.used {
            return AnyView(
                Button(action: {
                    viewModel.showGuestProvisionConfirmation(slotId: slot.id)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(slotCardStyle.currentDeviceTint)
                }
                .buttonStyle(.plain)
            )
        }

        return AnyView(
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
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(slotCardStyle.accessoryTint)
            }
        )
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
                doneTitle: "Done - I've Scanned",
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
}

#Preview {
    Text("Settings View Preview")
}

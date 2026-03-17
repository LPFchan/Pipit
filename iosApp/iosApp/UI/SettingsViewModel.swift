import SwiftUI
import Combine
import CoreImage
import Security

#if canImport(shared)
import shared
#endif

@MainActor
final class SettingsViewModel: ObservableObject {
    enum SlotLoadState {
        case idle
        case loading
        case loaded
        case error(String)
    }

    enum AlertType: Identifiable {
        case guestProvisionConfirmation(slotId: Int)
        case replaceConfirmation(slot: BleManagementSlot)
        case deleteConfirmation(slot: BleManagementSlot)
        case renamePrompt(slot: BleManagementSlot)
        case transferConfirmation
        case ownerTransferPinPrompt
        case deletionConfirmation
        case info(title: String, message: String)

        var id: String {
            switch self {
            case .guestProvisionConfirmation(let slotId): return "guestProvision_\(slotId)"
            case .replaceConfirmation(let slot): return "replace_\(slot.id)"
            case .deleteConfirmation(let slot): return "delete_\(slot.id)"
            case .renamePrompt(let slot): return "rename_\(slot.id)"
            case .transferConfirmation: return "transfer"
            case .ownerTransferPinPrompt: return "ownerTransferPin"
            case .deletionConfirmation: return "deletion"
            case .info(let title, _): return "info_\(title)"
            }
        }
    }

    enum QrType: Identifiable {
        case provisioning(title: String, body: String, payload: String, doneTitle: String, deleteLocalKeyOnDone: Bool)
        case transfer(title: String, body: String, payload: String)

        var id: String {
            switch self {
            case .provisioning: return "provisioning"
            case .transfer: return "transfer"
            }
        }
    }

    // MARK: - Dependencies
    private let bleService: IosBleProximityService
    private let onLocalKeyDeleted: () -> Void

#if canImport(shared)
    private let keyStore = KeyStoreManager()
    private let appSettings = AppSettings(manager: IosSettingsManager(userDefaults: UserDefaults.standard))
#endif

    private let qrContext = CIContext()

    // MARK: - Published State
    @Published var slotLoadState: SlotLoadState = .idle
    @Published var loadedSlots: [BleManagementSlot] = []
    @Published var proximityEnabled: Bool = false
    @Published var unlockRssi: Int = -55
    @Published var lockRssi: Int = -95
    @Published var alertType: AlertType?
    @Published var showQrSheet: QrType?
    @Published var renameText: String = ""
    @Published var transferPinText: String = ""
    @Published var selectedGuestSlotId: Int = 0
    @Published var selectedSlot: BleManagementSlot?

    private var slotLoadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        bleService: IosBleProximityService,
        onLocalKeyDeleted: @escaping () -> Void,
    ) {
        self.bleService = bleService
        self.onLocalKeyDeleted = onLocalKeyDeleted
        
        Task {
            await initialize()
        }
    }

    private func initialize() {
        loadStoredProximitySettings()
        bindBleState()
    }

    deinit {
        slotLoadTask?.cancel()
        bleService.disconnectManagement()
    }

    // MARK: - Computed Properties
    var isOwnerView: Bool {
        localSlotId == 1
    }

    var localSlotId: Int? {
        resolveLocalPhoneSlotId()
    }

    var completedSlots: [BleManagementSlot] {
        var slotsById: [Int: BleManagementSlot] = [:]
        for slot in loadedSlots {
            if slotsById[slot.id] == nil {
                slotsById[slot.id] = slot
            }
        }
        return (0...3).map { slotId in
            slotsById[slotId] ?? BleManagementSlot(
                id: slotId,
                used: false,
                counter: 0,
                name: slotId == 0 ? "Uguisu" : ""
            )
        }
    }

    var headerSubtitle: String {
        switch localSlotId {
        case 1:
            return "Owner controls, guest slot management, transfer QR export, and persisted proximity preferences."
        case 2, 3:
            return "Guest controls, transfer QR export, and a read-only slot overview."
        default:
            return "Read-only settings until a local phone key is available."
        }
    }

    var statusText: String {
        let managementState = bleService.managementState
        switch slotLoadState {
        case .idle:
            return "Opening a fresh management session when Settings appears."
        case .loading:
            return managementStatusText(for: managementState)
        case .loaded:
            return "Loaded \(completedSlots.count) slots over the management transport."
        case .error:
            return managementStatusText(for: managementState)
        }
    }

    var showRetry: Bool {
        if case .error = slotLoadState { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = slotLoadState { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = slotLoadState { return message }
        return nil
    }

    // MARK: - Public Actions
    func onAppear() {
        if case .idle = slotLoadState {
            loadSlots()
        }
    }

    func onDisappear() {
        bleService.disconnectManagement()
    }

    func retryLoadSlots() {
        loadSlots()
    }

    func backgroundUnlockToggled() {
#if canImport(shared)
        appSettings.isProximityEnabled = proximityEnabled
        updateProximityUi()
#endif
    }

    func unlockRssiChanged(_ value: Double) {
#if canImport(shared)
        let rounded = Int32(value.rounded())
        let clamped = max(-95, min(-35, Int(rounded)))
        unlockRssi = clamped
        appSettings.unlockRssi = Int32(clamped)

        let maxLock = clamped - 10
        if lockRssi > maxLock {
            lockRssi = maxLock
            appSettings.lockRssi = Int32(maxLock)
        }
        updateProximityUi()
#endif
    }

    func lockRssiChanged(_ value: Double) {
#if canImport(shared)
        let rounded = Int32(value.rounded())
        let maxLock = unlockRssi - 10
        let clamped = max(-105, min(maxLock, Int(rounded)))
        lockRssi = clamped
        appSettings.lockRssi = Int32(clamped)
        updateProximityUi()
#endif
    }

    // MARK: - Alert Actions
    func showGuestProvisionConfirmation(slotId: Int) {
        selectedGuestSlotId = slotId
        alertType = .guestProvisionConfirmation(slotId: slotId)
    }

    func showReplaceConfirmation(for slot: BleManagementSlot) {
        selectedSlot = slot
        alertType = .replaceConfirmation(slot: slot)
    }

    func showDeleteConfirmation(for slot: BleManagementSlot) {
        selectedSlot = slot
        alertType = .deleteConfirmation(slot: slot)
    }

    func showRenamePrompt(for slot: BleManagementSlot) {
        selectedSlot = slot
        renameText = slotDisplayName(for: slot)
        alertType = .renamePrompt(slot: slot)
    }

    func showTransferConfirmation() {
        guard localSlotId != nil else {
            alertType = .info(title: "No Local Key", message: "This device does not currently store a phone key.")
            return
        }
        alertType = .transferConfirmation
    }

    func proceedWithTransfer() {
        if localSlotId == 1 {
            alertType = .ownerTransferPinPrompt
        } else {
            Task {
                await presentTransferQr(pin: nil)
            }
        }
    }

    func proceedWithOwnerTransfer() {
        let pin = transferPinText.filter(\.isNumber)
        if pin.count != 6 {
            alertType = .info(title: "PIN Required", message: "Owner transfer requires your 6-digit management PIN.")
            return
        }
        Task {
            await presentTransferQr(pin: pin)
        }
    }

    func confirmGuestProvisioning() {
        provisionGuestSlot(slotId: selectedGuestSlotId, replaceExisting: false)
    }

    func confirmReplace() {
        guard let slot = selectedSlot else { return }
        provisionGuestSlot(slotId: slot.id, replaceExisting: true)
    }

    func confirmDelete() {
        guard let slot = selectedSlot else { return }
        Task {
            do {
                try await performOwnerWrite(description: "Revoking slot \(slot.id)") {
                    _ = try await self.bleService.revoke(slotId: slot.id)
                }
            } catch {
                alertType = .info(title: "Revoking slot \(slot.id)", message: error.localizedDescription)
            }
        }
    }

    func confirmRename() {
        guard let slot = selectedSlot else { return }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        Task {
            do {
                try await performOwnerWrite(description: "Renaming slot \(slot.id)") {
                    _ = try await self.bleService.rename(slotId: slot.id, name: String(newName.prefix(24)))
                }
            } catch {
                alertType = .info(title: "Renaming slot \(slot.id)", message: error.localizedDescription)
            }
        }
    }

    func confirmLocalDeletion() {
        guard let localSlotId else { return }
#if canImport(shared)
        keyStore.deleteKey(slotId: Int32(localSlotId))
#endif
        onLocalKeyDeleted()
    }

    func forceResetAllKeys() {
#if canImport(shared)
        for i in 1...6 {
            keyStore.deleteKey(slotId: Int32(i))
        }
#endif
    }


    // MARK: - Slot Management Helpers
    func shouldShowSlotControl(for slot: BleManagementSlot) -> Bool {
        guard isOwnerView else { return false }
        if slot.id == 1 || slot.id == localSlotId || slot.id == 0 {
            return false
        }
        return slot.id == 2 || slot.id == 3
    }

    func slotControlText(for slot: BleManagementSlot) -> String {
        slot.used ? "ellipsis.circle" : ""
    }

    func slotBadge(for slot: BleManagementSlot) -> String {
        if slot.id == localSlotId {
            return "THIS PHONE"
        }
        if slot.id == 0 {
            return "HARDWARE"
        }
        return slot.used ? "ACTIVE" : "EMPTY"
    }

    func slotTierLabel(for slotId: Int) -> String {
        switch slotId {
        case 0: return "HARDWARE KEY"
        case 1: return "OWNER"
        case 2, 3: return "GUEST"
        default: return "PHONE SLOT"
        }
    }

    func slotDisplayName(for slot: BleManagementSlot) -> String {
        if !slot.name.isEmpty {
            return slot.name
        }
        if slot.id == 0 {
            return "Uguisu"
        }
        return slot.used ? "Provisioned" : "Empty"
    }

    func slotDetailText(for slot: BleManagementSlot) -> String {
        if slot.id == 0 {
            return "Hardware slot. Manage via Whimbrel or Android USB OTG."
        }
        return slot.used ? "Counter \(slot.counter)" : "Available for provisioning"
    }

    func slotDetailTextAbout(for slot: BleManagementSlot) -> String {
        if slot.id == 0 {
            return "Hardware slot"
        }
        return slot.used ? "Counter \(slot.counter)" : "Available for provisioning"
    }

    // MARK: - Private Methods
    private func bindBleState() {
        bleService.$managementState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Update UI when BLE state changes
            }
            .store(in: &cancellables)
    }

    private func loadStoredProximitySettings() {
#if canImport(shared)
        proximityEnabled = appSettings.isProximityEnabled
        unlockRssi = Int(appSettings.unlockRssi)
        lockRssi = Int(appSettings.lockRssi)
        updateProximityUi()
#endif
    }

    private func updateProximityUi() {
#if canImport(shared)
        let unlockRssi = Int(appSettings.unlockRssi)
        let lockRssi = Int(appSettings.lockRssi)

        self.unlockRssi = unlockRssi
        self.lockRssi = lockRssi
        objectWillChange.send()
#endif
    }

    private func loadSlots() {
        slotLoadTask?.cancel()
        slotLoadState = .loading
        loadedSlots = []

        slotLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.bleService.connectManagement(mode: .standard)
                let response = try await self.bleService.requestSlots()
                try Task.checkCancellation()
                self.loadedSlots = response.slots.sorted { $0.id < $1.id }
                self.slotLoadState = .loaded
            } catch is CancellationError {
                bleService.disconnectManagement()
            } catch {
                bleService.disconnectManagement()
                self.slotLoadState = .error(error.localizedDescription)
            }
        }
    }

    private func provisionGuestSlot(slotId: Int, replaceExisting: Bool) {
        Task {
            do {
                let key = try randomBytes(count: 16)
                let slotName = guestSlotDefaultName(slotId)
                try await performOwnerWrite(description: replaceExisting ? "Replacing slot \(slotId)" : "Provisioning slot \(slotId)") {
                    if replaceExisting {
                        _ = try await self.bleService.revoke(slotId: slotId)
                    }
                    _ = try await self.bleService.provision(slotId: slotId, key: key, counter: 0, name: slotName)
                }

                let qrPayload = buildPlainProvisioningUri(slotId: slotId, key: key, counter: 0, name: slotName)
                await MainActor.run { [weak self] in
                    self?.showQrSheet = .provisioning(
                        title: replaceExisting ? "Replacement Key Ready" : "Guest Key Ready",
                        body: "Scan this on the guest phone. No PIN is required for guest provisioning.",
                        payload: qrPayload,
                        doneTitle: "Done",
                        deleteLocalKeyOnDone: false
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.alertType = .info(title: "Guest Provisioning Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func performOwnerWrite(description: String, action: @escaping () async throws -> Void) async throws {
        do {
            try await self.bleService.connectManagement(mode: .standard)
            _ = try await self.bleService.identify(slotId: 1)
            try await action()
            loadSlots()
        } catch {
            throw error
        }
    }

    private func presentTransferQr(pin: String?) async {
        do {
            let payload = try await buildMigrationPayload(pin: pin)
            await MainActor.run { [weak self] in
                self?.showQrSheet = .transfer(
                    title: "Transfer to New Phone",
                    body: payload.body,
                    payload: payload.qrPayload
                )
            }
        } catch {
            await MainActor.run { [weak self] in
                self?.alertType = .info(title: "Transfer Failed", message: error.localizedDescription)
            }
        }
    }

    private func buildMigrationPayload(pin: String?) async throws -> (qrPayload: String, body: String) {
#if canImport(shared)
        guard let localSlotId else {
            throw IosBleProximityServiceError.system("No local key is stored on this device")
        }
        guard let storedKey = keyStore.loadKey(slotId: Int32(localSlotId)) else {
            throw IosBleProximityServiceError.system("No local key is stored for slot \(localSlotId)")
        }

        let keyData = data(from: storedKey)
        let counter = keyStore.loadCounter(slotId: Int32(localSlotId))
        let slot = completedSlots.first(where: { $0.id == localSlotId })
        let slotName = String((slot?.name.isEmpty == false ? slot?.name : defaultSlotName(for: localSlotId, used: true))?.prefix(24) ?? "Phone")

        if localSlotId == 1 {
            guard let pin, pin.count == 6 else {
                throw IosBleProximityServiceError.system("Owner transfer requires your 6-digit PIN")
            }
            try await ensureCryptoInitialized()
            let salt = try randomBytes(count: Int(ImmoCrypto.shared.QR_SALT_LEN))
            let derivedKey = ImmoCrypto.shared.deriveKey(
                pin: pin,
                salt: kotlinByteArray(from: Array(salt)),
                params: defaultArgonParams()
            )
            let encryptedKey = ImmoCrypto.shared.encryptProvisionedKey(
                derivedKey: derivedKey,
                salt: kotlinByteArray(from: Array(salt)),
                slotKey: kotlinByteArray(from: Array(keyData))
            )
            return (
                buildEncryptedProvisioningUri(
                    slotId: localSlotId,
                    salt: salt,
                    encryptedKey: data(from: encryptedKey),
                    counter: counter,
                    name: slotName
                ),
                "Scan this on your new phone. The new phone will ask for your management PIN before importing the owner key."
            )
        }

        return (
            buildPlainProvisioningUri(slotId: localSlotId, key: keyData, counter: counter, name: slotName),
            "Scan this on your new phone. Guest transfers stay plaintext and do not require a PIN."
        )
#else
        throw IosBleProximityServiceError.unsupported("Shared framework is unavailable for secure transfer")
#endif
    }

    private func buildPlainProvisioningUri(slotId: Int, key: Data, counter: UInt32, name: String) -> String {
        var components = URLComponents()
        components.scheme = "immogen"
        components.host = "prov"
        components.queryItems = [
            URLQueryItem(name: "slot", value: String(slotId)),
            URLQueryItem(name: "key", value: key.hexEncodedString()),
            URLQueryItem(name: "ctr", value: String(counter)),
            URLQueryItem(name: "name", value: name)
        ]
        return components.string ?? "immogen://prov"
    }

    private func buildEncryptedProvisioningUri(slotId: Int, salt: Data, encryptedKey: Data, counter: UInt32, name: String) -> String {
        var components = URLComponents()
        components.scheme = "immogen"
        components.host = "prov"
        components.queryItems = [
            URLQueryItem(name: "slot", value: String(slotId)),
            URLQueryItem(name: "salt", value: salt.hexEncodedString()),
            URLQueryItem(name: "ekey", value: encryptedKey.hexEncodedString()),
            URLQueryItem(name: "ctr", value: String(counter)),
            URLQueryItem(name: "name", value: name)
        ]
        return components.string ?? "immogen://prov"
    }

    private func resolveLocalPhoneSlotId() -> Int? {
#if canImport(shared)
        for slotId in 1...3 {
            if keyStore.loadKey(slotId: Int32(slotId)) != nil {
                return slotId
            }
        }
#endif
        return nil
    }

    func guestSlotDefaultName(_ slotId: Int) -> String {
        switch slotId {
        case 2: return "Guest 1"
        case 3: return "Guest 2"
        default: return "Guest"
        }
    }

    private func defaultSlotName(for slotId: Int, used: Bool) -> String {
        switch slotId {
        case 0: return "Uguisu"
        case 1: return used ? "Owner Phone" : "Owner"
        case 2: return used ? "Guest 1" : "Empty"
        case 3: return used ? "Guest 2" : "Empty"
        default: return used ? "Provisioned" : "Empty"
        }
    }

    private func managementStatusText(for state: BleManagementSessionState) -> String {
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

    private func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            throw IosBleProximityServiceError.system("Secure random generation failed")
        }
        return Data(bytes)
    }

#if canImport(shared)
    private func ensureCryptoInitialized() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ImmoCrypto.shared.initialize { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func defaultArgonParams() -> ImmoCrypto.Argon2Params {
        ImmoCrypto.Argon2Params(
            parallelism: 1,
            outputLength: UInt32(ImmoCrypto.shared.QR_KEY_LEN),
            requestedMemoryKiB: 262_144,
            iterations: 3,
            key: kotlinByteArray(from: []),
            associatedData: kotlinByteArray(from: []),
            variant: ImmoCrypto.ArgonVariant.argon2id
        )
    }

    private func kotlinByteArray(from bytes: [UInt8]) -> KotlinByteArray {
        let array = KotlinByteArray(size: Int32(bytes.count))
        for (index, value) in bytes.enumerated() {
            array.set(index: Int32(index), value: Int8(bitPattern: value))
        }
        return array
    }

    private func data(from array: KotlinByteArray) -> Data {
        Data((0..<Int(array.size)).map { UInt8(bitPattern: array.get(index: Int32($0))) })
    }
#endif

    func generateQrImage(payload: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = qrContext.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

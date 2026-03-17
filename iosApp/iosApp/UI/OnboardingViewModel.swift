import Foundation
import Combine
import UIKit
import Security

#if canImport(shared)
import shared
#endif

// MARK: - Models

struct ProvisioningSuccess {
    let slotId: Int
    let counter: UInt32
    let name: String
}

struct PendingProvisioningMaterial {
    let slotId: Int
    let key: Data
    let counter: UInt32
    let name: String
    let statusText: String
}

enum ParsedProvisioningPayload {
    case guest(slotId: Int, key: Data, counter: UInt32, name: String)
    case encrypted(slotId: Int, salt: Data, encryptedKey: Data, counter: UInt32, name: String)
}

enum ProvisioningQrParseError: LocalizedError {
    case missingField(String)
    case invalidField(String, String)
    case unsupportedVariant(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let field): return "Missing required field: \(field)"
        case .invalidField(let field, let detail): return "Invalid \(field): \(detail)"
        case .unsupportedVariant(let detail): return detail
        }
    }
}

enum OnboardingState {
    case camera
    case pin
    case importing
    case recovery
    case locationPermission
    case success
}

enum RecoveryState {
    case waitingForWindowOpen
    case connecting
    case loadingSlots
    case ownerProof
    case recovering
    case slotPicker
    case error
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    private let bleService: IosBleProximityService
    private let onProvisioned: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var recoveryTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    
    @Published var onboardingState: OnboardingState
    @Published var recoveryState: RecoveryState = .waitingForWindowOpen
    @Published var recoverySlots: [BleManagementSlot] = []
    @Published var successOverviewSlots: [BleManagementSlot] = []
    @Published var selectedSlotId: Int?
    
    @Published var recoveryErrorMessage: String?
    @Published var scanErrorMessage: String?
    @Published var pinErrorMessage: String?
    
    @Published var pinCode: String = ""
    @Published var isProvisioningInFlight = false
    @Published var isScanLocked = false
    
    private var pendingEncryptedPayload: ParsedProvisioningPayload?
    private var pendingProvisioningMaterial: PendingProvisioningMaterial?
    @Published var provisioningSuccess: ProvisioningSuccess?
    
#if canImport(shared)
    private let keyStore = KeyStoreManager()
#endif

    var statusText: String {
        guard onboardingState == .recovery else { return "" }
        switch recoveryState {
        case .waitingForWindowOpen: return "Looking for Guillemot with window open..."
        case .connecting: return "Connecting to scope over GATT..."
        case .loadingSlots: return "Loading available slots..."
        case .ownerProof: return "Please enter your PIN."
        case .recovering: return "Recovering slot..."
        case .slotPicker:
            if recoverySlots.isEmpty {
                return "Device memory is completely empty; nothing to recover."
            }
            if selectedSlotId != nil {
                return "Ready to recover."
            }
            return "Please select your phone's previous slot from the list."
        case .error: return "Recovery failed."
        }
    }
    
    var importingStatusText: String {
        return pendingProvisioningMaterial?.statusText ?? "Importing your phone key..."
    }

    init(bleService: IosBleProximityService, initialState: OnboardingState = .camera, onProvisioned: @escaping () -> Void) {
        self.bleService = bleService
        self.onboardingState = initialState
        self.onProvisioned = onProvisioned
        
        bindBleState()
    }
    
    func onDisappear() {
        recoveryTask?.cancel()
        importTask?.cancel()
        bleService.stopWindowOpenScan()
        bleService.disconnectManagement()
    }
    
    private func bindBleState() {
        bleService.$managementState
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.handleManagementStateChange(state)
                }
            }
            .store(in: &cancellables)
            
        bleService.$isWindowOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOpen in
                self?.handleWindowOpenChange(isOpen)
            }
            .store(in: &cancellables)
            
        bleService.$locationAuthorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self, self.onboardingState == .locationPermission else { return }
                if status == .authorizedAlways || status == .authorizedWhenInUse {
                    self.onboardingState = .success
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleManagementStateChange(_ state: BleManagementSessionState?) {
        guard onboardingState == .recovery, let state = state else { return }
        switch (recoveryState, state.connectionState) {
        case (.connecting, .ready):
            recoveryErrorMessage = nil
            recoveryState = .loadingSlots
            Task {
                do {
                    let response = try await bleService.requestSlots()
                    await MainActor.run {
                        self.recoverySlots = response.slots
                        self.selectedSlotId = self.recoverySlots.first?.id
                        self.recoveryState = .slotPicker
                    }
                } catch {
                    await MainActor.run {
                        self.recoveryErrorMessage = error.localizedDescription
                        self.recoveryState = .error
                    }
                }
            }
        case (_, .error):
            recoveryErrorMessage = state.lastError
            recoveryState = .error
        case (.connecting, .disconnected):
            recoveryErrorMessage = "Failed to connect to device."
            recoveryState = .error
        default: break
        }
    }
    
    private func handleWindowOpenChange(_ isWindowOpen: Bool) {
        guard onboardingState == .recovery, recoveryState == .waitingForWindowOpen else { return }
        if isWindowOpen {
            bleService.stopWindowOpenScan()
            recoveryState = .connecting
            Task {
                try? await bleService.connectManagement(mode: .windowOpenRecovery)
            }
        }
    }
    
    func startRecoveryFlow() {
        scanErrorMessage = nil
        isScanLocked = true
        onboardingState = .recovery
        recoveryState = .waitingForWindowOpen
        recoveryErrorMessage = nil
        selectedSlotId = nil
        recoverySlots = []
        bleService.startWindowOpenScan()
    }
    
    func cancelRecovery() {
        recoveryTask?.cancel()
        bleService.stopWindowOpenScan()
        bleService.disconnectManagement()
        isScanLocked = false
        scanErrorMessage = nil
        onboardingState = .camera
    }

    func retryRecovery() {
        recoveryErrorMessage = nil
        if bleService.isWindowOpen {
            recoveryState = .connecting
            Task {
                try? await bleService.connectManagement(mode: .windowOpenRecovery)
            }
        } else {
            recoveryState = .waitingForWindowOpen
            bleService.startWindowOpenScan()
        }
    }

    func selectSlot(_ slotId: Int) {
        selectedSlotId = slotId
    }

    func beginSelectedSlotRecovery() {
        guard let id = selectedSlotId, let slot = recoverySlots.first(where: { $0.id == id }) else { return }
        if slot.id == 1 {
            recoveryState = .ownerProof
            pinCode = ""
            pinErrorMessage = nil
        } else {
            beginSelectedSlotRecoveryForSlot(slot)
        }
    }
    
    func confirmPin() {
        guard onboardingState == .pin else {
            // Pin for recovery case
            if onboardingState == .recovery && recoveryState == .ownerProof {
                guard let id = selectedSlotId, let slot = recoverySlots.first(where: { $0.id == id }) else { return }
                guard pinCode.count == 6 else {
                    pinErrorMessage = "PIN must be 6 digits"
                    return
                }
                beginSelectedSlotRecoveryForSlot(slot)
            }
            return
        }

        // Pin for Encrypted Payload setup
        guard let payload = pendingEncryptedPayload else { return }
        guard case .encrypted(let slotId, let salt, let encryptedKey, let counter, let name) = payload else { return }
        
        guard pinCode.count == 6 else {
            pinErrorMessage = "PIN must be exactly 6 digits"
            return
        }
        
        pinErrorMessage = nil
        isProvisioningInFlight = true
        
        Task {
            do {
                let decryptedKey = try await decryptProvisionedKey(pin: pinCode, salt: salt, encryptedKey: encryptedKey)
                await MainActor.run {
                    self.isProvisioningInFlight = false
                    self.startImportTransition(
                        slotId: slotId,
                        key: decryptedKey,
                        counter: counter,
                        name: name,
                        statusText: "Importing your phone key..."
                    )
                }
            } catch {
                await MainActor.run {
                    self.isProvisioningInFlight = false
                    self.pinErrorMessage = "Incorrect PIN or corrupted key: \(error.localizedDescription)"
                }
            }
        }
    }

    private func beginSelectedSlotRecoveryForSlot(_ slot: BleManagementSlot) {
        if slot.id == 1 && recoveryState != .ownerProof {
            recoveryErrorMessage = nil
            recoveryState = .ownerProof
            return
        }

        recoveryErrorMessage = nil
        recoveryState = .recovering
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self else { return }

            do {
                let recoveryKey = try self.generateRecoveryKey()
                let recoveryName = self.defaultRecoveredSlotName(for: slot)
                let response = try await self.bleService.recover(
                    slotId: slot.id,
                    key: recoveryKey,
                    counter: 0,
                    name: recoveryName
                )
                self.bleService.disconnectManagement()

                await MainActor.run {
                    let finalName = response.name ?? recoveryName
                    let finalCounter = response.counter ?? 0
                    self.successOverviewSlots = self.recoverySlots.map { existingSlot in
                        if existingSlot.id == slot.id {
                            return BleManagementSlot(id: slot.id, used: true, counter: finalCounter, name: finalName)
                        }
                        return existingSlot
                    }
                    self.saveProvisionedMaterial(
                        slotId: Int(slot.id),
                        key: recoveryKey,
                        counter: finalCounter,
                        name: finalName
                    )
                    self.recoveryTask = nil
                }
            } catch is CancellationError {
                self.bleService.disconnectManagement()
                await MainActor.run {
                    self.recoveryTask = nil
                }
            } catch {
                await MainActor.run {
                    if slot.id == 1 && self.isOwnerRecoveryPairingError(error) {
                        self.pinErrorMessage = "Incorrect owner PIN"
                        self.recoveryState = .ownerProof
                    } else {
                        self.bleService.disconnectManagement()
                        self.recoveryErrorMessage = error.localizedDescription
                        self.recoveryState = .error
                    }
                    self.recoveryTask = nil
                }
            }
        }
    }
    private func saveProvisionedMaterial(slotId: Int, key: Data, counter: UInt32, name: String) {
        #if canImport(shared)
        do {
            keyStore.saveKey(
                slotId: Int32(slotId),
                key: self.kotlinByteArray(from: Array(key))
            )
            keyStore.saveCounter(slotId: Int32(slotId), counter: counter)
        } catch {
            print("Failed to save to keychain: \(error)")
            // Optionally handle UI error for keychain write
            onboardingState = .camera
            isScanLocked = false
            return
        }
        #endif
        
        self.provisioningSuccess = ProvisioningSuccess(slotId: slotId, counter: counter, name: name)
        
        // Let Location auth check if we need to proceed.
        if bleService.locationAuthorizationStatus == .authorizedAlways {
            self.onboardingState = .success
        } else {
            self.onboardingState = .locationPermission
        }
    }

    private func startImportTransition(slotId: Int, key: Data, counter: UInt32, name: String, statusText: String) {
        pendingProvisioningMaterial = PendingProvisioningMaterial(
            slotId: slotId,
            key: key,
            counter: counter,
            name: name,
            statusText: statusText
        )
        importTask?.cancel()
        onboardingState = .importing
        importTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.onboardingState == .importing,
                      let pending = self.pendingProvisioningMaterial else { return }
                self.saveProvisionedMaterial(
                    slotId: pending.slotId,
                    key: pending.key,
                    counter: pending.counter,
                    name: pending.name
                )
            }
        }
    }

    func requestLocationPermission() {
        switch bleService.locationAuthorizationStatus {
        case .authorizedAlways:
            onboardingState = .success
        case .denied, .restricted:
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                if let u = URL(string: url.absoluteString) { UIApplication.shared.open(u) }
            }
            #endif
        default:
            bleService.requestAlwaysLocationAuthorization()
        }
    }
    
    func skipLocationPermission() {
        onboardingState = .success
    }
    
    func returnToCamera() {
        isScanLocked = false
        scanErrorMessage = nil
        onboardingState = .camera
    }

    func finishOnboarding() {
        onProvisioned()
    }
    
    func handleScannedQr(_ rawValue: String) {
        guard onboardingState == .camera, !isScanLocked else { return }

        let payload: ParsedProvisioningPayload
        do {
            guard let parsedPayload = try parseProvisioningQrIfNeeded(rawValue) else { return }
            payload = parsedPayload
        } catch {
            scanErrorMessage = error.localizedDescription
            return
        }

        scanErrorMessage = nil
        isScanLocked = true

        switch payload {
        case .guest(let slotId, let key, let counter, let name):
            startImportTransition(
                slotId: slotId,
                key: key,
                counter: counter,
                name: name,
                statusText: "Importing your phone key..."
            )
        case .encrypted:
            pendingEncryptedPayload = payload
            pinCode = ""
            pinErrorMessage = nil
            onboardingState = .pin
        }
    }

    // MARK: - Handlers & Parsing
    
    private func parseProvisioningQrIfNeeded(_ rawValue: String) throws -> ParsedProvisioningPayload? {
        let prefix = "immogen://prov?"
        guard rawValue.hasPrefix(prefix) else { return nil }

        let query = String(rawValue.dropFirst(prefix.count))
        let params = try parseQuery(query)
        let slotId = try parseSlotId(params["slot"])
        let counter = try parseCounter(params["ctr"])
        let name = params["name"] ?? ""

        if let keyHex = params["key"], params["salt"] == nil, params["ekey"] == nil {
            return .guest(
                slotId: slotId,
                key: try parseHex(field: "key", value: keyHex, expectedLength: 16),
                counter: counter,
                name: name
            )
        }

        if let saltHex = params["salt"], let encryptedKeyHex = params["ekey"], params["key"] == nil {
            return .encrypted(
                slotId: slotId,
                salt: try parseHex(field: "salt", value: saltHex, expectedLength: 16),
                encryptedKey: try parseHex(field: "ekey", value: encryptedKeyHex, expectedLength: 24),
                counter: counter,
                name: name
            )
        }

        if params["key"] != nil {
            throw ProvisioningQrParseError.unsupportedVariant("Provisioning QR cannot mix guest and encrypted owner fields")
        }

        throw ProvisioningQrParseError.unsupportedVariant("Provisioning QR must contain either key or salt+ekey fields")
    }

    private func parseQuery(_ query: String) throws -> [String: String] {
        var dict: [String: String] = [:]
        let pairs = query.split(separator: "&")
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0])
            let value = try percentDecode(String(kv[1]))
            dict[key] = value
        }
        return dict
    }

    private func percentDecode(_ value: String) throws -> String {
        guard let decoded = value.removingPercentEncoding else {
            throw ProvisioningQrParseError.unsupportedVariant("Invalid percent encoding")
        }
        return decoded
    }

    private func parseSlotId(_ raw: String?) throws -> Int {
        guard let raw = raw, let slotId = Int(raw), slotId >= 0, slotId < 255 else {
            throw ProvisioningQrParseError.missingField("slot")
        }
        return slotId
    }

    private func parseCounter(_ raw: String?) throws -> UInt32 {
        guard let raw = raw, let counter = UInt32(raw) else {
            throw ProvisioningQrParseError.missingField("ctr")
        }
        return counter
    }

    private func parseHex(field: String, value: String, expectedLength: Int) throws -> Data {
        let clean = value.replacingOccurrences(of: " ", with: "")
        guard clean.count == expectedLength * 2 else {
            throw ProvisioningQrParseError.invalidField(field, "expected \(expectedLength) bytes")
        }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            if nextIndex <= clean.endIndex {
                let byteString = String(clean[index..<nextIndex])
                if let byte = UInt8(byteString, radix: 16) {
                    data.append(byte)
                } else {
                    throw ProvisioningQrParseError.invalidField(field, "not valid hex")
                }
            }
            index = nextIndex
        }
        return data
    }
    
    private func generateRecoveryKey() throws -> Data {
        var key = Data(count: 16)
        let result = key.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        if result != errSecSuccess { throw URLError(.unknown) }
        return key
    }
    
    private func defaultArgonParams() -> ImmoCrypto.Argon2Params {
        ImmoCrypto.Argon2Params(
            parallelism: 1,
            outputLength: UInt32(ImmoCrypto.shared.QR_KEY_LEN),
            requestedMemoryKiB: 262_144,
            iterations: 3,
            key: self.kotlinByteArray(from: []),
            associatedData: self.kotlinByteArray(from: []),
            variant: ImmoCrypto.ArgonVariant.argon2id
        )
    }

    private func decryptProvisionedKey(pin: String, salt: Data, encryptedKey: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            ImmoCrypto.shared.decryptProvisionedKeyAsync(
                pin: pin,
                salt: self.kotlinByteArray(from: Array(salt)),
                encryptedKey: self.kotlinByteArray(from: Array(encryptedKey)),
                params: self.defaultArgonParams()
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: self.data(from: result))
                } else {
                    continuation.resume(throwing: IosBleProximityServiceError.system("Provisioning decrypt returned no result"))
                }
            }
        }
    }

    private func ensureCryptoInitialized() async throws {
        if ImmoCrypto.shared.isInitialized() {
            return
        }
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
    private func isOwnerRecoveryPairingError(_ error: Error) -> Bool {
        return error.localizedDescription.lowercased().contains("unlikely") || error.localizedDescription.lowercased().contains("auth failed")
    }

    private func kotlinByteArray(from bytes: [UInt8]) -> KotlinByteArray {
        let ktArray = KotlinByteArray(size: Int32(bytes.count))
        for (i, byte) in bytes.enumerated() {
            ktArray.set(index: Int32(i), value: Int8(bitPattern: byte))
        }
        return ktArray
    }
    
    private func data(from array: KotlinByteArray) -> Data {
        var bytes = [UInt8]()
        for i in 0..<array.size {
            bytes.append(UInt8(bitPattern: array.get(index: i)))
        }
        return Data(bytes)
    }
    
    func defaultRecoveredSlotName(for slot: BleManagementSlot) -> String {
        return "Recovered \(slot.name)"
    }

    func slotTierLabel(for slotId: Int) -> String {
        return slotId == 0 ? "Owner" : "Guest"
    }
}

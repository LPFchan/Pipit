import Foundation
import Combine
import CoreLocation
import CoreBluetooth

#if canImport(shared)
import shared
#endif

@objc public enum ConnectionState: Int {
    case disconnected = 0
    case scanning
    case connecting
    case connectedLocked
    case connectedUnlocked
}

public enum BleManagementConnectMode: Equatable {
    case standard
    case windowOpenRecovery
}

public enum BleManagementSessionConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case discovering
    case ready
    case error
}

public struct BleManagementSessionState: Equatable {
    public var connectionState: BleManagementSessionConnectionState
    public var mode: BleManagementConnectMode?
    public var peripheralIdentifier: UUID?
    public var peripheralName: String?
    public var lastError: String?

    public init(
        connectionState: BleManagementSessionConnectionState = .disconnected,
        mode: BleManagementConnectMode? = nil,
        peripheralIdentifier: UUID? = nil,
        peripheralName: String? = nil,
        lastError: String? = nil
    ) {
        self.connectionState = connectionState
        self.mode = mode
        self.peripheralIdentifier = peripheralIdentifier
        self.peripheralName = peripheralName
        self.lastError = lastError
    }
}

public struct BleManagementSlot: Equatable {
    public let id: Int
    public let used: Bool
    public let counter: UInt32
    public let name: String

    public init(id: Int, used: Bool, counter: UInt32, name: String) {
        self.id = id
        self.used = used
        self.counter = counter
        self.name = name
    }
}

public struct BleManagementCommandSuccess: Equatable {
    public let raw: String
    public let slotId: Int?
    public let name: String?
    public let counter: UInt32?
    public let message: String?

    public init(raw: String, slotId: Int? = nil, name: String? = nil, counter: UInt32? = nil, message: String? = nil) {
        self.raw = raw
        self.slotId = slotId
        self.name = name
        self.counter = counter
        self.message = message
    }
}

public struct BleManagementSlotsResponse: Equatable {
    public let raw: String
    public let slots: [BleManagementSlot]

    public init(raw: String, slots: [BleManagementSlot]) {
        self.raw = raw
        self.slots = slots
    }
}

public struct BleManagementErrorResponse: Error, Equatable {
    public let raw: String
    public let code: String?
    public let message: String?

    public init(raw: String, code: String? = nil, message: String? = nil) {
        self.raw = raw
        self.code = code
        self.message = message
    }
}

public enum BleManagementResponse: Equatable {
    case success(BleManagementCommandSuccess)
    case slots(BleManagementSlotsResponse)
    case error(BleManagementErrorResponse)
}

public enum IosBleProximityServiceError: LocalizedError {
    case bluetoothUnavailable(String)
    case busy(String)
    case scanTimedOut(String)
    case connectTimedOut
    case requestTimedOut(String)
    case notConnected
    case invalidSlot(Int)
    case invalidKeyLength(Int)
    case missingKey(Int)
    case counterOverflow(Int)
    case invalidResponse(String)
    case missingCharacteristic(String)
    case unsupported(String)
    case system(String)

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let message):
            return message
        case .busy(let message):
            return message
        case .scanTimedOut(let message):
            return message
        case .connectTimedOut:
            return "Management connection timed out"
        case .requestTimedOut(let commandName):
            return "Management request timed out: \(commandName)"
        case .notConnected:
            return "Management session is not connected"
        case .invalidSlot(let slotId):
            return "Slot ID must be between 0 and 3, got \(slotId)"
        case .invalidKeyLength(let length):
            return "Key must be exactly 16 bytes, got \(length) bytes"
        case .missingKey(let slotId):
            return "No key stored for slot \(slotId)"
        case .counterOverflow(let slotId):
            return "Counter overflow for slot \(slotId)"
        case .invalidResponse(let message):
            return message
        case .missingCharacteristic(let message):
            return message
        case .unsupported(let message):
            return message
        case .system(let message):
            return message
        }
    }
}

@objc public class IosBleProximityService: NSObject, ObservableObject {
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var rssi: Int = 0
    @Published public private(set) var isWindowOpen: Bool = false
    @Published public private(set) var lastCommandPayloadHex: String?
    @Published public private(set) var managementState: BleManagementSessionState = .init()

    private let locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?

    private var passiveScanMode: PassiveScanMode = .none
    private var activeDiscoveryRequest: DiscoveryRequest?
    private var pendingPoweredOnContinuations: [CheckedContinuation<Void, Error>] = []
    private var pendingScanContinuation: CheckedContinuation<CBPeripheral, Error>?
    private var pendingConnectionReadyContinuation: CheckedContinuation<Void, Error>?
    private var pendingWriteContinuation: CheckedContinuation<Void, Error>?
    private var pendingResponseContinuation: CheckedContinuation<Data, Error>?

    private var connectedPeripheral: CBPeripheral?
    private var managementPeripheral: CBPeripheral?
    private var lastStandardPeripheral: CBPeripheral?
    private var lastWindowOpenPeripheral: CBPeripheral?
    private var lastAdvertisedConnectionState: ConnectionState = .disconnected

    private var proximityService: CBService?
    private var unlockLockCharacteristic: CBCharacteristic?
    private var managementCommandCharacteristic: CBCharacteristic?
    private var managementResponseCharacteristic: CBCharacteristic?
    private var activeManagementMode: BleManagementConnectMode?
    private var activeOperation: ActivePeripheralOperation?
    private var intentionalDisconnectPeripheralID: UUID?

    private static let connectTimeout: TimeInterval = 15
    private static let requestTimeout: TimeInterval = 7.5
    private static let scanTimeout: TimeInterval = 8

    private static let serviceLocked = CBUUID(string: "C5380EF2-C3FC-4F2A-B3CC-D51A08EF5FA9")
    private static let serviceUnlocked = CBUUID(string: "A1AA4F79-B490-44D2-A7E1-8A03422243A1")
    private static let serviceWindowOpen = CBUUID(string: "B99F8D62-A1C3-4E8B-9D2F-5C3A1B4E6D7A")
    private static let serviceGattProximity = CBUUID(string: "942C7A1E-362E-4676-A22F-39130FAF2272")
    private static let charUnlockLockCommand = CBUUID(string: "2522DA08-9E21-47DB-A834-22B7267E178B")
    private static let charMgmtCommand = CBUUID(string: "438C5641-3825-40BE-80A8-97BC261E0EE9")
    private static let charMgmtResponse = CBUUID(string: "DA43E428-803C-401B-9915-4C1529F453B1")

#if canImport(shared)
    private let keyStore = KeyStoreManager()
    private let payloadBuilder = PayloadBuilder()
    private let commandSlotId: Int32 = 0
#endif

    override public init() {
        super.init()
        locationManager.delegate = self
    }

    public func startProximity() {
        requestLocationAuthorizationIfNeeded()
        ensureCentralManager()
        passiveScanMode = .standard
        connectionState = .scanning
        refreshScanning()
    }

    public func stopProximity() {
        if passiveScanMode == .standard {
            passiveScanMode = .none
        }
        if activeDiscoveryRequest == nil {
            refreshScanning()
        }
        if managementState.connectionState == .disconnected {
            connectionState = .disconnected
        }
    }

    public func startWindowOpenScan() {
        requestLocationAuthorizationIfNeeded()
        ensureCentralManager()
        passiveScanMode = .windowOpen
        connectionState = .scanning
        refreshScanning()
    }

    public func stopWindowOpenScan() {
        if passiveScanMode == .windowOpen {
            passiveScanMode = .none
        }
        if activeDiscoveryRequest == nil {
            refreshScanning()
        }
        isWindowOpen = false
        if managementState.connectionState == .disconnected && passiveScanMode == .none {
            connectionState = .disconnected
        }
    }

    public func connectManagement(mode: BleManagementConnectMode) async throws {
        ensureCentralManager()
        try await awaitPoweredOnCentral()

        if managementState.connectionState == .ready,
           activeManagementMode == mode,
           managementPeripheral?.state == .connected,
           managementCommandCharacteristic != nil,
           managementResponseCharacteristic != nil {
            return
        }

        updateManagementState(
            connectionState: .scanning,
            mode: mode,
            peripheral: nil,
            lastError: nil
        )

        let peripheral = try await resolvePeripheral(for: mode)
        try await openManagementSession(with: peripheral, mode: mode)
    }

    public func disconnectManagement() {
        activeManagementMode = nil
        managementPeripheral = nil
        updateManagementState(connectionState: .disconnected, mode: nil, peripheral: nil, lastError: nil)

        guard let peripheral = connectedPeripheral else {
            resetCharacteristics()
            return
        }

        intentionalDisconnectPeripheralID = peripheral.identifier
        failPendingOperation(with: IosBleProximityServiceError.notConnected)
        centralManager?.cancelPeripheralConnection(peripheral)
        resetConnectedPeripheral()
    }

    public func requestSlots() async throws -> BleManagementSlotsResponse {
        let response = try await executeManagementCommand(
            name: "SLOTS?",
            payload: Data("SLOTS?".utf8)
        )
        switch response {
        case .slots(let slotsResponse):
            return slotsResponse
        case .success:
            throw IosBleProximityServiceError.invalidResponse("Expected slot list JSON response")
        case .error(let errorResponse):
            throw errorResponse
        }
    }

    public func identify(slotId: Int) async throws -> BleManagementCommandSuccess {
        let payload = try buildIdentifyPayload(slotId: slotId)
        lastCommandPayloadHex = payload.hexEncodedString()

        let response = try await executeManagementCommand(name: "IDENTIFY", payload: payload)
        switch response {
        case .success(let success):
            return success
        case .slots:
            throw IosBleProximityServiceError.invalidResponse("Expected identify acknowledgement")
        case .error(let errorResponse):
            throw errorResponse
        }
    }

    public func provision(slotId: Int, key: Data, counter: UInt32, name: String) async throws -> BleManagementCommandSuccess {
        try validateSlotId(slotId)
        try validateKeyLength(key)

        let command = "PROV:\(slotId):\(key.hexEncodedString()):\(counter):\(encodeCommandField(name))"
        let response = try await executeManagementCommand(name: "PROV", payload: Data(command.utf8))
        return try requireCommandSuccess(response, expected: "provision")
    }

    public func rename(slotId: Int, name: String) async throws -> BleManagementCommandSuccess {
        try validateSlotId(slotId)

        let command = "RENAME:\(slotId):\(encodeCommandField(name))"
        let response = try await executeManagementCommand(name: "RENAME", payload: Data(command.utf8))
        return try requireCommandSuccess(response, expected: "rename")
    }

    public func revoke(slotId: Int) async throws -> BleManagementCommandSuccess {
        try validateSlotId(slotId)

        let command = "REVOKE:\(slotId)"
        let response = try await executeManagementCommand(name: "REVOKE", payload: Data(command.utf8))
        return try requireCommandSuccess(response, expected: "revoke")
    }

    public func recover(slotId: Int, key: Data, counter: UInt32, name: String) async throws -> BleManagementCommandSuccess {
        try validateSlotId(slotId)
        try validateKeyLength(key)

        let command = "RECOVER:\(slotId):\(key.hexEncodedString()):\(counter):\(encodeCommandField(name))"
        let response = try await executeManagementCommand(name: "RECOVER", payload: Data(command.utf8))
        return try requireCommandSuccess(response, expected: "recover")
    }

    @MainActor public func sendUnlockCommand() async {
        await sendSharedProximityCommand(command: .unlock, targetState: .connectedUnlocked)
    }

    @MainActor public func sendLockCommand() async {
        await sendSharedProximityCommand(command: .lock, targetState: .connectedLocked)
    }

    private func requestLocationAuthorizationIfNeeded() {
        if #available(iOS 13.0, *) {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestAlwaysAuthorization()
            }
        } else if CLLocationManager.authorizationStatus() == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
    }

    private func ensureCentralManager() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func awaitPoweredOnCentral() async throws {
        ensureCentralManager()
        guard let centralManager else {
            throw IosBleProximityServiceError.bluetoothUnavailable("Bluetooth manager is unavailable")
        }

        switch centralManager.state {
        case .poweredOn:
            return
        case .unsupported:
            throw IosBleProximityServiceError.bluetoothUnavailable("Bluetooth LE is unsupported on this device")
        case .unauthorized:
            throw IosBleProximityServiceError.bluetoothUnavailable("Bluetooth access is unauthorized")
        case .poweredOff:
            throw IosBleProximityServiceError.bluetoothUnavailable("Bluetooth is powered off")
        case .resetting, .unknown:
            try await withTimeout(seconds: Self.connectTimeout, error: IosBleProximityServiceError.connectTimedOut) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.pendingPoweredOnContinuations.append(continuation)
                }
            }
        @unknown default:
            throw IosBleProximityServiceError.bluetoothUnavailable("Bluetooth entered an unknown state")
        }
    }

    private func refreshScanning() {
        guard let centralManager else { return }
        guard centralManager.state == .poweredOn else { return }

        if let activeDiscoveryRequest {
            centralManager.stopScan()
            centralManager.scanForPeripherals(
                withServices: activeDiscoveryRequest.serviceUUIDs,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            return
        }

        switch passiveScanMode {
        case .none:
            centralManager.stopScan()
        case .standard:
            centralManager.stopScan()
            centralManager.scanForPeripherals(
                withServices: [Self.serviceLocked, Self.serviceUnlocked],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .windowOpen:
            centralManager.stopScan()
            centralManager.scanForPeripherals(
                withServices: [Self.serviceWindowOpen],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    private func resolvePeripheral(for mode: BleManagementConnectMode) async throws -> CBPeripheral {
        if let cached = cachedPeripheral(for: mode), cached.state != .disconnected {
            return cached
        }

        let request = DiscoveryRequest(
            serviceUUIDs: serviceUUIDs(for: mode),
            mode: mode,
            purposeDescription: mode == .windowOpenRecovery ? "window-open recovery" : "standard management"
        )
        return try await discoverPeripheral(using: request)
    }

    private func cachedPeripheral(for mode: BleManagementConnectMode) -> CBPeripheral? {
        switch mode {
        case .standard:
            return lastStandardPeripheral ?? lastWindowOpenPeripheral
        case .windowOpenRecovery:
            return lastWindowOpenPeripheral
        }
    }

    private func serviceUUIDs(for mode: BleManagementConnectMode) -> [CBUUID] {
        switch mode {
        case .standard:
            return [Self.serviceLocked, Self.serviceUnlocked]
        case .windowOpenRecovery:
            return [Self.serviceWindowOpen]
        }
    }

    private func discoverPeripheral(using request: DiscoveryRequest) async throws -> CBPeripheral {
        if pendingScanContinuation != nil {
            throw IosBleProximityServiceError.busy("Another BLE scan is already in progress")
        }

        connectionState = .scanning

        return try await withTimeout(
            seconds: Self.scanTimeout,
            error: IosBleProximityServiceError.scanTimedOut("Timed out scanning for \(request.purposeDescription) device")
        ) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CBPeripheral, Error>) in
                self.activeDiscoveryRequest = request
                self.pendingScanContinuation = continuation
                self.refreshScanning()
            }
        }
    }

    private func openManagementSession(with peripheral: CBPeripheral, mode: BleManagementConnectMode) async throws {
        if pendingConnectionReadyContinuation != nil {
            throw IosBleProximityServiceError.busy("A BLE connection is already in progress")
        }

        if let connectedPeripheral, connectedPeripheral.identifier != peripheral.identifier {
            disconnectCurrentPeripheral(expectReconnect: true)
        }

        activeManagementMode = mode
        managementPeripheral = peripheral
        activeOperation = .management(mode)
        connectionState = .connecting
        updateManagementState(
            connectionState: .connecting,
            mode: mode,
            peripheral: peripheral,
            lastError: nil
        )

        if peripheral.state == .connected {
            connectedPeripheral = peripheral
            peripheral.delegate = self
            updateManagementState(
                connectionState: .discovering,
                mode: mode,
                peripheral: peripheral,
                lastError: nil
            )
            try await awaitPeripheralReady {
                self.proximityService = nil
                self.resetCharacteristics()
                peripheral.discoverServices([Self.serviceGattProximity])
            }
            return
        }

        try await withTimeout(seconds: Self.connectTimeout, error: IosBleProximityServiceError.connectTimedOut) {
            try await self.awaitPeripheralReady {
                self.connectedPeripheral = peripheral
                peripheral.delegate = self
                self.centralManager?.connect(peripheral, options: nil)
            }
        }
    }

    private func awaitPeripheralReady(start: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.pendingConnectionReadyContinuation = continuation
            start()
        }
    }

    private func executeManagementCommand(name: String, payload: Data) async throws -> BleManagementResponse {
        guard let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let commandCharacteristic = managementCommandCharacteristic,
              managementResponseCharacteristic != nil else {
            throw IosBleProximityServiceError.notConnected
        }

        if pendingResponseContinuation != nil || pendingWriteContinuation != nil {
            throw IosBleProximityServiceError.busy("Another BLE management command is already in flight")
        }

        let responseTask = Task<Data, Error> {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                self.pendingResponseContinuation = continuation
            }
        }

        do {
            try await writeValue(payload, to: commandCharacteristic, on: peripheral)
            let responseBytes = try await withTimeout(
                seconds: Self.requestTimeout,
                error: IosBleProximityServiceError.requestTimedOut(name)
            ) {
                try await responseTask.value
            }

            let raw = String(decoding: responseBytes, as: UTF8.self)
            let parsed = try parseManagementResponse(raw)
            if case .error(let errorResponse) = parsed {
                throw errorResponse
            }
            updateManagementState(
                connectionState: .ready,
                mode: activeManagementMode,
                peripheral: managementPeripheral,
                lastError: nil
            )
            return parsed
        } catch {
            responseTask.cancel()
            failPendingOperation(with: error)
            if managementState.connectionState != .disconnected {
                updateManagementState(
                    connectionState: .error,
                    mode: activeManagementMode,
                    peripheral: managementPeripheral,
                    lastError: error.localizedDescription
                )
            }
            throw error
        }
    }

    private func writeValue(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) async throws {
        let writeType = preferredWriteType(for: characteristic)
        if writeType == .withoutResponse {
            peripheral.writeValue(data, for: characteristic, type: writeType)
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.pendingWriteContinuation = continuation
            peripheral.writeValue(data, for: characteristic, type: writeType)
        }
    }

    private func preferredWriteType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        if characteristic.properties.contains(.write) {
            return .withResponse
        }
        return .withoutResponse
    }

    private func updateManagementState(
        connectionState: BleManagementSessionConnectionState,
        mode: BleManagementConnectMode?,
        peripheral: CBPeripheral?,
        lastError: String?
    ) {
        managementState = BleManagementSessionState(
            connectionState: connectionState,
            mode: mode,
            peripheralIdentifier: peripheral?.identifier,
            peripheralName: peripheral?.name,
            lastError: lastError
        )
    }

    private func disconnectCurrentPeripheral(expectReconnect: Bool) {
        guard let connectedPeripheral else { return }
        intentionalDisconnectPeripheralID = connectedPeripheral.identifier
        centralManager?.cancelPeripheralConnection(connectedPeripheral)
        if !expectReconnect {
            activeManagementMode = nil
            managementPeripheral = nil
        }
        resetConnectedPeripheral()
    }

    private func resetConnectedPeripheral() {
        connectedPeripheral?.delegate = nil
        connectedPeripheral = nil
        resetCharacteristics()
        activeOperation = nil
    }

    private func resetCharacteristics() {
        proximityService = nil
        unlockLockCharacteristic = nil
        managementCommandCharacteristic = nil
        managementResponseCharacteristic = nil
    }

    private func failPendingOperation(with error: Error) {
        if let continuation = pendingScanContinuation {
            pendingScanContinuation = nil
            activeDiscoveryRequest = nil
            continuation.resume(throwing: error)
            refreshScanning()
        }
        if let continuation = pendingConnectionReadyContinuation {
            pendingConnectionReadyContinuation = nil
            continuation.resume(throwing: error)
        }
        if let continuation = pendingWriteContinuation {
            pendingWriteContinuation = nil
            continuation.resume(throwing: error)
        }
        if let continuation = pendingResponseContinuation {
            pendingResponseContinuation = nil
            continuation.resume(throwing: error)
        }
    }

    private func completePendingScan(with peripheral: CBPeripheral) {
        guard let continuation = pendingScanContinuation else { return }
        pendingScanContinuation = nil
        activeDiscoveryRequest = nil
        continuation.resume(returning: peripheral)
        refreshScanning()
    }

    private func completePendingConnectionReady() {
        guard let continuation = pendingConnectionReadyContinuation else { return }
        pendingConnectionReadyContinuation = nil
        continuation.resume(returning: ())
    }

    private func completePendingWrite() {
        guard let continuation = pendingWriteContinuation else { return }
        pendingWriteContinuation = nil
        continuation.resume(returning: ())
    }

    private func completePendingResponse(with data: Data) {
        guard let continuation = pendingResponseContinuation else { return }
        pendingResponseContinuation = nil
        continuation.resume(returning: data)
    }

    private func requireCommandSuccess(_ response: BleManagementResponse, expected: String) throws -> BleManagementCommandSuccess {
        switch response {
        case .success(let success):
            return success
        case .slots:
            throw IosBleProximityServiceError.invalidResponse("Expected \(expected) acknowledgement response")
        case .error(let errorResponse):
            throw errorResponse
        }
    }

    private func parseManagementResponse(_ raw: String) throws -> BleManagementResponse {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !normalized.isEmpty else {
            throw IosBleProximityServiceError.invalidResponse("Empty management response")
        }

        if normalized == "ACK" {
            return .success(BleManagementCommandSuccess(raw: raw))
        }
        if normalized.hasPrefix("ACK:") {
            let message = String(normalized.dropFirst(4))
            return .success(BleManagementCommandSuccess(raw: raw, message: message.isEmpty ? nil : message))
        }
        if normalized == "ERR" {
            return .error(BleManagementErrorResponse(raw: raw, code: "ERR", message: nil))
        }
        if normalized.hasPrefix("ERR:") {
            let payload = String(normalized.dropFirst(4))
            let parts = payload.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            return .error(
                BleManagementErrorResponse(
                    raw: raw,
                    code: parts.first.map(String.init),
                    message: parts.count > 1 ? String(parts[1]) : nil
                )
            )
        }

        guard let data = normalized.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IosBleProximityServiceError.invalidResponse("Unsupported management response: \(normalized)")
        }

        guard let status = object["status"] as? String else {
            throw IosBleProximityServiceError.invalidResponse("Management response missing status")
        }

        switch status {
        case "ok":
            if let slotsArray = object["slots"] as? [[String: Any]] {
                let slots = try slotsArray.map { slotObject -> BleManagementSlot in
                    guard let slotId = slotObject["id"] as? Int else {
                        throw IosBleProximityServiceError.invalidResponse("Slot entry missing id")
                    }
                    guard let used = slotObject["used"] as? Bool else {
                        throw IosBleProximityServiceError.invalidResponse("Slot entry missing used flag")
                    }
                    guard let counterValue = slotObject["counter"] as? NSNumber else {
                        throw IosBleProximityServiceError.invalidResponse("Slot entry missing counter")
                    }
                    let name = (slotObject["name"] as? String) ?? ""
                    return BleManagementSlot(
                        id: slotId,
                        used: used,
                        counter: counterValue.uint32Value,
                        name: name
                    )
                }
                return .slots(BleManagementSlotsResponse(raw: raw, slots: slots))
            }

            let slotId = object["slot"] as? Int
            let name = object["name"] as? String
            let message = object["msg"] as? String
            let counter = (object["counter"] as? NSNumber)?.uint32Value
            return .success(
                BleManagementCommandSuccess(
                    raw: raw,
                    slotId: slotId,
                    name: name,
                    counter: counter,
                    message: message
                )
            )

        case "error":
            return .error(
                BleManagementErrorResponse(
                    raw: raw,
                    code: object["code"] as? String,
                    message: object["msg"] as? String
                )
            )

        default:
            throw IosBleProximityServiceError.invalidResponse("Unknown management status: \(status)")
        }
    }

    private func encodeCommandField(_ value: String) -> String {
        guard !value.isEmpty else { return "" }

        var encoded = String()
        for byte in value.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x5F, 0x2E, 0x7E:
                encoded.append(Character(UnicodeScalar(byte)))
            default:
                encoded.append(String(format: "%%%02X", byte))
            }
        }
        return encoded
    }

    private func validateSlotId(_ slotId: Int) throws {
        guard (0...3).contains(slotId) else {
            throw IosBleProximityServiceError.invalidSlot(slotId)
        }
    }

    private func validateKeyLength(_ key: Data) throws {
        guard key.count == 16 else {
            throw IosBleProximityServiceError.invalidKeyLength(key.count)
        }
    }

#if canImport(shared)
    private func ensureDemoKeyMaterialInitializedIfNeeded() {
        guard keyStore.loadKey(slotId: commandSlotId) == nil else { return }

        let keyBytes = (1...16).map { UInt8($0) }
        let kotlinKey = kotlinByteArray(from: keyBytes)
        keyStore.saveKey(slotId: commandSlotId, key: kotlinKey)
        keyStore.saveCounter(slotId: commandSlotId, counter: 1)
    }

    private func buildIdentifyPayload(slotId: Int) throws -> Data {
        try validateSlotId(slotId)
        let slotId32 = Int32(slotId)

        guard let key = keyStore.loadKey(slotId: slotId32) else {
            throw IosBleProximityServiceError.missingKey(slotId)
        }

        let counter = keyStore.loadCounter(slotId: slotId32)
        guard counter != UInt32.max else {
            throw IosBleProximityServiceError.counterOverflow(slotId)
        }

        let payload = payloadBuilder.buildPayload(
            slotId: slotId32,
            command: .identify,
            key: key,
            counter: counter
        )
        keyStore.saveCounter(slotId: slotId32, counter: counter &+ 1)
        return data(from: payload)
    }

    private func buildSharedPayload(command: ImmoCrypto.Command) -> Data? {
        ensureDemoKeyMaterialInitializedIfNeeded()

        guard let key = keyStore.loadKey(slotId: commandSlotId) else {
            return nil
        }

        let counter = keyStore.loadCounter(slotId: commandSlotId)
        let payload = payloadBuilder.buildPayload(
            slotId: commandSlotId,
            command: command,
            key: key,
            counter: counter
        )
        keyStore.saveCounter(slotId: commandSlotId, counter: counter &+ 1)
        return data(from: payload)
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
#else
    private func buildIdentifyPayload(slotId: Int) throws -> Data {
        throw IosBleProximityServiceError.unsupported("Shared framework is unavailable for IDENTIFY slot \(slotId)")
    }
#endif

    @MainActor
    private func sendSharedProximityCommand(command: ImmoCrypto.Command, targetState: ConnectionState) async {
#if canImport(shared)
        guard let payload = buildSharedPayload(command: command) else {
            connectionState = targetState
            return
        }

        lastCommandPayloadHex = payload.hexEncodedString()

        do {
            try await awaitPoweredOnCentral()
            if let unlockCharacteristic = unlockLockCharacteristic,
               let connectedPeripheral,
               connectedPeripheral.state == .connected {
                try await writeValue(payload, to: unlockCharacteristic, on: connectedPeripheral)
                connectionState = targetState
                return
            }

            guard let peripheral = lastStandardPeripheral ?? lastWindowOpenPeripheral else {
                connectionState = targetState
                return
            }

            if pendingConnectionReadyContinuation != nil {
                connectionState = targetState
                return
            }

            if let connectedPeripheral, connectedPeripheral.identifier != peripheral.identifier {
                disconnectCurrentPeripheral(expectReconnect: true)
            }

            activeOperation = .proximityCommand(targetState)
            connectionState = .connecting

            try await withTimeout(seconds: Self.connectTimeout, error: IosBleProximityServiceError.connectTimedOut) {
                try await self.awaitPeripheralReady {
                    self.connectedPeripheral = peripheral
                    peripheral.delegate = self
                    if peripheral.state == .connected {
                        self.proximityService = nil
                        self.resetCharacteristics()
                        peripheral.discoverServices([Self.serviceGattProximity])
                    } else {
                        self.centralManager?.connect(peripheral, options: nil)
                    }
                }
            }

            guard let unlockLockCharacteristic, let connectedPeripheral else {
                connectionState = targetState
                return
            }

            try await writeValue(payload, to: unlockLockCharacteristic, on: connectedPeripheral)
            connectionState = targetState
            disconnectCurrentPeripheral(expectReconnect: false)
        } catch {
            connectionState = targetState
        }
#else
        connectionState = targetState
#endif
    }

    private func withTimeout<T>(seconds: TimeInterval, error timeoutError: Error, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw timeoutError
            }

            let result = try await group.next()
            group.cancelAll()
            guard let result else {
                throw timeoutError
            }
            return result
        }
    }

    private enum PassiveScanMode: Equatable {
        case none
        case standard
        case windowOpen
    }

    private struct DiscoveryRequest {
        let serviceUUIDs: [CBUUID]
        let mode: BleManagementConnectMode
        let purposeDescription: String
    }

    private enum ActivePeripheralOperation {
        case management(BleManagementConnectMode)
        case proximityCommand(ConnectionState)
    }
}

extension IosBleProximityService: CLLocationManagerDelegate {}

extension IosBleProximityService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            let continuations = pendingPoweredOnContinuations
            pendingPoweredOnContinuations.removeAll()
            continuations.forEach { $0.resume(returning: ()) }
            refreshScanning()
        case .unsupported:
            let error = IosBleProximityServiceError.bluetoothUnavailable("Bluetooth LE is unsupported on this device")
            connectionState = .disconnected
            failPendingOperation(with: error)
        case .unauthorized:
            let error = IosBleProximityServiceError.bluetoothUnavailable("Bluetooth access is unauthorized")
            connectionState = .disconnected
            failPendingOperation(with: error)
        case .poweredOff:
            let error = IosBleProximityServiceError.bluetoothUnavailable("Bluetooth is powered off")
            connectionState = .disconnected
            failPendingOperation(with: error)
        case .resetting, .unknown:
            connectionState = .disconnected
        @unknown default:
            connectionState = .disconnected
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        rssi = RSSI.intValue

        let advertisedUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let uuidSet = Set(advertisedUUIDs)

        if uuidSet.contains(Self.serviceWindowOpen) || activeDiscoveryRequest?.mode == .windowOpenRecovery {
            lastWindowOpenPeripheral = peripheral
            isWindowOpen = true
        }

        if uuidSet.contains(Self.serviceLocked) {
            lastStandardPeripheral = peripheral
            lastAdvertisedConnectionState = .connectedLocked
            if passiveScanMode != .windowOpen {
                isWindowOpen = false
            }
        }

        if uuidSet.contains(Self.serviceUnlocked) {
            lastStandardPeripheral = peripheral
            lastAdvertisedConnectionState = .connectedUnlocked
            if passiveScanMode != .windowOpen {
                isWindowOpen = false
            }
        }

        guard let activeDiscoveryRequest else { return }
        if uuidSet.isEmpty || !uuidSet.isDisjoint(with: activeDiscoveryRequest.serviceUUIDs) {
            completePendingScan(with: peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting

        if case .management(let mode) = activeOperation {
            managementPeripheral = peripheral
            activeManagementMode = mode
            updateManagementState(
                connectionState: .discovering,
                mode: mode,
                peripheral: peripheral,
                lastError: nil
            )
        }

        proximityService = nil
        resetCharacteristics()
        peripheral.discoverServices([Self.serviceGattProximity])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let failure = error ?? IosBleProximityServiceError.system("Failed to connect to \(peripheral.name ?? peripheral.identifier.uuidString)")
        failPendingOperation(with: failure)
        updateManagementState(
            connectionState: .error,
            mode: activeManagementMode,
            peripheral: peripheral,
            lastError: failure.localizedDescription
        )
        resetConnectedPeripheral()
        connectionState = .disconnected
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let wasIntentional = intentionalDisconnectPeripheralID == peripheral.identifier
        intentionalDisconnectPeripheralID = nil

        if wasIntentional {
            resetConnectedPeripheral()
            if passiveScanMode == .none {
                connectionState = .disconnected
            }
            updateManagementState(connectionState: .disconnected, mode: nil, peripheral: nil, lastError: nil)
            return
        }

        let disconnectError = error ?? IosBleProximityServiceError.system("BLE connection closed")
        failPendingOperation(with: disconnectError)
        updateManagementState(
            connectionState: .error,
            mode: activeManagementMode,
            peripheral: peripheral,
            lastError: disconnectError.localizedDescription
        )
        resetConnectedPeripheral()
        connectionState = passiveScanMode == .none ? .disconnected : .scanning
        refreshScanning()
    }
}

extension IosBleProximityService: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            failPendingOperation(with: error)
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceGattProximity }) else {
            failPendingOperation(with: IosBleProximityServiceError.missingCharacteristic("Proximity GATT service not found"))
            return
        }

        proximityService = service
        peripheral.discoverCharacteristics(
            [Self.charUnlockLockCommand, Self.charMgmtCommand, Self.charMgmtResponse],
            for: service
        )
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            failPendingOperation(with: error)
            return
        }

        unlockLockCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.charUnlockLockCommand })
        managementCommandCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.charMgmtCommand })
        managementResponseCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.charMgmtResponse })

        switch activeOperation {
        case .management(let mode):
            guard let responseCharacteristic = managementResponseCharacteristic,
                  managementCommandCharacteristic != nil else {
                failPendingOperation(with: IosBleProximityServiceError.missingCharacteristic("Management characteristics not found"))
                return
            }

            updateManagementState(
                connectionState: .discovering,
                mode: mode,
                peripheral: peripheral,
                lastError: nil
            )

            if responseCharacteristic.isNotifying {
                updateManagementState(
                    connectionState: .ready,
                    mode: mode,
                    peripheral: peripheral,
                    lastError: nil
                )
                completePendingConnectionReady()
            } else {
                peripheral.setNotifyValue(true, for: responseCharacteristic)
            }

        case .proximityCommand:
            guard unlockLockCharacteristic != nil else {
                failPendingOperation(with: IosBleProximityServiceError.missingCharacteristic("Unlock/lock command characteristic not found"))
                return
            }
            completePendingConnectionReady()

        case .none:
            break
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            failPendingOperation(with: error)
            return
        }

        guard characteristic.uuid == Self.charMgmtResponse else { return }

        guard characteristic.isNotifying else {
            failPendingOperation(with: IosBleProximityServiceError.system("Management response notifications were not enabled"))
            return
        }

        updateManagementState(
            connectionState: .ready,
            mode: activeManagementMode,
            peripheral: peripheral,
            lastError: nil
        )
        connectionState = lastAdvertisedConnectionState == .disconnected ? connectionState : lastAdvertisedConnectionState
        completePendingConnectionReady()
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            failPendingOperation(with: error)
            return
        }

        if characteristic.uuid == Self.charMgmtCommand || characteristic.uuid == Self.charUnlockLockCommand {
            completePendingWrite()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            failPendingOperation(with: error)
            return
        }

        guard characteristic.uuid == Self.charMgmtResponse else { return }
        completePendingResponse(with: characteristic.value ?? Data())
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02X", $0) }.joined()
    }
}

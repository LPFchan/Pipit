import Foundation
import CoreLocation
import CoreBluetooth

#if canImport(shared)
import shared
#endif

/// Lightweight iOS BLE proximity service.
///
/// When the Kotlin Multiplatform shared framework is available, this service uses
/// shared cryptographic primitives (KeyStoreManager + PayloadBuilder) to generate
/// real lock/unlock payloads.

@objc public enum ConnectionState: Int {
    case disconnected = 0
    case scanning
    case connecting
    case connectedLocked
    case connectedUnlocked
}

@objc public class IosBleProximityService: NSObject, ObservableObject {
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var rssi: Int = 0
    @Published public private(set) var isWindowOpen: Bool = false
    @Published public private(set) var lastCommandPayloadHex: String?

    private var locationManager: CLLocationManager?
    private var centralManager: CBCentralManager?

#if canImport(shared)
    private let keyStore = KeyStoreManager()
    private let payloadBuilder = PayloadBuilder()
    private let commandSlotId: Int32 = 0
#endif

    override public init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager?.delegate = self

#if canImport(shared)
        ensureSharedKeyMaterialInitialized()
#endif

        // In Debug (previews/tests) avoid instantiating a real CBCentralManager which
        // will call back with transient `.unknown`/`.poweredOff` states and overwrite
        // the mocked connectionState we set from `AppDelegate`. Only create the
        // central manager in non-debug builds where we expect real BLE behaviour.
    #if !DEBUG
        centralManager = CBCentralManager(delegate: self, queue: nil)
    #else
        centralManager = nil
    #endif
    }

    public func startProximity() {
        // Minimal behaviour for previews: request authorization and do nothing else.
        if #available(iOS 13.0, *) {
            if locationManager?.authorizationStatus == .notDetermined {
                locationManager?.requestAlwaysAuthorization()
            }
        }
        connectionState = .scanning
    }

    public func stopProximity() {
        centralManager?.stopScan()
        connectionState = .disconnected
    }

    public func startWindowOpenScan() {
        connectionState = .scanning
    }

    public func stopWindowOpenScan() {
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    @MainActor public func sendUnlockCommand() async {
#if canImport(shared)
        _ = buildSharedPayload(command: .unlock)
#endif
        connectionState = .connectedUnlocked
    }

    @MainActor public func sendLockCommand() async {
#if canImport(shared)
        _ = buildSharedPayload(command: .lock)
#endif
        connectionState = .connectedLocked
    }

#if canImport(shared)
    private func ensureSharedKeyMaterialInitialized() {
        guard keyStore.loadKey(slotId: commandSlotId) == nil else { return }

        // Deterministic dev key for local preview/testing only.
        let keyBytes = (1...16).map { UInt8($0) }
        let kotlinKey = kotlinByteArray(from: keyBytes)
        keyStore.saveKey(slotId: commandSlotId, key: kotlinKey)
        keyStore.saveCounter(slotId: commandSlotId, counter: 1)
    }

    @discardableResult
    private func buildSharedPayload(command: ImmoCrypto.Command) -> KotlinByteArray? {
        ensureSharedKeyMaterialInitialized()

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
        lastCommandPayloadHex = hexString(from: payload)
        return payload
    }

    private func kotlinByteArray(from bytes: [UInt8]) -> KotlinByteArray {
        let array = KotlinByteArray(size: Int32(bytes.count))
        for (idx, value) in bytes.enumerated() {
            array.set(index: Int32(idx), value: Int8(bitPattern: value))
        }
        return array
    }

    private func hexString(from array: KotlinByteArray) -> String {
        var out = String()
        out.reserveCapacity(Int(array.size) * 2)
        for idx in 0..<Int(array.size) {
            let b = UInt8(bitPattern: array.get(index: Int32(idx)))
            out += String(format: "%02X", b)
        }
        return out
    }
#endif
}

// MARK: - Delegates (no-op implementations so the class can compile)
extension IosBleProximityService: CLLocationManagerDelegate {}

extension IosBleProximityService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // keep minimal state mapping for previews
        switch central.state {
        case .unsupported, .unauthorized, .unknown, .resetting:
            connectionState = .disconnected
        case .poweredOff:
            connectionState = .disconnected
        case .poweredOn:
            // remain in current state; real logic lives in the shared KMP implementation
            break
        @unknown default:
            connectionState = .disconnected
        }
    }
}

extension IosBleProximityService: CBPeripheralDelegate {}

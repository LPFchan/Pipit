import Foundation
import CoreLocation
import CoreBluetooth
import shared

class IosBleProximityService: NSObject, ObservableObject {
    
    // Config from KMP Shared
    private let beaconUUID = UUID(uuidString: ImmogenBleConfig.shared.IBEACON_UUID)!
    private let serviceLockedUUID = CBUUID(string: ImmogenBleConfig.shared.SERVICE_PROXIMITY_LOCKED)
    private let serviceUnlockedUUID = CBUUID(string: ImmogenBleConfig.shared.SERVICE_PROXIMITY_UNLOCKED)
    private let serviceWindowOpenUUID = CBUUID(string: ImmogenBleConfig.shared.SERVICE_PROXIMITY_WINDOW_OPEN)
    
    private let gattServiceUUID = CBUUID(string: ImmogenBleConfig.shared.SERVICE_GATT_PROXIMITY)
    private let charUnlockLockUUID = CBUUID(string: ImmogenBleConfig.shared.CHAR_UNLOCK_LOCK_CMD)
    
    // CoreLocation for waking the app
    private var locationManager: CLLocationManager!
    private var beaconRegion: CLBeaconRegion!
    
    // CoreBluetooth for actual GATT payload delivery
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    
    // Settings
    private let settingsManager = IosSettingsManager(userDefaults: UserDefaults.standard)
    private var appSettings: AppSettings!
    
    // State bridging to UI (would normally wrap the KMP Flow, but using Combine here for pure iOS UI convenience)
    @Published var connectionState: ConnectionState = .disconnected
    @Published var rssi: Int = 0
    @Published var isWindowOpen: Bool = false
    
    private var isWindowScanActive = false
    private var rssiHistory: [Int] = []
    private let rssiHistorySize = 5
    private var isGattConnecting = false
    private var lastKnownState: ConnectionState = .disconnected

    override init() {
        super.init()
        appSettings = AppSettings(manager: settingsManager)
        
        locationManager = CLLocationManager()
        locationManager.delegate = self
        
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "PipitBleCentral"])
        
        setupBeaconRegion()
    }
    
    private func setupBeaconRegion() {
        let constraint = CLBeaconIdentityConstraint(uuid: beaconUUID)
        beaconRegion = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: "ImmogenVehicle")
        beaconRegion.notifyEntryStateOnDisplay = true
        beaconRegion.notifyOnEntry = true
        beaconRegion.notifyOnExit = true
    }
    
    func startProximity() {
        guard appSettings.isProximityEnabled else { return }
        
        // Request Always authorization required for background iBeacon wake
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        
        locationManager.startMonitoring(for: beaconRegion)
        // Note: We don't range beacons usually, we just monitor region entry to wake, then use CB to scan for the GATT advertisement
        print("Started iBeacon monitoring")
    }
    
    func stopProximity() {
        locationManager.stopMonitoring(for: beaconRegion)
        centralManager.stopScan()
        connectionState = .disconnected
    }
    
    func startWindowOpenScan() {
        isWindowScanActive = true
        centralManager.scanForPeripherals(withServices: [serviceWindowOpenUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func stopWindowOpenScan() {
        isWindowScanActive = false
        centralManager.stopScan()
        if appSettings.isProximityEnabled {
            // Revert to background scanning if needed
        }
    }
    
    private func startGattScan() {
        guard centralManager.state == .poweredOn else { return }
        connectionState = .scanning
        
        // When woken by iBeacon, we immediately scan for the GATT services to evaluate precise RSSI
        centralManager.scanForPeripherals(
            withServices: [serviceLockedUUID, serviceUnlockedUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
    
    private func evaluateRssiForAction(peripheral: CBPeripheral, rssi: NSNumber, isLockedState: Bool) {
        let currentRssi = rssi.intValue
        self.rssi = currentRssi
        
        rssiHistory.append(currentRssi)
        if rssiHistory.count > rssiHistorySize {
            rssiHistory.removeFirst()
        }
        
        let avgRssi = rssiHistory.reduce(0, +) / rssiHistory.count
        
        if isLockedState {
            lastKnownState = .connectedLocked
            if avgRssi >= appSettings.unlockRssi && !isGattConnecting {
                print("Unlock threshold met, connecting...")
                connectAndSendPayload(peripheral: peripheral, isUnlock: true)
            }
        } else {
            lastKnownState = .connectedUnlocked
            if avgRssi <= appSettings.lockRssi && !isGattConnecting {
                print("Lock threshold met, connecting...")
                connectAndSendPayload(peripheral: peripheral, isUnlock: false)
            }
        }
    }
    
    private func connectAndSendPayload(peripheral: CBPeripheral, isUnlock: Bool) {
        isGattConnecting = true
        connectionState = .connecting
        self.peripheral = peripheral
        
        // Store intent for when connected
        // In a real app we'd use a queue or wrapper object
        objc_setAssociatedObject(peripheral, "isUnlockIntent", NSNumber(value: isUnlock), .OBJC_ASSOCIATION_RETAIN)
        
        centralManager.connect(peripheral, options: nil)
    }
    
    private func buildAndSendPayload(characteristic: CBCharacteristic, isUnlock: Bool) {
        // TODO: Replace with actual iOS Keychain retrieval
        let dummyKey = KotlinByteArray(size: 16)
        let dummyCounter: Int64 = 1
        let dummySlotId: Int8 = 1
        
        let command = isUnlock ? PayloadBuilder.shared.CMD_UNLOCK : PayloadBuilder.shared.CMD_LOCK
        
        do {
            let payloadKBA = try PayloadBuilder.shared.buildPayload(
                slotId: dummySlotId,
                counter: dummyCounter,
                command: command,
                key: dummyKey
            )
            
            // Convert KotlinByteArray to Swift Data
            // (Assuming standard interop extension, mocked here)
            var bytes = [UInt8]()
            for i in 0..<payloadKBA.size {
                bytes.append(UInt8(bitPattern: payloadKBA.get(index: i)))
            }
            let data = Data(bytes)
            
            peripheral?.writeValue(data, for: characteristic, type: .withoutResponse)
            print("Payload sent")
            
            // Fire and forget
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let p = self.peripheral {
                    self.centralManager.cancelPeripheralConnection(p)
                }
            }
            
        } catch {
            print("Failed to build payload: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension IosBleProximityService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion, beaconRegion.identifier == "ImmogenVehicle" else { return }
        print("iBeacon Region Entered - waking app to scan GATT")
        startGattScan()
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion, beaconRegion.identifier == "ImmogenVehicle" else { return }
        print("iBeacon Region Exited")
        centralManager.stopScan()
        connectionState = .disconnected
        rssiHistory.removeAll()
        
        // Edge case: Abrupt dropout walk-away logic could be evaluated here based on last known state
        if lastKnownState == .connectedUnlocked {
            // Consider sending lock command aggressively on next sight
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension IosBleProximityService: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if appSettings.isProximityEnabled && locationManager.authorizationStatus == .authorizedAlways {
                // We rely on CoreLocation to trigger the scan, but if we are already in region, we might want to start scanning immediately.
            }
        } else {
            connectionState = .disconnected
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        // Handle iOS app termination recovery
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else { return }
        
        if isWindowScanActive {
            if serviceUUIDs.contains(serviceWindowOpenUUID) {
                isWindowOpen = true
                // In recovery flow, just connect for management
                if !isGattConnecting {
                    self.peripheral = peripheral
                    centralManager.connect(peripheral, options: nil)
                }
            }
            return
        }
        
        let isLocked = serviceUUIDs.contains(serviceLockedUUID)
        let isUnlocked = serviceUUIDs.contains(serviceUnlockedUUID)
        
        if isLocked || isUnlocked {
            evaluateRssiForAction(peripheral: peripheral, rssi: RSSI, isLockedState: isLocked)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([gattServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isGattConnecting = false
        connectionState = .disconnected
        self.peripheral = nil
    }
}

// MARK: - CBPeripheralDelegate
extension IosBleProximityService: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == gattServiceUUID {
            peripheral.discoverCharacteristics([charUnlockLockUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics where char.uuid == charUnlockLockUUID {
            if let isUnlockIntentNumber = objc_getAssociatedObject(peripheral, "isUnlockIntent") as? NSNumber {
                let isUnlock = isUnlockIntentNumber.boolValue
                buildAndSendPayload(characteristic: char, isUnlock: isUnlock)
                // Clear intent
                objc_setAssociatedObject(peripheral, "isUnlockIntent", nil, .OBJC_ASSOCIATION_RETAIN)
            }
        }
    }
}

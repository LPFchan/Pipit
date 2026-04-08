package com.immogen.pipit.ble

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Binder
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.NotificationCompat
import com.immogen.core.ImmoCrypto
import com.immogen.core.KeyStoreManager
import com.immogen.core.PayloadBuilder
import com.immogen.pipit.settings.AndroidSettingsManager
import com.immogen.pipit.settings.AppSettings
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

@SuppressLint("MissingPermission") // Handled by UI layer before starting service
class AndroidBleProximityService : Service() {

    companion object {
        private const val TAG = "BleProximity"
        private const val NOTIFICATION_CHANNEL_ID = "immogen_proximity_channel"
        private const val NOTIFICATION_ID = 1
        private const val COMMAND_SCAN_TIMEOUT_MS = 8_000L
        private const val MANAGEMENT_TARGET_MTU = 247
        private const val MANAGEMENT_CONNECT_TIMEOUT_MS = 15_000L
        private const val MANAGEMENT_REQUEST_TIMEOUT_MS = 7_500L
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        const val ACTION_START_FOREGROUND = "com.immogen.pipit.action.START_FOREGROUND"
        const val ACTION_STOP_FOREGROUND = "com.immogen.pipit.action.STOP_FOREGROUND"
        const val ACTION_START_WINDOW_SCAN = "com.immogen.pipit.action.START_WINDOW_SCAN"
        const val ACTION_STOP_WINDOW_SCAN = "com.immogen.pipit.action.STOP_WINDOW_SCAN"
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    private lateinit var bluetoothManager: BluetoothManager
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var proximityGatt: BluetoothGatt? = null
    
    private lateinit var appSettings: AppSettings
    private lateinit var keyStoreManager: KeyStoreManager
    private val payloadBuilder = PayloadBuilder()
    private val bleManagementTransport = AndroidBleManagementTransport()
    private val bleStateService = AndroidBleServiceImpl()

    private var isScanning = false
    private var isWindowScan = false
    private var currentRssiHistory = mutableListOf<Int>()
    private val RSSI_HISTORY_SIZE = 5

    // Cached state to prevent rapid reconnects
    private var isGattConnecting = false
    private var lastStandardDevice: BluetoothDevice? = null
    private var lastWindowOpenDevice: BluetoothDevice? = null

    override fun onCreate() {
        super.onCreate()
        appSettings = AppSettings(AndroidSettingsManager(this))
        KeyStoreManager.init(applicationContext)
        keyStoreManager = KeyStoreManager()
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
        
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_FOREGROUND -> {
                startForeground(NOTIFICATION_ID, createNotification("Scanning for vehicle..."))
                startScanning(false)
            }
            ACTION_STOP_FOREGROUND -> {
                stopScanning()
                stopForegroundCompat()
                stopSelf()
            }
            ACTION_START_WINDOW_SCAN -> {
                startScanning(true)
            }
            ACTION_STOP_WINDOW_SCAN -> {
                if (appSettings.isProximityEnabled) {
                    startScanning(false) // Revert to normal scan
                } else {
                    stopScanning()
                }
            }
        }
        return START_STICKY
    }

    private fun startScanning(windowMode: Boolean) {
        if (bluetoothLeScanner == null || isScanning && isWindowScan == windowMode) return
        
        stopScanning() // Stop current scan if any
        
        isWindowScan = windowMode
        val scanFilters = mutableListOf<ScanFilter>()
        
        if (windowMode) {
            scanFilters.add(ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_WINDOW_OPEN)))
                .build())
        } else {
            scanFilters.add(ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_LOCKED)))
                .build())
            scanFilters.add(ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_UNLOCKED)))
                .build())
        }

        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY) // High freq for proximity
            .build()

        isScanning = true
        bleStateService.updateConnectionState(ConnectionState.SCANNING)
        bluetoothLeScanner?.startScan(scanFilters, scanSettings, scanCallback)
        Log.d(TAG, "Started scanning (Window mode: $windowMode)")
    }

    private fun stopScanning() {
        if (!isScanning) return
        bluetoothLeScanner?.stopScan(scanCallback)
        isScanning = false
        bleStateService.updateConnectionState(ConnectionState.DISCONNECTED)
        Log.d(TAG, "Stopped scanning")
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            super.onScanResult(callbackType, result)
            
            val device = result.device
            val rssi = result.rssi
            val uuids = result.scanRecord?.serviceUuids
            
            bleStateService.updateRssi(rssi)
            
            if (uuids != null) {
                if (uuids.contains(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_WINDOW_OPEN)))) {
                    lastWindowOpenDevice = device
                    handleWindowOpenDetection(device)
                    return
                }

                lastStandardDevice = device
                
                if (!appSettings.isProximityEnabled) return
                
                // Track RSSI history
                currentRssiHistory.add(rssi)
                if (currentRssiHistory.size > RSSI_HISTORY_SIZE) {
                    currentRssiHistory.removeAt(0)
                }
                
                val avgRssi = currentRssiHistory.average().toInt()
                
                if (uuids.contains(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_LOCKED)))) {
                    // Approach scenario
                    if (avgRssi >= appSettings.unlockRssi && !isGattConnecting && !bleManagementTransport.isActive()) {
                        Log.d(TAG, "Unlock threshold met ($avgRssi >= ${appSettings.unlockRssi}), connecting...")
                        connectGatt(device, true)
                    }
                } else if (uuids.contains(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_UNLOCKED)))) {
                    // Walk-away scenario
                    if (avgRssi <= appSettings.lockRssi && !isGattConnecting && !bleManagementTransport.isActive()) {
                        Log.d(TAG, "Lock threshold met ($avgRssi <= ${appSettings.lockRssi}), connecting...")
                        connectGatt(device, false)
                    }
                }
            }
        }
        
        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Scan failed with error: $errorCode")
            isScanning = false
        }
    }

    private fun handleWindowOpenDetection(device: BluetoothDevice) {
        lastWindowOpenDevice = device
        bleStateService.updateWindowOpen(true)
    }

    private fun connectGatt(device: BluetoothDevice, isUnlock: Boolean?) {
        if (bleManagementTransport.isActive()) {
            Log.d(TAG, "Skipping proximity GATT connect while management session is active")
            return
        }

        isGattConnecting = true
        bleStateService.updateConnectionState(ConnectionState.CONNECTING)
        
        // Android 6+ autoConnect=false for faster initial connection
        proximityGatt?.close()
        proximityGatt = device.connectGatt(this, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    Log.i(TAG, "Connected to GATT server.")
                    gatt.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    Log.i(TAG, "Disconnected from GATT server.")
                    isGattConnecting = false
                    bleStateService.updateConnectionState(ConnectionState.DISCONNECTED)
                    gatt.close()
                    if (proximityGatt === gatt) {
                        proximityGatt = null
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    if (isUnlock != null) {
                        sendPayload(gatt, isUnlock)
                    } else {
                        // Just connected for management (Window open)
                        bleStateService.updateConnectionState(ConnectionState.CONNECTED)
                    }
                }
            }
        })
    }

    private fun sendPayload(gatt: BluetoothGatt, isUnlock: Boolean) {
        val service = gatt.getService(UUID.fromString(ImmogenBleConfig.SERVICE_GATT_PROXIMITY))
        val char = service?.getCharacteristic(UUID.fromString(ImmogenBleConfig.CHAR_UNLOCK_LOCK_CMD))
        
        if (char != null) {
            serviceScope.launch {
                try {
                    val preparedPayload = buildSharedCommandPayload(
                        command = if (isUnlock) ImmoCrypto.Command.Unlock else ImmoCrypto.Command.Lock
                    )
                    
                    val success = writeCharacteristicCompat(gatt, char, preparedPayload.payload)
                    if (success) {
                        persistSharedCommandCounter(preparedPayload)
                    }
                    Log.d(TAG, "Payload sent: $success")
                    
                    // Fire and forget, disconnect immediately
                    delay(100) // Small delay to ensure packet sent
                    gatt.disconnect()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to send payload", e)
                    gatt.disconnect()
                }
            }
        } else {
            Log.e(TAG, "Characteristic not found")
            gatt.disconnect()
        }
    }

    private fun buildSharedCommandPayload(command: ImmoCrypto.Command): PreparedCommandPayload {
        val slotId = resolveProvisionedPhoneSlotId()
            ?: throw BleManagementException("No provisioned phone key stored locally")
        val key = keyStoreManager.loadKey(slotId)
            ?: throw BleManagementException("No key stored for slot $slotId")
        val counter = keyStoreManager.loadCounter(slotId)
        require(counter != UInt.MAX_VALUE) { "Counter overflow for slot $slotId" }

        val payload = payloadBuilder.buildPayload(
            slotId = slotId,
            counter = counter,
            command = command,
            key = key
        )
        return PreparedCommandPayload(slotId = slotId, counter = counter, payload = payload)
    }

    private fun persistSharedCommandCounter(preparedPayload: PreparedCommandPayload) {
        keyStoreManager.saveCounter(preparedPayload.slotId, preparedPayload.counter + 1u)
    }

    private fun resolveProvisionedPhoneSlotId(): Int? {
        for (slotId in 1..3) {
            if (keyStoreManager.loadKey(slotId) != null) {
                return slotId
            }
        }
        return null
    }

    private suspend fun resolveForegroundCommandDevice(): BluetoothDevice {
        lastStandardDevice?.let { return it }

        val scanner = bluetoothLeScanner
            ?: throw BleManagementException("Bluetooth LE scanner is unavailable")
        val deferred = CompletableDeferred<BluetoothDevice>()
        val filters = listOf(
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_LOCKED)))
                .build(),
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_UNLOCKED)))
                .build()
        )
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                super.onScanResult(callbackType, result)
                lastStandardDevice = result.device
                if (!deferred.isCompleted) {
                    deferred.complete(result.device)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                if (!deferred.isCompleted) {
                    deferred.completeExceptionally(
                        BleManagementException("Foreground scan failed (error=$errorCode)")
                    )
                }
            }
        }

        scanner.startScan(filters, settings, callback)
        return try {
            withTimeout(COMMAND_SCAN_TIMEOUT_MS) { deferred.await() }
        } finally {
            scanner.stopScan(callback)
        }
    }

    private suspend fun sendForegroundCommand(isUnlock: Boolean) {
        if (bleManagementTransport.isActive()) {
            Log.d(TAG, "Skipping foreground command while management session is active")
            return
        }
        if (isGattConnecting) {
            Log.d(TAG, "Skipping foreground command while a proximity connection is already in progress")
            return
        }

        try {
            val device = resolveForegroundCommandDevice()
            connectGatt(device, isUnlock)
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to start foreground BLE command", error)
        }
    }

    private data class PreparedCommandPayload(
        val slotId: Int,
        val counter: UInt,
        val payload: ByteArray
    )

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Proximity Unlock Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Runs in the background to automatically unlock your vehicle"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(content: String): Notification {
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Pipit Proximity Active")
            .setContentText(content)
            // .setSmallIcon(R.drawable.ic_notification) // Needs actual icon
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun writeCharacteristicCompat(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        payload: ByteArray
    ): Boolean {
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(
                characteristic,
                payload,
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            ) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                characteristic.value = payload
                gatt.writeCharacteristic(characteristic)
            }
        }
    }

    private fun disconnectProximityGatt() {
        proximityGatt?.disconnect()
        proximityGatt?.close()
        proximityGatt = null
        isGattConnecting = false
    }

    private fun resolveManagementDevice(mode: BleManagementConnectMode): BluetoothDevice {
        return when (mode) {
            BleManagementConnectMode.STANDARD -> lastStandardDevice ?: lastWindowOpenDevice
            BleManagementConnectMode.WINDOW_OPEN_RECOVERY -> lastWindowOpenDevice
        } ?: throw BleManagementException("No BLE device available for $mode connection")
    }

    inner class LocalBinder : Binder() {
        fun getBleService(): BleService = bleStateService
    }
    override fun onBind(intent: Intent?): IBinder? = LocalBinder()
    
    override fun onDestroy() {
        stopScanning()
        bleManagementTransport.closeQuietly()
        disconnectProximityGatt()
        serviceScope.cancel()
        super.onDestroy()
    }
    
    // Internal implementation of the shared KMP interface to bridge state
    inner class AndroidBleServiceImpl : BaseBleService() {
        override val managementTransport: BleManagementTransport = bleManagementTransport

        override fun startScanning() {
            updateWindowOpen(false)
            this@AndroidBleProximityService.startScanning(false)
        }
        override fun stopScanning() = this@AndroidBleProximityService.stopScanning()
        
        override suspend fun sendUnlockCommand() {
            sendForegroundCommand(isUnlock = true)
        }
        
        override suspend fun sendLockCommand() {
            sendForegroundCommand(isUnlock = false)
        }
        
        override fun startWindowOpenScan() {
            updateWindowOpen(false)
            this@AndroidBleProximityService.startScanning(true)
        }
        override fun stopWindowOpenScan() {
            updateWindowOpen(false)
            this@AndroidBleProximityService.stopScanning()
            if (appSettings.isProximityEnabled) startScanning(false)
        }
        
        fun updateConnectionState(state: ConnectionState) {
            updateState { it.copy(connectionState = state) }
        }
        
        fun updateRssi(rssi: Int) {
            updateState { it.copy(rssi = rssi) }
        }
        
        fun updateWindowOpen(isOpen: Boolean) {
            updateState { it.copy(isWindowOpen = isOpen) }
        }
    }

    inner class AndroidBleManagementTransport : BleManagementTransport {
        private val _sessionState = MutableStateFlow(BleManagementSessionState())
        override val sessionState: StateFlow<BleManagementSessionState> = _sessionState.asStateFlow()

        private val connectMutex = Mutex()
        private val requestMutex = Mutex()
        private var session: ManagementGattSession? = null

        fun isActive(): Boolean = session?.isOpen() == true

        override suspend fun connect(mode: BleManagementConnectMode) {
            connectMutex.withLock {
                val current = session
                if (current?.isReady() == true && current.mode == mode) {
                    return
                }

                current?.close(null)
                disconnectProximityGatt()

                val device = resolveManagementDevice(mode)
                val newSession = ManagementGattSession(mode = mode, device = device)
                session = newSession
                updateSessionState(
                    connectionState = BleManagementSessionConnectionState.CONNECTING,
                    mode = mode,
                    deviceAddress = device.address,
                    mtu = null,
                    lastError = null
                )

                try {
                    newSession.connect()
                } catch (error: Throwable) {
                    if (session === newSession) {
                        session = null
                    }
                    newSession.close(error.message)
                    throw error
                }
            }
        }

        override suspend fun disconnect() {
            connectMutex.withLock {
                session?.close(null)
                session = null
                updateSessionState(
                    connectionState = BleManagementSessionConnectionState.DISCONNECTED,
                    mode = null,
                    deviceAddress = null,
                    mtu = null,
                    lastError = null
                )
            }
        }

        override suspend fun requestSlots(): BleManagementSlotsResponse {
            val response = execute(BleManagementProtocol.buildSlotsRequest())
            return response as? BleManagementSlotsResponse
                ?: throw BleManagementProtocolException("Expected SLOTS response")
        }

        override suspend fun identify(slotId: Int): BleManagementCommandSuccess {
            val frame = BleManagementProtocol.buildIdentifyRequest(
                slotId = slotId,
                keyStoreManager = keyStoreManager,
                payloadBuilder = payloadBuilder
            )
            return execute(frame) as? BleManagementCommandSuccess
                ?: throw BleManagementProtocolException("Expected IDENTIFY acknowledgement")
        }

        override suspend fun provision(
            slotId: Int,
            key: ByteArray,
            counter: UInt,
            name: String
        ): BleManagementCommandSuccess {
            val frame = BleManagementProtocol.buildProvisionRequest(slotId, key, counter, name)
            return execute(frame) as? BleManagementCommandSuccess
                ?: throw BleManagementProtocolException("Expected PROV acknowledgement")
        }

        override suspend fun rename(slotId: Int, name: String): BleManagementCommandSuccess {
            val frame = BleManagementProtocol.buildRenameRequest(slotId, name)
            return execute(frame) as? BleManagementCommandSuccess
                ?: throw BleManagementProtocolException("Expected RENAME acknowledgement")
        }

        override suspend fun revoke(slotId: Int): BleManagementCommandSuccess {
            val frame = BleManagementProtocol.buildRevokeRequest(slotId)
            return execute(frame) as? BleManagementCommandSuccess
                ?: throw BleManagementProtocolException("Expected REVOKE acknowledgement")
        }

        override suspend fun recover(
            slotId: Int,
            key: ByteArray,
            counter: UInt,
            name: String
        ): BleManagementCommandSuccess {
            val frame = BleManagementProtocol.buildRecoverRequest(slotId, key, counter, name)
            return execute(frame) as? BleManagementCommandSuccess
                ?: throw BleManagementProtocolException("Expected RECOVER acknowledgement")
        }

        fun closeQuietly() {
            session?.close(null)
            session = null
            updateSessionState(
                connectionState = BleManagementSessionConnectionState.DISCONNECTED,
                mode = null,
                deviceAddress = null,
                mtu = null,
                lastError = null
            )
        }

        private suspend fun execute(frame: BleManagementFrame): BleManagementResponse {
            return requestMutex.withLock {
                val activeSession = session ?: throw BleManagementException("Management session is not connected")
                if (!activeSession.isReady()) {
                    throw BleManagementException("Management session is not ready")
                }

                val response = activeSession.execute(frame)
                if (response is BleManagementError) {
                    throw BleManagementResponseException(response)
                }
                response
            }
        }

        private fun updateSessionState(
            connectionState: BleManagementSessionConnectionState,
            mode: BleManagementConnectMode?,
            deviceAddress: String?,
            mtu: Int?,
            lastError: String?
        ) {
            _sessionState.value = BleManagementSessionState(
                connectionState = connectionState,
                mode = mode,
                deviceAddress = deviceAddress,
                mtu = mtu,
                lastError = lastError
            )
        }

        inner class ManagementGattSession(
            val mode: BleManagementConnectMode,
            private val device: BluetoothDevice
        ) {
            private val pendingLock = Any()
            private var readyDeferred: CompletableDeferred<Unit>? = null
            private var writeDeferred: CompletableDeferred<Unit>? = null
            private var responseDeferred: CompletableDeferred<ByteArray>? = null
            private var gatt: BluetoothGatt? = null
            private var managementCommandCharacteristic: BluetoothGattCharacteristic? = null
            private var managementResponseCharacteristic: BluetoothGattCharacteristic? = null
            private var mtu: Int? = null
            private var closed = false

            private val callback = object : BluetoothGattCallback() {
                override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                    if (closed) {
                        return
                    }

                    when (newState) {
                        BluetoothProfile.STATE_CONNECTED -> {
                            if (status != BluetoothGatt.GATT_SUCCESS) {
                                fail(BleManagementException("Management connection failed (status=$status)"))
                                return
                            }

                            updateSessionState(
                                connectionState = BleManagementSessionConnectionState.DISCOVERING,
                                mode = mode,
                                deviceAddress = device.address,
                                mtu = null,
                                lastError = null
                            )

                            if (!gatt.requestMtu(MANAGEMENT_TARGET_MTU) && !gatt.discoverServices()) {
                                fail(BleManagementException("Failed to begin management service discovery"))
                            }
                        }

                        BluetoothProfile.STATE_DISCONNECTED -> {
                            val message = if (status == BluetoothGatt.GATT_SUCCESS) {
                                "Management connection closed"
                            } else {
                                "Management connection lost (status=$status)"
                            }
                            fail(BleManagementException(message))
                        }
                    }
                }

                override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                    if (closed) {
                        return
                    }

                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        this@ManagementGattSession.mtu = mtu
                    }
                    if (!gatt.discoverServices()) {
                        fail(BleManagementException("Failed to discover management services"))
                    }
                }

                override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                    if (closed) {
                        return
                    }
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        fail(BleManagementException("Management service discovery failed (status=$status)"))
                        return
                    }

                    val service = gatt.getService(UUID.fromString(ImmogenBleConfig.SERVICE_GATT_PROXIMITY))
                    val commandCharacteristic = service?.getCharacteristic(UUID.fromString(ImmogenBleConfig.CHAR_MGMT_CMD))
                    val responseCharacteristic = service?.getCharacteristic(UUID.fromString(ImmogenBleConfig.CHAR_MGMT_RESP))

                    if (service == null || commandCharacteristic == null || responseCharacteristic == null) {
                        fail(BleManagementException("Management characteristics not found"))
                        return
                    }

                    managementCommandCharacteristic = commandCharacteristic
                    managementResponseCharacteristic = responseCharacteristic

                    if (!gatt.setCharacteristicNotification(responseCharacteristic, true)) {
                        fail(BleManagementException("Failed to enable management notifications"))
                        return
                    }

                    val descriptor = responseCharacteristic.getDescriptor(CCCD_UUID)
                    if (descriptor == null) {
                        fail(BleManagementException("Management response CCCD is missing"))
                        return
                    }

                    if (!writeDescriptorCompat(gatt, descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                        fail(BleManagementException("Failed to write management notification descriptor"))
                    }
                }

                override fun onDescriptorWrite(
                    gatt: BluetoothGatt,
                    descriptor: BluetoothGattDescriptor,
                    status: Int
                ) {
                    if (closed || descriptor.uuid != CCCD_UUID) {
                        return
                    }
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        fail(BleManagementException("Management notification enable failed (status=$status)"))
                        return
                    }

                    readyDeferred?.complete(Unit)
                    updateSessionState(
                        connectionState = BleManagementSessionConnectionState.READY,
                        mode = mode,
                        deviceAddress = device.address,
                        mtu = mtu,
                        lastError = null
                    )
                }

                override fun onCharacteristicWrite(
                    gatt: BluetoothGatt,
                    characteristic: BluetoothGattCharacteristic,
                    status: Int
                ) {
                    if (closed || characteristic.uuid != UUID.fromString(ImmogenBleConfig.CHAR_MGMT_CMD)) {
                        return
                    }

                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        writeDeferred?.complete(Unit)
                    } else {
                        writeDeferred?.completeExceptionally(
                            BleManagementException("Management write failed (status=$status)")
                        )
                    }
                }

                override fun onCharacteristicChanged(
                    gatt: BluetoothGatt,
                    characteristic: BluetoothGattCharacteristic
                ) {
                    if (closed || characteristic.uuid != UUID.fromString(ImmogenBleConfig.CHAR_MGMT_RESP)) {
                        return
                    }
                    responseDeferred?.complete(characteristic.value?.copyOf() ?: ByteArray(0))
                }

                override fun onCharacteristicChanged(
                    gatt: BluetoothGatt,
                    characteristic: BluetoothGattCharacteristic,
                    value: ByteArray
                ) {
                    if (closed || characteristic.uuid != UUID.fromString(ImmogenBleConfig.CHAR_MGMT_RESP)) {
                        return
                    }
                    responseDeferred?.complete(value.copyOf())
                }
            }

            suspend fun connect() {
                val ready = CompletableDeferred<Unit>()
                synchronized(pendingLock) {
                    readyDeferred = ready
                }

                gatt = device.connectGatt(
                    this@AndroidBleProximityService,
                    false,
                    callback,
                    BluetoothDevice.TRANSPORT_LE
                )

                try {
                    withTimeout(MANAGEMENT_CONNECT_TIMEOUT_MS) {
                        ready.await()
                    }
                } catch (error: TimeoutCancellationException) {
                    fail(BleManagementTimeoutException("Management connection timed out"))
                    throw BleManagementTimeoutException("Management connection timed out")
                }
            }

            suspend fun execute(frame: BleManagementFrame): BleManagementResponse {
                val activeGatt = gatt ?: throw BleManagementException("Management GATT is unavailable")
                val commandCharacteristic = managementCommandCharacteristic
                    ?: throw BleManagementException("Management command characteristic is unavailable")

                val writeAck = CompletableDeferred<Unit>()
                val responseAck = CompletableDeferred<ByteArray>()
                synchronized(pendingLock) {
                    writeDeferred = writeAck
                    responseDeferred = responseAck
                }

                try {
                    if (!writeManagementCharacteristic(activeGatt, commandCharacteristic, frame.payload)) {
                        throw BleManagementException("Failed to write management command ${frame.commandName}")
                    }

                    val responseBytes = withTimeout(MANAGEMENT_REQUEST_TIMEOUT_MS) {
                        writeAck.await()
                        responseAck.await()
                    }
                    return BleManagementProtocol.parseResponse(String(responseBytes, Charsets.UTF_8))
                } catch (error: TimeoutCancellationException) {
                    throw BleManagementTimeoutException("Management request timed out: ${frame.commandName}")
                } finally {
                    synchronized(pendingLock) {
                        if (writeDeferred === writeAck) {
                            writeDeferred = null
                        }
                        if (responseDeferred === responseAck) {
                            responseDeferred = null
                        }
                    }
                }
            }

            fun isReady(): Boolean = !closed && managementCommandCharacteristic != null && managementResponseCharacteristic != null

            fun isOpen(): Boolean = !closed

            fun close(reason: String?) {
                if (closed) {
                    return
                }
                closed = true

                val closeError = BleManagementException(reason ?: "Management session closed")
                synchronized(pendingLock) {
                    readyDeferred?.completeExceptionally(closeError)
                    writeDeferred?.completeExceptionally(closeError)
                    responseDeferred?.completeExceptionally(closeError)
                    readyDeferred = null
                    writeDeferred = null
                    responseDeferred = null
                }

                gatt?.disconnect()
                gatt?.close()
                gatt = null
                managementCommandCharacteristic = null
                managementResponseCharacteristic = null

                if (session === this) {
                    session = null
                }
                updateSessionState(
                    connectionState = BleManagementSessionConnectionState.DISCONNECTED,
                    mode = null,
                    deviceAddress = null,
                    mtu = null,
                    lastError = reason
                )
            }

            private fun fail(error: Throwable) {
                Log.e(TAG, "Management session failure", error)
                updateSessionState(
                    connectionState = BleManagementSessionConnectionState.ERROR,
                    mode = mode,
                    deviceAddress = device.address,
                    mtu = mtu,
                    lastError = error.message
                )
                close(error.message)
            }

            private fun writeManagementCharacteristic(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                payload: ByteArray
            ): Boolean {
                characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeCharacteristic(
                        characteristic,
                        payload,
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    ) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    run {
                        characteristic.value = payload
                        gatt.writeCharacteristic(characteristic)
                    }
                }
            }

            private fun writeDescriptorCompat(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                value: ByteArray
            ): Boolean {
                return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    run {
                        descriptor.value = value
                        gatt.writeDescriptor(descriptor)
                    }
                }
            }
        }
    }
}

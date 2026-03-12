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
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.NotificationCompat
import com.immogen.core.ImmoCrypto
import com.immogen.core.PayloadBuilder
import com.immogen.pipit.settings.AndroidSettingsManager
import com.immogen.pipit.settings.AppSettings
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.update
import java.util.UUID

@SuppressLint("MissingPermission") // Handled by UI layer before starting service
class AndroidBleProximityService : Service() {

    companion object {
        private const val TAG = "BleProximity"
        private const val NOTIFICATION_CHANNEL_ID = "immogen_proximity_channel"
        private const val NOTIFICATION_ID = 1

        const val ACTION_START_FOREGROUND = "com.immogen.pipit.action.START_FOREGROUND"
        const val ACTION_STOP_FOREGROUND = "com.immogen.pipit.action.STOP_FOREGROUND"
        const val ACTION_START_WINDOW_SCAN = "com.immogen.pipit.action.START_WINDOW_SCAN"
        const val ACTION_STOP_WINDOW_SCAN = "com.immogen.pipit.action.STOP_WINDOW_SCAN"
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    private lateinit var bluetoothManager: BluetoothManager
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothGatt: BluetoothGatt? = null
    
    private lateinit var appSettings: AppSettings
    private val bleStateService = AndroidBleServiceImpl()

    private var isScanning = false
    private var isWindowScan = false
    private var currentRssiHistory = mutableListOf<Int>()
    private val RSSI_HISTORY_SIZE = 5

    // Cached state to prevent rapid reconnects
    private var lastKnownState: ConnectionState = ConnectionState.DISCONNECTED
    private var isGattConnecting = false

    override fun onCreate() {
        super.onCreate()
        appSettings = AppSettings(AndroidSettingsManager(this))
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
                stopForeground(true)
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
                    handleWindowOpenDetection(device)
                    return
                }
                
                if (!appSettings.isProximityEnabled) return
                
                // Track RSSI history
                currentRssiHistory.add(rssi)
                if (currentRssiHistory.size > RSSI_HISTORY_SIZE) {
                    currentRssiHistory.removeAt(0)
                }
                
                val avgRssi = currentRssiHistory.average().toInt()
                
                if (uuids.contains(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_LOCKED)))) {
                    lastKnownState = ConnectionState.CONNECTED_LOCKED
                    // Approach scenario
                    if (avgRssi >= appSettings.unlockRssi && !isGattConnecting) {
                        Log.d(TAG, "Unlock threshold met ($avgRssi >= ${appSettings.unlockRssi}), connecting...")
                        connectGatt(device, true)
                    }
                } else if (uuids.contains(ParcelUuid(UUID.fromString(ImmogenBleConfig.SERVICE_PROXIMITY_UNLOCKED)))) {
                    lastKnownState = ConnectionState.CONNECTED_UNLOCKED
                    // Walk-away scenario
                    if (avgRssi <= appSettings.lockRssi && !isGattConnecting) {
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
        bleStateService.updateWindowOpen(true)
        // If we're explicitly looking for it (Recovery flow), connect
        if (isWindowScan && !isGattConnecting) {
            connectGatt(device, isUnlock = null) // Null means don't auto-send payload, just connect for management
        }
    }

    private fun connectGatt(device: BluetoothDevice, isUnlock: Boolean?) {
        isGattConnecting = true
        bleStateService.updateConnectionState(ConnectionState.CONNECTING)
        
        // Android 6+ autoConnect=false for faster initial connection
        bluetoothGatt = device.connectGatt(this, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    Log.i(TAG, "Connected to GATT server.")
                    gatt.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    Log.i(TAG, "Disconnected from GATT server.")
                    isGattConnecting = false
                    bleStateService.updateConnectionState(ConnectionState.DISCONNECTED)
                    gatt.close()
                    bluetoothGatt = null
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    if (isUnlock != null) {
                        sendPayload(gatt, isUnlock)
                    } else {
                        // Just connected for management (Window open)
                        bleStateService.updateConnectionState(lastKnownState)
                    }
                }
            }
        })
    }

    private fun sendPayload(gatt: BluetoothGatt, isUnlock: Boolean) {
        val service = gatt.getService(UUID.fromString(ImmogenBleConfig.SERVICE_GATT_PROXIMITY))
        val char = service?.getCharacteristic(UUID.fromString(ImmogenBleConfig.CHAR_UNLOCK_LOCK_CMD))
        
        if (char != null) {
            // In a real app, we'd fetch the actual slot and key from KeyStore here
            // For now, this is the architectural placeholder
            serviceScope.launch {
                try {
                    // TODO: Replace with actual KeyStore retrieval
                    val dummyKey = ByteArray(16) { 0 }
                    val dummyCounter = 1L
                    val dummySlotId = 1.toByte()
                    
                    val payload = PayloadBuilder.buildPayload(
                        slotId = dummySlotId,
                        counter = dummyCounter,
                        command = if (isUnlock) PayloadBuilder.CMD_UNLOCK else PayloadBuilder.CMD_LOCK,
                        key = dummyKey
                    )
                    
                    char.value = payload
                    char.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    val success = gatt.writeCharacteristic(char)
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

    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        stopScanning()
        bluetoothGatt?.close()
    }
    
    // Internal implementation of the shared KMP interface to bridge state
    inner class AndroidBleServiceImpl : BaseBleService() {
        override fun startScanning() = this@AndroidBleProximityService.startScanning(false)
        override fun stopScanning() = this@AndroidBleProximityService.stopScanning()
        
        override suspend fun sendUnlockCommand() {
            // For manual foreground trigger - would need active connection
        }
        
        override suspend fun sendLockCommand() {
             // For manual foreground trigger
        }
        
        override fun startWindowOpenScan() = this@AndroidBleProximityService.startScanning(true)
        override fun stopWindowOpenScan() {
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
}

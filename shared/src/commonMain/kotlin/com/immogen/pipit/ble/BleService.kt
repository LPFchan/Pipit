package com.immogen.pipit.ble

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class ConnectionState {
    DISCONNECTED,
    SCANNING,
    CONNECTING,
    CONNECTED_LOCKED,
    CONNECTED_UNLOCKED
}

data class BleState(
    val connectionState: ConnectionState = ConnectionState.DISCONNECTED,
    val rssi: Int? = null,
    val isBluetoothEnabled: Boolean = true,
    val isWindowOpen: Boolean = false
)

interface BleService {
    val state: StateFlow<BleState>
    val managementTransport: BleManagementTransport?
    
    fun startScanning()
    fun stopScanning()
    
    // Foreground interaction
    suspend fun sendUnlockCommand()
    suspend fun sendLockCommand()
    
    // Recovery flow
    fun startWindowOpenScan()
    fun stopWindowOpenScan()
}

// Common UUIDs from architecture document
object ImmogenBleConfig {
    const val IBEACON_UUID = "66962B67-9C59-4D83-9101-AC0C9CCA2B12"
    
    const val SERVICE_PROXIMITY_LOCKED = "C5380EF2-C3FC-4F2A-B3CC-D51A08EF5FA9"
    const val SERVICE_PROXIMITY_UNLOCKED = "A1AA4F79-B490-44D2-A7E1-8A03422243A1"
    const val SERVICE_PROXIMITY_WINDOW_OPEN = "B99F8D62-A1C3-4E8B-9D2F-5C3A1B4E6D7A"
    
    const val SERVICE_GATT_PROXIMITY = "942C7A1E-362E-4676-A22F-39130FAF2272"
    const val CHAR_UNLOCK_LOCK_CMD = "2522DA08-9E21-47DB-A834-22B7267E178B"
    const val CHAR_MGMT_CMD = "438C5641-3825-40BE-80A8-97BC261E0EE9"
    const val CHAR_MGMT_RESP = "DA43E428-803C-401B-9915-4C1529F453B1"
    
    const val IBEACON_INTERVAL_MS = 300L
    const val HYSTERESIS_DBM = 10
}

abstract class BaseBleService : BleService {
    protected val _state = MutableStateFlow(BleState())
    override val state: StateFlow<BleState> = _state.asStateFlow()
    override val managementTransport: BleManagementTransport? = null
    
    protected fun updateState(update: (BleState) -> BleState) {
        _state.value = update(_state.value)
    }
}

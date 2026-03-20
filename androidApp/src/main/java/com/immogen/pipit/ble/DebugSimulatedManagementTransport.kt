package com.immogen.pipit.ble

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

/**
 * Debug-only simulated BleManagementTransport, mirroring the iOS simulator implementation in
 * IosBleProximityService. Routes all management operations to SharedPreferences-backed state,
 * enabling full Settings and Onboarding testing without Bluetooth hardware.
 *
 * Only instantiated when BuildConfig.DEBUG == true (enforced by AndroidBleProximityService).
 * Slot 0 (Uguisu hardware key) is read-only, matching iOS simulator behaviour.
 */
internal class DebugSimulatedManagementTransport(context: Context) : BleManagementTransport {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _sessionState = MutableStateFlow(BleManagementSessionState())
    override val sessionState: StateFlow<BleManagementSessionState> = _sessionState.asStateFlow()

    companion object {
        private const val PREFS_NAME  = "debug_sim_transport"
        private const val SLOTS_KEY   = "SIM_MANAGEMENT_SLOTS_V1"
        const val DEV_BYPASS_OVERLAY_KEY = "DEV_BYPASS_OVERLAY"
    }

    // ── Connect / disconnect ──────────────────────────────────────────────────

    override suspend fun connect(mode: BleManagementConnectMode) {
        _sessionState.value = BleManagementSessionState(
            connectionState = BleManagementSessionConnectionState.CONNECTING,
            mode = mode,
        )
        delay(120) // Simulated handshake delay (matches iOS 120 ms)
        _sessionState.value = BleManagementSessionState(
            connectionState = BleManagementSessionConnectionState.READY,
            mode = mode,
            deviceAddress = "00:00:00:00:00:SIM",
            mtu = 247,
        )
    }

    override suspend fun disconnect() {
        _sessionState.value = BleManagementSessionState(
            connectionState = BleManagementSessionConnectionState.DISCONNECTED,
        )
    }

    // ── Management operations ─────────────────────────────────────────────────

    override suspend fun requestSlots(): BleManagementSlotsResponse {
        ensureReady()
        val slots = loadSlots().map {
            BleManagementSlot(id = it.id, used = it.used, counter = it.counter, name = it.name)
        }
        return BleManagementSlotsResponse(raw = "SIM_SLOTS", slots = slots)
    }

    override suspend fun identify(slotId: Int): BleManagementCommandSuccess {
        ensureReady()
        validateSlotId(slotId)
        val slot = slotById(slotId)
        return BleManagementCommandSuccess(
            raw     = "SIM_ACK:IDENTIFY",
            slotId  = slotId,
            name    = slot?.name,
            counter = slot?.counter,
            message = "Simulator identify acknowledged",
        )
    }

    override suspend fun provision(
        slotId: Int, key: ByteArray, counter: UInt, name: String,
    ): BleManagementCommandSuccess {
        ensureReady()
        validateSlotId(slotId)
        ensureWritable(slotId)
        require(key.size == 16) { "Key must be exactly 16 bytes" }
        val sanitized = name.take(24)
        mutateSlot(slotId) { it.copy(used = true, counter = counter, name = sanitized) }
        return BleManagementCommandSuccess(
            raw     = "SIM_ACK:PROV",
            slotId  = slotId,
            name    = sanitized,
            counter = counter,
            message = "Simulator provisioning complete",
        )
    }

    override suspend fun rename(slotId: Int, name: String): BleManagementCommandSuccess {
        ensureReady()
        validateSlotId(slotId)
        ensureWritable(slotId)
        val sanitized = name.take(24)
        mutateSlot(slotId) { slot ->
            slot.copy(name = sanitized, used = slot.used || sanitized.isNotEmpty())
        }
        val slot = slotById(slotId)!!
        return BleManagementCommandSuccess(
            raw     = "SIM_ACK:RENAME",
            slotId  = slotId,
            name    = slot.name,
            counter = slot.counter,
            message = "Simulator rename complete",
        )
    }

    override suspend fun revoke(slotId: Int): BleManagementCommandSuccess {
        ensureReady()
        validateSlotId(slotId)
        ensureWritable(slotId)
        mutateSlot(slotId) { it.copy(used = false, counter = 0u, name = "") }
        return BleManagementCommandSuccess(
            raw     = "SIM_ACK:REVOKE",
            slotId  = slotId,
            name    = null,
            counter = 0u,
            message = "Simulator revoke complete",
        )
    }

    override suspend fun recover(
        slotId: Int, key: ByteArray, counter: UInt, name: String,
    ): BleManagementCommandSuccess = provision(slotId, key, counter, name)

    // ── Slot persistence ──────────────────────────────────────────────────────

    private data class SimSlot(
        val id: Int,
        val used: Boolean,
        val counter: UInt,
        val name: String,
    )

    private fun defaultSlots(): List<SimSlot> = listOf(
        SimSlot(0, used = true,  counter = 0u, name = "Uguisu"),
        SimSlot(1, used = false, counter = 0u, name = ""),
        SimSlot(2, used = false, counter = 0u, name = ""),
        SimSlot(3, used = false, counter = 0u, name = ""),
    )

    private fun loadSlots(): List<SimSlot> {
        val json = prefs.getString(SLOTS_KEY, null) ?: return defaultSlots()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                SimSlot(
                    id      = obj.getInt("id"),
                    used    = obj.getBoolean("used"),
                    counter = obj.getLong("counter").toUInt(),
                    name    = obj.optString("name", ""),
                )
            }
        } catch (_: Exception) {
            defaultSlots()
        }
    }

    private fun saveSlots(slots: List<SimSlot>) {
        val arr = JSONArray()
        slots.sortedBy { it.id }.forEach { s ->
            arr.put(JSONObject().apply {
                put("id",      s.id)
                put("used",    s.used)
                put("counter", s.counter.toLong())
                put("name",    s.name)
            })
        }
        prefs.edit().putString(SLOTS_KEY, arr.toString()).apply()
    }

    private fun slotById(slotId: Int): SimSlot? =
        loadSlots().firstOrNull { it.id == slotId }

    private fun mutateSlot(slotId: Int, transform: (SimSlot) -> SimSlot) {
        val slots = loadSlots().map { if (it.id == slotId) transform(it) else it }
        saveSlots(slots)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun ensureReady() {
        if (_sessionState.value.connectionState != BleManagementSessionConnectionState.READY) {
            throw BleManagementException("Simulator management session is not connected")
        }
    }

    private fun validateSlotId(slotId: Int) {
        require(slotId in 0..3) { "Slot ID must be between 0 and 3" }
    }

    private fun ensureWritable(slotId: Int) {
        if (slotId == 0) {
            throw BleManagementException("Slot 0 stays read-only in the simulator")
        }
    }
}

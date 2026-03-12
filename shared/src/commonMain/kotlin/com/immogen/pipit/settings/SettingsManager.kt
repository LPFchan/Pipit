package com.immogen.pipit.settings

interface SettingsManager {
    fun getBoolean(key: String, defaultValue: Boolean): Boolean
    fun setBoolean(key: String, value: Boolean)
    
    fun getInt(key: String, defaultValue: Int): Int
    fun setInt(key: String, value: Int)
}

object ProximitySettings {
    const val PREF_PROXIMITY_ENABLED = "pref_proximity_enabled"
    const val PREF_UNLOCK_RSSI = "pref_unlock_rssi"
    const val PREF_LOCK_RSSI = "pref_lock_rssi"
    
    const val DEFAULT_PROXIMITY_ENABLED = true
    const val DEFAULT_UNLOCK_RSSI = -65
    const val DEFAULT_LOCK_RSSI = -75
}

class AppSettings(private val manager: SettingsManager) {
    var isProximityEnabled: Boolean
        get() = manager.getBoolean(ProximitySettings.PREF_PROXIMITY_ENABLED, ProximitySettings.DEFAULT_PROXIMITY_ENABLED)
        set(value) = manager.setBoolean(ProximitySettings.PREF_PROXIMITY_ENABLED, value)
        
    var unlockRssi: Int
        get() = manager.getInt(ProximitySettings.PREF_UNLOCK_RSSI, ProximitySettings.DEFAULT_UNLOCK_RSSI)
        set(value) = manager.setInt(ProximitySettings.PREF_UNLOCK_RSSI, value)
        
    var lockRssi: Int
        get() = manager.getInt(ProximitySettings.PREF_LOCK_RSSI, ProximitySettings.DEFAULT_LOCK_RSSI)
        set(value) = manager.setInt(ProximitySettings.PREF_LOCK_RSSI, value)
}

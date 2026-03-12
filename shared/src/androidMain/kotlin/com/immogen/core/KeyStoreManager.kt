package com.immogen.core

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import android.util.Base64

/**
 * Android implementation uses AndroidX Security EncryptedSharedPreferences.
 * Note: KeyStoreManager.init(context) must be called from the Android Application class
 * before any methods are used.
 */
actual class KeyStoreManager {
    
    actual fun saveKey(slotId: Int, key: ByteArray) {
        require(key.size == 16) { "Key must be exactly 16 bytes" }
        val prefs = getPrefs()
        val base64Key = Base64.encodeToString(key, Base64.NO_WRAP)
        prefs.edit().putString("key_slot_$slotId", base64Key).apply()
    }
    
    actual fun loadKey(slotId: Int): ByteArray? {
        val prefs = getPrefs()
        val base64Key = prefs.getString("key_slot_$slotId", null) ?: return null
        return try {
            val key = Base64.decode(base64Key, Base64.NO_WRAP)
            if (key.size == 16) key else null
        } catch (e: Exception) {
            null
        }
    }
    
    actual fun deleteKey(slotId: Int) {
        val prefs = getPrefs()
        prefs.edit()
            .remove("key_slot_$slotId")
            .remove("counter_slot_$slotId")
            .apply()
    }
    
    actual fun saveCounter(slotId: Int, counter: UInt) {
        val prefs = getPrefs()
        // SharedPreferences doesn't support UInt natively, so we store it as a Long (to prevent sign issues)
        prefs.edit().putLong("counter_slot_$slotId", counter.toLong()).apply()
    }
    
    actual fun loadCounter(slotId: Int): UInt {
        val prefs = getPrefs()
        val value = prefs.getLong("counter_slot_$slotId", 0L)
        return value.toUInt()
    }
    
    private fun getPrefs(): android.content.SharedPreferences {
        val ctx = appContext ?: throw IllegalStateException("KeyStoreManager not initialized. Call KeyStoreManager.init(context) first.")
        
        val masterKey = MasterKey.Builder(ctx)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
            
        return EncryptedSharedPreferences.create(
            ctx,
            "immogen_secure_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }
    
    companion object {
        private var appContext: Context? = null
        
        fun init(context: Context) {
            appContext = context.applicationContext
        }
    }
}
package com.immogen.core

/**
 * Platform-agnostic interface for secure storage of AES-CCM keys and monotonic counters.
 * 
 * On iOS, this uses the native Keychain.
 * On Android, this uses EncryptedSharedPreferences / Android Keystore.
 */
expect class KeyStoreManager() {
    
    /**
     * Stores a 16-byte AES key for the specified slot.
     * Overwrites any existing key in that slot.
     */
    fun saveKey(slotId: Int, key: ByteArray)
    
    /**
     * Retrieves the 16-byte AES key for the specified slot.
     * @return The 16-byte array, or null if no key exists for the slot.
     */
    fun loadKey(slotId: Int): ByteArray?
    
    /**
     * Deletes the AES key and associated counter for the specified slot.
     */
    fun deleteKey(slotId: Int)
    
    /**
     * Saves the current monotonic counter value for the specified slot.
     */
    fun saveCounter(slotId: Int, counter: UInt)
    
    /**
     * Retrieves the last stored monotonic counter value for the specified slot.
     * @return The counter value, or 0u if none exists.
     */
    fun loadCounter(slotId: Int): UInt
}
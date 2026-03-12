package com.immogen.core

/**
 * High-level builder for Immogen AES-CCM BLE payloads.
 */
class PayloadBuilder {
    
    /**
     * Builds the 14-byte encrypted payload.
     * @param slotId The key slot ID (0-3).
     * @param command The command to execute (Unlock, Lock, Identify).
     * @param key The 16-byte AES key for the specified slot.
     * @param counter The monotonic counter to use for this payload.
     * @return A 14-byte array containing the payload.
     */
    fun buildPayload(
        slotId: Int,
        command: ImmoCrypto.Command,
        key: ByteArray,
        counter: UInt
    ): ByteArray {
        require(slotId in 0..3) { "Slot ID must be between 0 and 3" }
        require(key.size == 16) { "Key must be exactly 16 bytes" }
        
        val prefix = (slotId shl 4).toByte()
        
        val nonce = ByteArray(ImmoCrypto.NONCE_LEN)
        ImmoCrypto.buildNonce(counter, nonce)
        
        val msg = ByteArray(ImmoCrypto.MSG_LEN)
        ImmoCrypto.buildMsg(prefix, counter, command, msg)
        
        val ct = ByteArray(ImmoCrypto.MSG_LEN)
        val mic = ByteArray(ImmoCrypto.MIC_LEN)
        
        // AAD length is 5 (prefix + counter)
        val success = ImmoCrypto.ccmAuthEncrypt(
            key = key,
            nonce = nonce,
            msg = msg,
            msgLen = ImmoCrypto.MSG_LEN,
            aadLen = 5,
            outCt = ct,
            outMic = mic
        )
        
        check(success) { "Failed to encrypt payload" }
        
        val payload = ByteArray(ImmoCrypto.PAYLOAD_LEN)
        System.arraycopy(ct, 0, payload, 0, ImmoCrypto.MSG_LEN)
        System.arraycopy(mic, 0, payload, ImmoCrypto.MSG_LEN, ImmoCrypto.MIC_LEN)
        
        return payload
    }
}

/**
 * Manages the strictly monotonic counter for key slots.
 * Note: Implementers must persist the current counter value to non-volatile storage
 * to prevent replay attacks across app restarts.
 */
class CounterState(initialCounter: UInt = 0u) {
    private var _counter: UInt = initialCounter
    
    /**
     * Returns the current counter value and increments it strictly.
     * Note: Not thread-safe by default. Caller should synchronize if needed.
     */
    fun nextCounter(): UInt {
        val current = _counter
        _counter++
        // Prevent overflow to 0
        if (_counter == 0u) {
            _counter = 1u
        }
        return current
    }
    
    fun currentCounter(): UInt = _counter
    
    /**
     * Sets the counter. Must only be used when restoring state or provisioning.
     */
    fun setCounter(value: UInt) {
        _counter = value
    }
}

package com.immogen.core

import com.ionspin.kotlin.crypto.LibsodiumInitializer
import com.ionspin.kotlin.crypto.pwhash.PasswordHash
import com.ionspin.kotlin.crypto.pwhash.crypto_pwhash_ALG_DEFAULT
import com.ionspin.kotlin.crypto.pwhash.crypto_pwhash_argon2i_ALG_ARGON2I13
import com.ionspin.kotlin.crypto.pwhash.crypto_pwhash_argon2id_ALG_ARGON2ID13
import kotlin.math.min
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Pure Kotlin AES-CCM implementation matching the Guillemot C++ `immo_crypto` logic.
 */
object ImmoCrypto {

    const val MIC_LEN = 8
    const val MSG_LEN = 6      // prefix(1) + counter(4) + command(1)
    const val PAYLOAD_LEN = 14 // msg(6) + mic(8)
    const val NONCE_LEN = 13   // le32(counter) + zeros(9)
    const val QR_SALT_LEN = 16
    const val QR_KEY_LEN = 16
    const val QR_ENCRYPTED_KEY_LEN = QR_KEY_LEN + MIC_LEN

    enum class ArgonVariant {
        Argon2d,
        Argon2i,
        Argon2id,
    }

    data class Argon2Params(
        val parallelism: Int = 1,
        val outputLength: UInt = QR_KEY_LEN.toUInt(),
        val requestedMemoryKiB: UInt = 262144u,
        val iterations: Int = 3,
        val key: ByteArray = ByteArray(0),
        val associatedData: ByteArray = ByteArray(0),
        val variant: ArgonVariant = ArgonVariant.Argon2id,
    )

    open class ProvisioningCryptoException(message: String) : Exception(message)

    class InvalidProvisioningDataException(message: String) : ProvisioningCryptoException(message)

    class InvalidProvisioningPinException :
        ProvisioningCryptoException("Invalid PIN or corrupted provisioning payload")

    enum class Command(val value: Byte) {
        Unlock(0x01),
        Lock(0x02),
        Identify(0x03),
        Window(0x04);

        companion object {
            fun fromValue(value: Byte): Command? = values().find { it.value == value }
        }
    }

    private fun le32Write(out: ByteArray, offset: Int, x: UInt) {
        val xInt = x.toInt()
        out[offset] = (xInt and 0xFF).toByte()
        out[offset + 1] = ((xInt shr 8) and 0xFF).toByte()
        out[offset + 2] = ((xInt shr 16) and 0xFF).toByte()
        out[offset + 3] = ((xInt shr 24) and 0xFF).toByte()
    }

    fun buildNonce(counter: UInt, nonce: ByteArray) {
        require(nonce.size >= NONCE_LEN)
        le32Write(nonce, 0, counter)
        for (i in 4 until NONCE_LEN) {
            nonce[i] = 0
        }
    }

    fun buildMsg(prefix: Byte, counter: UInt, command: Command, msg: ByteArray) {
        require(msg.size >= MSG_LEN)
        msg[0] = prefix
        le32Write(msg, 1, counter)
        msg[5] = command.value
    }

    suspend fun initialize() {
        if (!LibsodiumInitializer.isInitialized()) {
            LibsodiumInitializer.initialize()
        }
    }

    fun isInitialized(): Boolean = LibsodiumInitializer.isInitialized()

    @OptIn(ExperimentalUnsignedTypes::class)
    fun deriveKey(
        pin: String,
        salt: ByteArray,
        params: Argon2Params = Argon2Params(),
    ): ByteArray {
        validateSalt(salt)
        require(pin.isNotEmpty()) { "PIN must not be empty" }
        check(LibsodiumInitializer.isInitialized()) { "Libsodium must be initialized before deriving keys" }

        val memLimitBytesLong = params.requestedMemoryKiB.toLong() * 1024L
        require(memLimitBytesLong <= Int.MAX_VALUE.toLong()) { "Requested memory exceeds Int range" }

        return PasswordHash.pwhash(
            outputLength = params.outputLength.toInt(),
            password = pin,
            salt = salt.toUByteArray(),
            opsLimit = params.iterations.toULong(),
            memLimit = memLimitBytesLong.toInt(),
            algorithm = params.variant.toPasswordHashAlgorithm(),
        ).toByteArray()
    }

    fun decryptProvisionedKey(
        pin: String,
        salt: ByteArray,
        encryptedKey: ByteArray,
        params: Argon2Params = Argon2Params(),
    ): ByteArray {
        val derivedKey = deriveKey(pin, salt, params)
        return decryptProvisionedKey(derivedKey, salt, encryptedKey)
    }

    suspend fun decryptProvisionedKeyAsync(
        pin: String,
        salt: ByteArray,
        encryptedKey: ByteArray,
        params: Argon2Params = Argon2Params(),
    ): ByteArray = withContext(Dispatchers.Default) {
        if (!isInitialized()) {
            initialize()
        }
        decryptProvisionedKey(pin, salt, encryptedKey, params)
    }

    /**
     * Non-suspend variant for ObjC/Swift callers that bypasses the ObjCExportCoroutines
     * bridge. Work runs on Dispatchers.Default; callbacks fire on that same thread.
     */
    fun decryptProvisionedKeyBackground(
        pin: String,
        salt: ByteArray,
        encryptedKey: ByteArray,
        params: Argon2Params = Argon2Params(),
        onSuccess: (ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        GlobalScope.launch(Dispatchers.Default) {
            try {
                if (!isInitialized()) initialize()
                onSuccess(decryptProvisionedKey(pin, salt, encryptedKey, params))
            } catch (e: Throwable) {
                onError(e.message ?: "Decryption failed")
            }
        }
    }

    fun decryptProvisionedKey(
        derivedKey: ByteArray,
        salt: ByteArray,
        encryptedKey: ByteArray,
    ): ByteArray {
        validateSalt(salt)
        validateKeyLength(derivedKey, "Derived key")
        validateEncryptedKey(encryptedKey)

        val nonce = salt.copyOf(NONCE_LEN)
        val ciphertext = encryptedKey.copyOfRange(0, QR_KEY_LEN)
        val mic = encryptedKey.copyOfRange(QR_KEY_LEN, QR_ENCRYPTED_KEY_LEN)
        val plaintext = ByteArray(QR_KEY_LEN)

        if (!ccmAuthDecrypt(derivedKey, nonce, ciphertext, ciphertext.size, 0, mic, plaintext)) {
            throw InvalidProvisioningPinException()
        }

        return plaintext
    }

    fun encryptProvisionedKey(
        derivedKey: ByteArray,
        salt: ByteArray,
        slotKey: ByteArray,
    ): ByteArray {
        validateSalt(salt)
        validateKeyLength(derivedKey, "Derived key")
        validateKeyLength(slotKey, "Slot key")

        val nonce = salt.copyOf(NONCE_LEN)
        val ciphertext = ByteArray(slotKey.size)
        val mic = ByteArray(MIC_LEN)
        val success = ccmAuthEncrypt(
            key = derivedKey,
            nonce = nonce,
            msg = slotKey,
            msgLen = slotKey.size,
            aadLen = 0,
            outCt = ciphertext,
            outMic = mic,
        )

        check(success) { "Failed to encrypt provisioning payload" }
        return ciphertext + mic
    }

    private fun xorBlock(dst: ByteArray, a: ByteArray, b: ByteArray, offsetA: Int = 0, offsetB: Int = 0) {
        for (i in 0 until 16) {
            dst[i] = (a[offsetA + i].toInt() xor b[offsetB + i].toInt()).toByte()
        }
    }

    fun ccmAuthEncrypt(
        key: ByteArray,
        nonce: ByteArray,
        msg: ByteArray,
        msgLen: Int,
        aadLen: Int,
        outCt: ByteArray,
        outMic: ByteArray
    ): Boolean {
        if (msgLen > 0xFFFF || aadLen > msgLen) return false

        val payloadLen = msgLen - aadLen
        val L = 2
        val M = MIC_LEN

        // RFC 3610: B0 = Flags | Nonce | PayloadLength
        val flagsB0 = ((if (aadLen > 0) 0x40 else 0) or (((M - 2) / 2) shl 3) or (L - 1)).toByte()

        val b0 = ByteArray(16)
        b0[0] = flagsB0
        nonce.copyInto(b0, destinationOffset = 1, startIndex = 0, endIndex = NONCE_LEN)
        b0[14] = ((payloadLen shr 8) and 0xFF).toByte()
        b0[15] = (payloadLen and 0xFF).toByte()

        val x = ByteArray(16)
        val tmp = ByteArray(16)
        xorBlock(tmp, x, b0)
        Aes128.encryptBlock(key, tmp, x)

        if (aadLen > 0) {
            val block = ByteArray(16)
            block[0] = ((aadLen shr 8) and 0xFF).toByte()
            block[1] = (aadLen and 0xFF).toByte()

            var aadIdx = 0
            var blockIdx = 2
            while (aadIdx < aadLen) {
                val n = min(16 - blockIdx, aadLen - aadIdx)
                msg.copyInto(block, destinationOffset = blockIdx, startIndex = aadIdx, endIndex = aadIdx + n)
                aadIdx += n
                blockIdx += n

                if (blockIdx == 16 || aadIdx == aadLen) {
                    xorBlock(tmp, x, block)
                    Aes128.encryptBlock(key, tmp, x)
                    for (i in 0 until 16) block[i] = 0
                    blockIdx = 0
                }
            }
        }

        var payloadIdx = 0
        while (payloadIdx < payloadLen) {
            val block = ByteArray(16)
            val n = min(16, payloadLen - payloadIdx)
            msg.copyInto(block, destinationOffset = 0, startIndex = aadLen + payloadIdx, endIndex = aadLen + payloadIdx + n)
            xorBlock(tmp, x, block)
            Aes128.encryptBlock(key, tmp, x)
            payloadIdx += n
        }

        val a0 = ByteArray(16)
        a0[0] = (L - 1).toByte()
        nonce.copyInto(a0, destinationOffset = 1, startIndex = 0, endIndex = NONCE_LEN)

        val s0 = ByteArray(16)
        Aes128.encryptBlock(key, a0, s0)
        for (i in 0 until M) {
            outMic[i] = (x[i].toInt() xor s0[i].toInt()).toByte()
        }

        msg.copyInto(outCt, destinationOffset = 0, startIndex = 0, endIndex = aadLen)

        var offsetEnc = 0
        var ctrI = 1
        while (offsetEnc < payloadLen) {
            val ai = ByteArray(16)
            ai[0] = (L - 1).toByte()
            nonce.copyInto(ai, destinationOffset = 1, startIndex = 0, endIndex = NONCE_LEN)
            ai[14] = ((ctrI shr 8) and 0xFF).toByte()
            ai[15] = (ctrI and 0xFF).toByte()

            val si = ByteArray(16)
            Aes128.encryptBlock(key, ai, si)

            val n = min(16, payloadLen - offsetEnc)
            for (j in 0 until n) {
                outCt[aadLen + offsetEnc + j] = (msg[aadLen + offsetEnc + j].toInt() xor si[j].toInt()).toByte()
            }
            offsetEnc += n
            ctrI++
        }

        return true
    }

    fun ccmAuthDecrypt(
        key: ByteArray,
        nonce: ByteArray,
        ct: ByteArray,
        payloadLen: Int,
        aadLen: Int,
        mic: ByteArray,
        outMsg: ByteArray,
    ): Boolean {
        if (payloadLen > ct.size || aadLen > payloadLen || mic.size < MIC_LEN || outMsg.size < payloadLen) {
            return false
        }

        ct.copyInto(outMsg, destinationOffset = 0, startIndex = 0, endIndex = aadLen)

        val encryptedPayloadLen = payloadLen - aadLen
        val l = 2
        var offsetEnc = 0
        var ctrI = 1

        while (offsetEnc < encryptedPayloadLen) {
            val ai = ByteArray(16)
            ai[0] = (l - 1).toByte()
            nonce.copyInto(ai, destinationOffset = 1, startIndex = 0, endIndex = NONCE_LEN)
            ai[14] = ((ctrI shr 8) and 0xFF).toByte()
            ai[15] = (ctrI and 0xFF).toByte()

            val si = ByteArray(16)
            Aes128.encryptBlock(key, ai, si)

            val n = min(16, encryptedPayloadLen - offsetEnc)
            for (j in 0 until n) {
                outMsg[aadLen + offsetEnc + j] = (ct[aadLen + offsetEnc + j].toInt() xor si[j].toInt()).toByte()
            }
            offsetEnc += n
            ctrI++
        }

        val expectedCt = ByteArray(payloadLen)
        val expectedMic = ByteArray(MIC_LEN)
        val success = ccmAuthEncrypt(
            key = key,
            nonce = nonce,
            msg = outMsg,
            msgLen = payloadLen,
            aadLen = aadLen,
            outCt = expectedCt,
            outMic = expectedMic,
        )

        if (!success || !constantTimeEq(expectedMic, mic, MIC_LEN)) {
            outMsg.fill(0)
            return false
        }

        return true
    }

    fun constantTimeEq(a: ByteArray, b: ByteArray, n: Int): Boolean {
        var diff = 0
        for (i in 0 until n) {
            diff = diff or (a[i].toInt() xor b[i].toInt())
        }
        return diff == 0
    }

    private fun validateSalt(salt: ByteArray) {
        if (salt.size != QR_SALT_LEN) {
            throw InvalidProvisioningDataException("Salt must be exactly 16 bytes")
        }
    }

    private fun validateKeyLength(key: ByteArray, label: String) {
        if (key.size != QR_KEY_LEN) {
            throw InvalidProvisioningDataException("$label must be exactly 16 bytes")
        }
    }

    private fun validateEncryptedKey(encryptedKey: ByteArray) {
        if (encryptedKey.size != QR_ENCRYPTED_KEY_LEN) {
            throw InvalidProvisioningDataException("Encrypted key must be exactly 24 bytes")
        }
    }

    private fun ArgonVariant.toPasswordHashAlgorithm(): Int = when (this) {
        ArgonVariant.Argon2d -> crypto_pwhash_ALG_DEFAULT
        ArgonVariant.Argon2i -> crypto_pwhash_argon2i_ALG_ARGON2I13
        ArgonVariant.Argon2id -> crypto_pwhash_argon2id_ALG_ARGON2ID13
    }
}

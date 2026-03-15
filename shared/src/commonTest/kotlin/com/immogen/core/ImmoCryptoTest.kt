package com.immogen.core

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ImmoCryptoTest {

    private fun ensureInitialized() {
        runBlocking {
            ImmoCrypto.initialize()
        }
    }

    @Test
    fun deriveKeyMatchesDocumentedArgon2Vector() {
        ensureInitialized()

        val params = ImmoCrypto.Argon2Params(
            parallelism = 8,
            outputLength = 64u,
            requestedMemoryKiB = 256u,
            iterations = 4,
            variant = ImmoCrypto.ArgonVariant.Argon2id,
        )

        val derived = ImmoCrypto.deriveKey(
            pin = "Password",
            salt = "RandomSalt123456".encodeToByteArray(),
            params = params,
        )

        assertEquals(
            "749333bf8391297d153292d1f81fd1d8e2d0d386e9c04da9b5bc9a39d73efba38c0beba1c97860492bd17d4d778c6a064a3bbadce7839f1e652d5f8eaea75bc8",
            derived.toHex(),
        )
    }

    @Test
    fun encryptAndDecryptProvisionedKeyRoundTrip() {
        ensureInitialized()

        val params = ImmoCrypto.Argon2Params(requestedMemoryKiB = 1024u, iterations = 2)
        val salt = hexStringToByteArray("00112233445566778899aabbccddeeff")
        val slotKey = hexStringToByteArray("4a2b9c8f33d7c6e5a9b1f8e7d6c5b4a3")
        val derived = ImmoCrypto.deriveKey("123456", salt, params)
        val encrypted = ImmoCrypto.encryptProvisionedKey(derived, salt, slotKey)

        val decrypted = ImmoCrypto.decryptProvisionedKey("123456", salt, encrypted, params)

        assertContentEquals(slotKey, decrypted)
        assertEquals(ImmoCrypto.QR_ENCRYPTED_KEY_LEN, encrypted.size)
    }

    @Test
    fun decryptProvisionedKeyRejectsWrongPin() {
        ensureInitialized()

        val params = ImmoCrypto.Argon2Params(requestedMemoryKiB = 1024u, iterations = 2)
        val salt = hexStringToByteArray("0f1e2d3c4b5a69788796a5b4c3d2e1f0")
        val slotKey = hexStringToByteArray("00112233445566778899aabbccddeeff")
        val derived = ImmoCrypto.deriveKey("123456", salt, params)
        val encrypted = ImmoCrypto.encryptProvisionedKey(derived, salt, slotKey)

        assertFailsWith<ImmoCrypto.InvalidProvisioningPinException> {
            ImmoCrypto.decryptProvisionedKey("654321", salt, encrypted, params)
        }
    }

    @Test
    fun decryptProvisionedKeyRejectsMalformedLengths() {
        val salt = ByteArray(ImmoCrypto.QR_SALT_LEN)
        val derived = ByteArray(ImmoCrypto.QR_KEY_LEN)

        assertFailsWith<ImmoCrypto.InvalidProvisioningDataException> {
            ImmoCrypto.decryptProvisionedKey(derived, salt.copyOf(8), ByteArray(ImmoCrypto.QR_ENCRYPTED_KEY_LEN))
        }

        assertFailsWith<ImmoCrypto.InvalidProvisioningDataException> {
            ImmoCrypto.decryptProvisionedKey(derived, salt, ByteArray(12))
        }
    }

    @Test
    fun ccmAuthDecryptValidatesMic() {
        val key = hexStringToByteArray("000102030405060708090a0b0c0d0e0f")
        val nonce = ByteArray(ImmoCrypto.NONCE_LEN)
        nonce[0] = 1
        val plaintext = byteArrayOf(0x01)
        val ciphertext = ByteArray(plaintext.size)
        val mic = ByteArray(ImmoCrypto.MIC_LEN)

        assertTrue(
            ImmoCrypto.ccmAuthEncrypt(
                key = key,
                nonce = nonce,
                msg = plaintext,
                msgLen = plaintext.size,
                aadLen = 0,
                outCt = ciphertext,
                outMic = mic,
            )
        )

        val decrypted = ByteArray(plaintext.size)
        assertTrue(
            ImmoCrypto.ccmAuthDecrypt(
                key = key,
                nonce = nonce,
                ct = ciphertext,
                payloadLen = ciphertext.size,
                aadLen = 0,
                mic = mic,
                outMsg = decrypted,
            )
        )
        assertContentEquals(plaintext, decrypted)
    }
}

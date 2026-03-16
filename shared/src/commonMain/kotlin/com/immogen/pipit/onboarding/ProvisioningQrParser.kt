package com.immogen.pipit.onboarding

import com.immogen.core.ImmoCrypto
import com.immogen.core.hexStringToByteArray

sealed interface ProvisioningQrPayload {
    val slotId: Int
    val counter: UInt
    val name: String

    data class Guest(
        override val slotId: Int,
        val key: ByteArray,
        override val counter: UInt,
        override val name: String,
    ) : ProvisioningQrPayload

    data class Encrypted(
        override val slotId: Int,
        val salt: ByteArray,
        val encryptedKey: ByteArray,
        override val counter: UInt,
        override val name: String,
    ) : ProvisioningQrPayload
}

sealed class ProvisioningQrParseException(message: String) : IllegalArgumentException(message) {
    class MissingField(fieldName: String) : ProvisioningQrParseException("Missing required field: $fieldName")
    class InvalidField(fieldName: String, detail: String) : ProvisioningQrParseException("Invalid $fieldName: $detail")
    class UnsupportedVariant(detail: String) : ProvisioningQrParseException(detail)
}

object ProvisioningQrParser {
    private const val PROVISIONING_PREFIX = "immogen://prov?"

    fun parseIfProvisioningQr(raw: String): ProvisioningQrPayload? {
        if (!raw.startsWith(PROVISIONING_PREFIX)) {
            return null
        }

        return parse(raw)
    }

    fun parse(raw: String): ProvisioningQrPayload {
        require(raw.startsWith(PROVISIONING_PREFIX)) {
            "Unsupported provisioning URI: $raw"
        }

        val params = parseQuery(raw.removePrefix(PROVISIONING_PREFIX))
        val slotId = parseSlotId(params.requireValue("slot"))
        val counter = parseCounter(params.requireValue("ctr"))
        val name = params["name"] ?: ""
        val keyHex = params["key"]
        val saltHex = params["salt"]
        val encryptedKeyHex = params["ekey"]

        return when {
            keyHex != null && saltHex == null && encryptedKeyHex == null -> {
                val key = parseHex("key", keyHex, ImmoCrypto.QR_KEY_LEN)
                ProvisioningQrPayload.Guest(
                    slotId = slotId,
                    key = key,
                    counter = counter,
                    name = name,
                )
            }

            keyHex == null && saltHex != null && encryptedKeyHex != null -> {
                val salt = parseHex("salt", saltHex, ImmoCrypto.QR_SALT_LEN)
                val encryptedKey = parseHex("ekey", encryptedKeyHex, ImmoCrypto.QR_ENCRYPTED_KEY_LEN)
                ProvisioningQrPayload.Encrypted(
                    slotId = slotId,
                    salt = salt,
                    encryptedKey = encryptedKey,
                    counter = counter,
                    name = name,
                )
            }

            keyHex == null && (saltHex != null || encryptedKeyHex != null) -> {
                throw ProvisioningQrParseException.MissingField("ekey/salt")
            }

            keyHex != null && (saltHex != null || encryptedKeyHex != null) -> {
                throw ProvisioningQrParseException.UnsupportedVariant(
                    "Provisioning QR cannot mix guest and encrypted owner fields"
                )
            }

            else -> throw ProvisioningQrParseException.UnsupportedVariant(
                "Provisioning QR must contain either key or salt+ekey fields"
            )
        }
    }

    private fun parseQuery(query: String): Map<String, String> {
        if (query.isEmpty()) {
            return emptyMap()
        }

        return buildMap {
            for (pair in query.split('&')) {
                if (pair.isEmpty()) {
                    continue
                }

                val delimiterIndex = pair.indexOf('=')
                val rawKey: String
                val rawValue: String
                if (delimiterIndex >= 0) {
                    rawKey = pair.substring(0, delimiterIndex)
                    rawValue = pair.substring(delimiterIndex + 1)
                } else {
                    rawKey = pair
                    rawValue = ""
                }

                put(percentDecode(rawKey), percentDecode(rawValue))
            }
        }
    }

    private fun parseSlotId(raw: String): Int {
        val slotId = raw.toIntOrNull()
            ?: throw ProvisioningQrParseException.InvalidField("slot", "expected integer")

        if (slotId !in 0 until OnboardingGate.SLOT_COUNT) {
            throw ProvisioningQrParseException.InvalidField(
                "slot",
                "must be between 0 and ${OnboardingGate.SLOT_COUNT - 1}",
            )
        }

        return slotId
    }

    private fun parseCounter(raw: String): UInt {
        return raw.toUIntOrNull()
            ?: throw ProvisioningQrParseException.InvalidField("ctr", "expected unsigned integer")
    }

    private fun parseHex(fieldName: String, raw: String, expectedSize: Int): ByteArray {
        val bytes = try {
            hexStringToByteArray(raw)
        } catch (_: IllegalArgumentException) {
            throw ProvisioningQrParseException.InvalidField(fieldName, "expected hex string")
        }

        if (bytes.size != expectedSize) {
            throw ProvisioningQrParseException.InvalidField(
                fieldName,
                "expected $expectedSize bytes but was ${bytes.size}",
            )
        }

        return bytes
    }

    private fun Map<String, String>.requireValue(key: String): String {
        return this[key] ?: throw ProvisioningQrParseException.MissingField(key)
    }

    private fun percentDecode(value: String): String {
        val output = StringBuilder(value.length)
        var index = 0
        while (index < value.length) {
            val ch = value[index]
            when (ch) {
                '+' -> {
                    output.append(' ')
                    index += 1
                }

                '%' -> {
                    if (index + 2 >= value.length) {
                        throw ProvisioningQrParseException.InvalidField("query", "incomplete percent escape")
                    }

                    val decoded = decodeHexByte(value[index + 1], value[index + 2])
                    output.append(decoded.toInt().toChar())
                    index += 3
                }

                else -> {
                    output.append(ch)
                    index += 1
                }
            }
        }

        return output.toString()
    }

    private fun decodeHexByte(high: Char, low: Char): Byte {
        val highNibble = decodeHexChar(high)
        val lowNibble = decodeHexChar(low)
        return ((highNibble shl 4) or lowNibble).toByte()
    }

    private fun decodeHexChar(ch: Char): Int = when (ch) {
        in '0'..'9' -> ch - '0'
        in 'a'..'f' -> ch - 'a' + 10
        in 'A'..'F' -> ch - 'A' + 10
        else -> throw ProvisioningQrParseException.InvalidField("query", "invalid percent escape")
    }
}
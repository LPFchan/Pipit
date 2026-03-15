package com.immogen.pipit.ble

import com.immogen.core.ImmoCrypto
import com.immogen.core.KeyStoreManager
import com.immogen.core.PayloadBuilder
import com.immogen.core.toHex
import kotlinx.coroutines.flow.StateFlow

enum class BleManagementConnectMode {
    STANDARD,
    WINDOW_OPEN_RECOVERY
}

enum class BleManagementSessionConnectionState {
    DISCONNECTED,
    CONNECTING,
    DISCOVERING,
    READY,
    ERROR
}

data class BleManagementSessionState(
    val connectionState: BleManagementSessionConnectionState = BleManagementSessionConnectionState.DISCONNECTED,
    val mode: BleManagementConnectMode? = null,
    val deviceAddress: String? = null,
    val mtu: Int? = null,
    val lastError: String? = null
)

data class BleManagementFrame(
    val commandName: String,
    val payload: ByteArray,
    val isBinary: Boolean = false
)

data class BleManagementSlot(
    val id: Int,
    val used: Boolean,
    val counter: UInt,
    val name: String
)

sealed interface BleManagementResponse {
    val raw: String
}

data class BleManagementCommandSuccess(
    override val raw: String,
    val slotId: Int? = null,
    val name: String? = null,
    val counter: UInt? = null,
    val message: String? = null
) : BleManagementResponse

data class BleManagementSlotsResponse(
    override val raw: String,
    val slots: List<BleManagementSlot>
) : BleManagementResponse

data class BleManagementError(
    override val raw: String,
    val code: String? = null,
    val message: String? = null
) : BleManagementResponse

open class BleManagementException(message: String, cause: Throwable? = null) : Exception(message, cause)

class BleManagementProtocolException(message: String) : BleManagementException(message)

class BleManagementResponseException(val response: BleManagementError) :
    BleManagementException(response.message ?: response.code ?: "Management command failed")

class BleManagementTimeoutException(message: String) : BleManagementException(message)

interface BleManagementTransport {
    val sessionState: StateFlow<BleManagementSessionState>

    suspend fun connect(mode: BleManagementConnectMode)
    suspend fun disconnect()
    suspend fun requestSlots(): BleManagementSlotsResponse
    suspend fun identify(slotId: Int): BleManagementCommandSuccess
    suspend fun provision(slotId: Int, key: ByteArray, counter: UInt, name: String): BleManagementCommandSuccess
    suspend fun rename(slotId: Int, name: String): BleManagementCommandSuccess
    suspend fun revoke(slotId: Int): BleManagementCommandSuccess
    suspend fun recover(slotId: Int, key: ByteArray, counter: UInt, name: String): BleManagementCommandSuccess
}

object BleManagementProtocol {
    fun buildSlotsRequest(): BleManagementFrame =
        BleManagementFrame(commandName = "SLOTS?", payload = "SLOTS?".encodeToByteArray())

    fun buildIdentifyRequest(
        slotId: Int,
        key: ByteArray,
        counter: UInt,
        payloadBuilder: PayloadBuilder = PayloadBuilder()
    ): BleManagementFrame {
        validateSlotId(slotId)
        val payload = payloadBuilder.buildPayload(
            slotId = slotId,
            counter = counter,
            command = ImmoCrypto.Command.Identify,
            key = key
        )
        return BleManagementFrame(commandName = "IDENTIFY", payload = payload, isBinary = true)
    }

    fun buildIdentifyRequest(
        slotId: Int,
        keyStoreManager: KeyStoreManager = KeyStoreManager(),
        payloadBuilder: PayloadBuilder = PayloadBuilder()
    ): BleManagementFrame {
        validateSlotId(slotId)
        val key = keyStoreManager.loadKey(slotId)
            ?: throw BleManagementProtocolException("No key stored for slot $slotId")
        val counter = keyStoreManager.loadCounter(slotId)
        require(counter != UInt.MAX_VALUE) { "Counter overflow for slot $slotId" }

        val frame = buildIdentifyRequest(
            slotId = slotId,
            key = key,
            counter = counter,
            payloadBuilder = payloadBuilder
        )
        keyStoreManager.saveCounter(slotId, counter + 1u)
        return frame
    }

    fun buildProvisionRequest(
        slotId: Int,
        key: ByteArray,
        counter: UInt,
        name: String
    ): BleManagementFrame {
        validateSlotId(slotId)
        require(key.size == 16) { "Key must be exactly 16 bytes" }
        return buildAsciiFrame(
            commandName = "PROV",
            command = "PROV:$slotId:${key.toHex()}:$counter:${encodeCommandField(name)}"
        )
    }

    fun buildRenameRequest(slotId: Int, name: String): BleManagementFrame {
        validateSlotId(slotId)
        return buildAsciiFrame(
            commandName = "RENAME",
            command = "RENAME:$slotId:${encodeCommandField(name)}"
        )
    }

    fun buildRevokeRequest(slotId: Int): BleManagementFrame {
        validateSlotId(slotId)
        return buildAsciiFrame(commandName = "REVOKE", command = "REVOKE:$slotId")
    }

    fun buildRecoverRequest(
        slotId: Int,
        key: ByteArray,
        counter: UInt,
        name: String
    ): BleManagementFrame {
        validateSlotId(slotId)
        require(key.size == 16) { "Key must be exactly 16 bytes" }
        return buildAsciiFrame(
            commandName = "RECOVER",
            command = "RECOVER:$slotId:${key.toHex()}:$counter:${encodeCommandField(name)}"
        )
    }

    fun parseResponse(raw: String): BleManagementResponse {
        val normalized = raw.trim { it <= ' ' || it == '\u0000' }
        if (normalized.isEmpty()) {
            throw BleManagementProtocolException("Empty management response")
        }

        if (normalized == "ACK") {
            return BleManagementCommandSuccess(raw = raw)
        }
        if (normalized.startsWith("ACK:")) {
            val message = normalized.removePrefix("ACK:").ifBlank { null }
            return BleManagementCommandSuccess(raw = raw, message = message)
        }
        if (normalized == "ERR") {
            return BleManagementError(raw = raw, code = "ERR")
        }
        if (normalized.startsWith("ERR:")) {
            val payload = normalized.removePrefix("ERR:")
            val parts = payload.split(':', limit = 2)
            return BleManagementError(
                raw = raw,
                code = parts.firstOrNull()?.ifBlank { null } ?: "ERR",
                message = parts.getOrNull(1)?.ifBlank { null }
            )
        }

        if (!normalized.startsWith('{')) {
            throw BleManagementProtocolException("Unsupported management response: $normalized")
        }

        val status = extractJsonString(normalized, "status")
            ?: throw BleManagementProtocolException("Management response missing status")

        return when (status) {
            "ok" -> {
                val slotsArray = extractJsonArray(normalized, "slots")
                if (slotsArray != null) {
                    BleManagementSlotsResponse(
                        raw = raw,
                        slots = extractJsonObjects(slotsArray).map { slotJson ->
                            BleManagementSlot(
                                id = extractJsonInt(slotJson, "id")
                                    ?: throw BleManagementProtocolException("Slot entry missing id"),
                                used = extractJsonBoolean(slotJson, "used")
                                    ?: throw BleManagementProtocolException("Slot entry missing used flag"),
                                counter = (extractJsonLong(slotJson, "counter")
                                    ?: throw BleManagementProtocolException("Slot entry missing counter")).toUInt(),
                                name = extractJsonString(slotJson, "name") ?: ""
                            )
                        }
                    )
                } else {
                    BleManagementCommandSuccess(
                        raw = raw,
                        slotId = extractJsonInt(normalized, "slot"),
                        name = extractJsonString(normalized, "name"),
                        counter = extractJsonLong(normalized, "counter")?.toUInt(),
                        message = extractJsonString(normalized, "msg")
                    )
                }
            }

            "error" -> BleManagementError(
                raw = raw,
                code = extractJsonString(normalized, "code"),
                message = extractJsonString(normalized, "msg")
            )

            else -> throw BleManagementProtocolException("Unknown management status: $status")
        }
    }

    private fun buildAsciiFrame(commandName: String, command: String): BleManagementFrame =
        BleManagementFrame(commandName = commandName, payload = command.encodeToByteArray())

    private fun validateSlotId(slotId: Int) {
        require(slotId in 0..3) { "Slot ID must be between 0 and 3" }
    }

    private fun encodeCommandField(value: String): String {
        if (value.isEmpty()) return ""

        val builder = StringBuilder(value.length)
        value.forEach { ch ->
            if (ch.isAsciiUnreserved()) {
                builder.append(ch)
            } else {
                val utf8 = ch.toString().encodeToByteArray()
                utf8.forEach { byte ->
                    val unsigned = byte.toInt() and 0xFF
                    builder.append('%')
                    builder.append(HEX_DIGITS[unsigned ushr 4])
                    builder.append(HEX_DIGITS[unsigned and 0x0F])
                }
            }
        }
        return builder.toString()
    }

    private fun Char.isAsciiUnreserved(): Boolean =
        this in 'A'..'Z' || this in 'a'..'z' || this in '0'..'9' || this == '-' || this == '_' || this == '.' || this == '~'

    private fun extractJsonString(json: String, key: String): String? {
        val regex = Regex("\"${Regex.escape(key)}\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"")
        return regex.find(json)?.groupValues?.get(1)?.let(::decodeJsonString)
    }

    private fun extractJsonBoolean(json: String, key: String): Boolean? {
        val regex = Regex("\"${Regex.escape(key)}\"\\s*:\\s*(true|false)")
        return regex.find(json)?.groupValues?.get(1)?.toBooleanStrictOrNull()
    }

    private fun extractJsonInt(json: String, key: String): Int? =
        extractJsonLong(json, key)?.toInt()

    private fun extractJsonLong(json: String, key: String): Long? {
        val regex = Regex("\"${Regex.escape(key)}\"\\s*:\\s*(\\d+)")
        return regex.find(json)?.groupValues?.get(1)?.toLongOrNull()
    }

    private fun extractJsonArray(json: String, key: String): String? {
        val keyIndex = json.indexOf("\"$key\"")
        if (keyIndex < 0) return null

        val openBracket = json.indexOf('[', startIndex = keyIndex)
        if (openBracket < 0) {
            throw BleManagementProtocolException("Management response missing array for $key")
        }
        return extractDelimited(json, openBracket, '[', ']')
    }

    private fun extractJsonObjects(arrayJson: String): List<String> {
        val objects = mutableListOf<String>()
        var index = 0
        while (index < arrayJson.length) {
            if (arrayJson[index] == '{') {
                val objectJson = extractDelimited(arrayJson, index, '{', '}')
                objects += objectJson
                index += objectJson.length
            } else {
                index++
            }
        }
        return objects
    }

    private fun extractDelimited(text: String, startIndex: Int, open: Char, close: Char): String {
        var depth = 0
        var inString = false
        var escaped = false

        for (index in startIndex until text.length) {
            val ch = text[index]
            if (inString) {
                if (escaped) {
                    escaped = false
                } else if (ch == '\\') {
                    escaped = true
                } else if (ch == '"') {
                    inString = false
                }
                continue
            }

            when (ch) {
                '"' -> inString = true
                open -> depth++
                close -> {
                    depth--
                    if (depth == 0) {
                        return text.substring(startIndex, index + 1)
                    }
                }
            }
        }

        throw BleManagementProtocolException("Unterminated JSON segment")
    }

    private fun decodeJsonString(encoded: String): String {
        val result = StringBuilder(encoded.length)
        var index = 0
        while (index < encoded.length) {
            val ch = encoded[index]
            if (ch != '\\') {
                result.append(ch)
                index++
                continue
            }

            require(index + 1 < encoded.length) { "Invalid JSON escape sequence" }
            when (val escaped = encoded[index + 1]) {
                '"', '\\', '/' -> result.append(escaped)
                'b' -> result.append('\b')
                'f' -> result.append('\u000C')
                'n' -> result.append('\n')
                'r' -> result.append('\r')
                't' -> result.append('\t')
                'u' -> {
                    require(index + 5 < encoded.length) { "Invalid unicode escape sequence" }
                    val codePoint = encoded.substring(index + 2, index + 6).toInt(16)
                    result.append(codePoint.toChar())
                    index += 4
                }

                else -> throw BleManagementProtocolException("Unsupported JSON escape: \\$escaped")
            }
            index += 2
        }
        return result.toString()
    }

    private val HEX_DIGITS = "0123456789ABCDEF"
}
package com.immogen.core

fun hexStringToByteArray(s: String): ByteArray {
    fun hexDigit(ch: Char): Int = when (ch) {
        in '0'..'9' -> ch - '0'
        in 'a'..'f' -> ch - 'a' + 10
        in 'A'..'F' -> ch - 'A' + 10
        else -> throw IllegalArgumentException("Invalid hex char: $ch")
    }

    val len = s.length
    require(len % 2 == 0)
    val data = ByteArray(len / 2)
    var i = 0
    while (i < len) {
        val hi = hexDigit(s[i])
        val lo = hexDigit(s[i + 1])
        data[i / 2] = ((hi shl 4) + lo).toByte()
        i += 2
    }
    return data
}

fun ByteArray.toHex(): String = buildString {
    val hex = "0123456789abcdef"
    for (b in this@toHex) {
        val v = b.toInt() and 0xFF
        append(hex[v ushr 4])
        append(hex[v and 0x0F])
    }
}

fun main() {
    val key = hexStringToByteArray("000102030405060708090a0b0c0d0e0f")
    val pb = PayloadBuilder()
    val payload = pb.buildPayload(
        slotId = 1,
        command = ImmoCrypto.Command.Unlock,
        key = key,
        counter = 1u
    )
    println("Payload: ${payload.toHex()}")
}

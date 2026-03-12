package com.immogen.core

fun hexStringToByteArray(s: String): ByteArray {
    val len = s.length
    val data = ByteArray(len / 2)
    var i = 0
    while (i < len) {
        data[i / 2] = ((Character.digit(s[i], 16) shl 4) + Character.digit(s[i + 1], 16)).toByte()
        i += 2
    }
    return data
}

fun ByteArray.toHex(): String = joinToString(separator = "") { eachByte -> "%02x".format(eachByte) }

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

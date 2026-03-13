package com.immogen.core

import kotlin.math.min

/**
 * Pure Kotlin AES-CCM implementation matching the Guillemot C++ `immo_crypto` logic.
 */
object ImmoCrypto {

    const val MIC_LEN = 8
    const val MSG_LEN = 6      // prefix(1) + counter(4) + command(1)
    const val PAYLOAD_LEN = 14 // msg(6) + mic(8)
    const val NONCE_LEN = 13   // le32(counter) + zeros(9)

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

    fun constantTimeEq(a: ByteArray, b: ByteArray, n: Int): Boolean {
        var diff = 0
        for (i in 0 until n) {
            diff = diff or (a[i].toInt() xor b[i].toInt())
        }
        return diff == 0
    }
}

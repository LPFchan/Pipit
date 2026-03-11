package com.immogen.core

/**
 * Pure Kotlin implementation of AES-128 ECB core for KMP.
 * Supports exactly 16-byte key and 16-byte block size.
 */
internal object Aes128 {
    private val SBOX = intArrayOf(
        0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
        0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
        0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
        0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
        0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
        0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
        0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
        0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
        0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
        0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
        0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
        0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
        0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
        0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
        0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
        0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
    )

    private val RCON = intArrayOf(
        0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
    )

    fun encryptBlock(key: ByteArray, input: ByteArray, output: ByteArray) {
        require(key.size == 16) { "Key must be 16 bytes" }
        require(input.size == 16) { "Input must be 16 bytes" }
        require(output.size >= 16) { "Output must be at least 16 bytes" }

        val roundKeys = IntArray(44)
        keyExpansion(key, roundKeys)

        val state = IntArray(16)
        for (i in 0 until 16) state[i] = input[i].toInt() and 0xFF

        addRoundKey(state, roundKeys, 0)

        for (round in 1..9) {
            subBytes(state)
            shiftRows(state)
            mixColumns(state)
            addRoundKey(state, roundKeys, round * 16)
        }

        subBytes(state)
        shiftRows(state)
        addRoundKey(state, roundKeys, 10 * 16)

        for (i in 0 until 16) output[i] = state[i].toByte()
    }

    private fun keyExpansion(key: ByteArray, roundKeys: IntArray) {
        for (i in 0 until 4) {
            roundKeys[i * 4] = key[i * 4].toInt() and 0xFF
            roundKeys[i * 4 + 1] = key[i * 4 + 1].toInt() and 0xFF
            roundKeys[i * 4 + 2] = key[i * 4 + 2].toInt() and 0xFF
            roundKeys[i * 4 + 3] = key[i * 4 + 3].toInt() and 0xFF
        }

        for (i in 4 until 44 step 4) {
            var k0 = roundKeys[i - 4]
            var k1 = roundKeys[i - 3]
            var k2 = roundKeys[i - 2]
            var k3 = roundKeys[i - 1]

            if (i % 16 == 0) {
                val t = k0
                k0 = SBOX[k1] xor RCON[i / 16]
                k1 = SBOX[k2]
                k2 = SBOX[k3]
                k3 = SBOX[t]
            }

            roundKeys[i] = roundKeys[i - 16] xor k0
            roundKeys[i + 1] = roundKeys[i - 15] xor k1
            roundKeys[i + 2] = roundKeys[i - 14] xor k2
            roundKeys[i + 3] = roundKeys[i - 13] xor k3
        }
    }

    private fun addRoundKey(state: IntArray, roundKeys: IntArray, offset: Int) {
        for (c in 0 until 4) {
            for (r in 0 until 4) {
                state[r * 4 + c] = state[r * 4 + c] xor roundKeys[offset + c * 4 + r]
            }
        }
    }

    private fun subBytes(state: IntArray) {
        for (i in 0 until 16) {
            state[i] = SBOX[state[i]]
        }
    }

    private fun shiftRows(state: IntArray) {
        val temp = IntArray(16)
        
        // Row 0: no shift
        temp[0] = state[0]
        temp[4] = state[4]
        temp[8] = state[8]
        temp[12] = state[12]
        
        // Row 1: shift left 1
        temp[1] = state[5]
        temp[5] = state[9]
        temp[9] = state[13]
        temp[13] = state[1]
        
        // Row 2: shift left 2
        temp[2] = state[10]
        temp[6] = state[14]
        temp[10] = state[2]
        temp[14] = state[6]
        
        // Row 3: shift left 3
        temp[3] = state[15]
        temp[7] = state[3]
        temp[11] = state[7]
        temp[15] = state[11]
        
        for (i in 0 until 16) state[i] = temp[i]
    }

    private fun mixColumns(state: IntArray) {
        val temp = IntArray(16)
        for (c in 0 until 4) {
            val s0 = state[c * 4 + 0]
            val s1 = state[c * 4 + 1]
            val s2 = state[c * 4 + 2]
            val s3 = state[c * 4 + 3]

            temp[c * 4 + 0] = mul2(s0) xor mul3(s1) xor s2 xor s3
            temp[c * 4 + 1] = s0 xor mul2(s1) xor mul3(s2) xor s3
            temp[c * 4 + 2] = s0 xor s1 xor mul2(s2) xor mul3(s3)
            temp[c * 4 + 3] = mul3(s0) xor s1 xor s2 xor mul2(s3)
        }
        for (i in 0 until 16) state[i] = temp[i]
    }

    private fun mul2(v: Int): Int {
        val res = v shl 1
        return if ((v and 0x80) != 0) (res xor 0x1b) and 0xFF else res and 0xFF
    }

    private fun mul3(v: Int): Int {
        return mul2(v) xor v
    }
}

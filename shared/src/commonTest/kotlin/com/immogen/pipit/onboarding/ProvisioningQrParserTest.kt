package com.immogen.pipit.onboarding

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull

class ProvisioningQrParserTest {
    @Test
    fun parseIfProvisioningQrIgnoresNonImmogenCodes() {
        assertNull(ProvisioningQrParser.parseIfProvisioningQr("https://example.com/qr"))
    }

    @Test
    fun parseGuestPayloadReturnsPlaintextKeyModel() {
        val payload = ProvisioningQrParser.parse(
            "immogen://prov?slot=2&key=00112233445566778899aabbccddeeff&ctr=7&name=Jamie%27s%20iPhone"
        )

        val guest = assertIs<ProvisioningQrPayload.Guest>(payload)
        assertEquals(2, guest.slotId)
        assertContentEquals(
            byteArrayOf(
                0x00,
                0x11,
                0x22,
                0x33,
                0x44,
                0x55,
                0x66,
                0x77,
                0x88.toByte(),
                0x99.toByte(),
                0xaa.toByte(),
                0xbb.toByte(),
                0xcc.toByte(),
                0xdd.toByte(),
                0xee.toByte(),
                0xff.toByte(),
            ),
            guest.key,
        )
        assertEquals(7u, guest.counter)
        assertEquals("Jamie's iPhone", guest.name)
    }

    @Test
    fun parseEncryptedPayloadReturnsOwnerModel() {
        val payload = ProvisioningQrParser.parse(
            "immogen://prov?slot=1&salt=00112233445566778899aabbccddeeff&ekey=ffeeddccbbaa998877665544332211000102030405060708&ctr=0&name="
        )

        val encrypted = assertIs<ProvisioningQrPayload.Encrypted>(payload)
        assertEquals(1, encrypted.slotId)
        assertEquals(16, encrypted.salt.size)
        assertEquals(24, encrypted.encryptedKey.size)
        assertEquals(0u, encrypted.counter)
        assertEquals("", encrypted.name)
    }

    @Test
    fun parseRejectsInvalidSlot() {
        assertFailsWith<ProvisioningQrParseException.InvalidField> {
            ProvisioningQrParser.parse(
                "immogen://prov?slot=4&key=00112233445566778899aabbccddeeff&ctr=0&name="
            )
        }
    }

    @Test
    fun parseRejectsBadHex() {
        assertFailsWith<ProvisioningQrParseException.InvalidField> {
            ProvisioningQrParser.parse(
                "immogen://prov?slot=1&salt=xyz&ekey=ffeeddccbbaa998877665544332211000102030405060708&ctr=0&name="
            )
        }
    }

    @Test
    fun parseRejectsMixedGuestAndEncryptedFields() {
        assertFailsWith<ProvisioningQrParseException.UnsupportedVariant> {
            ProvisioningQrParser.parse(
                "immogen://prov?slot=1&key=00112233445566778899aabbccddeeff&salt=00112233445566778899aabbccddeeff&ekey=ffeeddccbbaa998877665544332211000102030405060708&ctr=0&name="
            )
        }
    }

    @Test
    fun parseRejectsMissingCounter() {
        assertFailsWith<ProvisioningQrParseException.MissingField> {
            ProvisioningQrParser.parse(
                "immogen://prov?slot=1&key=00112233445566778899aabbccddeeff&name="
            )
        }
    }
}
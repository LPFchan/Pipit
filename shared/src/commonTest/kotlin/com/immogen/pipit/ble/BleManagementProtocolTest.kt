package com.immogen.pipit.ble

import com.immogen.core.ImmoCrypto
import com.immogen.core.PayloadBuilder
import com.immogen.core.hexStringToByteArray
import com.immogen.core.toHex
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BleManagementProtocolTest {
    @Test
    fun buildSlotsRequestUsesAsciiFrame() {
        val frame = BleManagementProtocol.buildSlotsRequest()

        assertEquals("SLOTS?", frame.commandName)
        assertFalse(frame.isBinary)
        assertEquals("SLOTS?", frame.payload.decodeToString())
    }

    @Test
    fun buildIdentifyRequestMatchesPayloadBuilder() {
        val key = hexStringToByteArray("000102030405060708090a0b0c0d0e0f")
        val payloadBuilder = PayloadBuilder()

        val frame = BleManagementProtocol.buildIdentifyRequest(
            slotId = 1,
            key = key,
            counter = 7u,
            payloadBuilder = payloadBuilder
        )

        val expected = payloadBuilder.buildPayload(
            slotId = 1,
            command = ImmoCrypto.Command.Identify,
            key = key,
            counter = 7u
        )

        assertEquals("IDENTIFY", frame.commandName)
        assertTrue(frame.isBinary)
        assertEquals(expected.toHex(), frame.payload.toHex())
    }

    @Test
    fun buildProvisionRequestEncodesNameAndKey() {
        val key = hexStringToByteArray("00112233445566778899aabbccddeeff")

        val frame = BleManagementProtocol.buildProvisionRequest(
            slotId = 2,
            key = key,
            counter = 12u,
            name = "Jamie's iPhone / owner"
        )

        assertEquals("PROV", frame.commandName)
        assertEquals(
            "PROV:2:00112233445566778899aabbccddeeff:12:Jamie%27s%20iPhone%20%2F%20owner",
            frame.payload.decodeToString()
        )
    }

    @Test
    fun buildRenameAndRecoverRequestsKeepTrailingNameField() {
        val key = hexStringToByteArray("ffeeddccbbaa99887766554433221100")

        val renameFrame = BleManagementProtocol.buildRenameRequest(slotId = 3, name = "")
        val recoverFrame = BleManagementProtocol.buildRecoverRequest(
            slotId = 1,
            key = key,
            counter = 0u,
            name = ""
        )

        assertEquals("RENAME:3:", renameFrame.payload.decodeToString())
        assertEquals("RECOVER:1:ffeeddccbbaa99887766554433221100:0:", recoverFrame.payload.decodeToString())
    }

    @Test
    fun parseSlotsResponseReturnsStructuredSlots() {
        val response = BleManagementProtocol.parseResponse(
            """
            {"status":"ok","slots":[
              {"id":0,"used":true,"counter":4821,"name":"Uguisu"},
              {"id":1,"used":false,"counter":0,"name":""}
            ]}
            """.trimIndent()
        )

        val slotsResponse = assertIs<BleManagementSlotsResponse>(response)
        assertEquals(2, slotsResponse.slots.size)
        assertEquals(0, slotsResponse.slots[0].id)
        assertTrue(slotsResponse.slots[0].used)
        assertEquals(4821u, slotsResponse.slots[0].counter)
        assertEquals("Uguisu", slotsResponse.slots[0].name)
        assertFalse(slotsResponse.slots[1].used)
    }

    @Test
    fun parseSuccessResponseReturnsGenericAckModel() {
        val response = BleManagementProtocol.parseResponse(
            "{" +
                "\"status\":\"ok\"," +
                "\"slot\":1," +
                "\"name\":\"Pixel 9\"," +
                "\"counter\":0" +
            "}"
        )

        val success = assertIs<BleManagementCommandSuccess>(response)
        assertEquals(1, success.slotId)
        assertEquals("Pixel 9", success.name)
        assertEquals(0u, success.counter)
        assertNull(success.message)
    }

    @Test
    fun parseErrorResponsesHandlesJsonAndLegacyFormat() {
        val jsonError = BleManagementProtocol.parseResponse(
            "{\"status\":\"error\",\"code\":\"FORBIDDEN\",\"msg\":\"guest slot\"}"
        )
        val legacyError = BleManagementProtocol.parseResponse("ERR:LOCKED:pairing required")

        val structuredError = assertIs<BleManagementError>(jsonError)
        assertEquals("FORBIDDEN", structuredError.code)
        assertEquals("guest slot", structuredError.message)

        val ackError = assertIs<BleManagementError>(legacyError)
        assertEquals("LOCKED", ackError.code)
        assertEquals("pairing required", ackError.message)
    }

    @Test
    fun parseAckResponseKeepsOptionalMessage() {
        val response = BleManagementProtocol.parseResponse("ACK:renamed")

        val success = assertIs<BleManagementCommandSuccess>(response)
        assertEquals("renamed", success.message)
    }
}
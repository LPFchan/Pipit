package com.immogen.core

import kotlinx.cinterop.*
import platform.CoreFoundation.*
import platform.Foundation.*
import platform.posix.memcpy
import platform.Security.*

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
actual class KeyStoreManager {

    private val service = "com.immogen.pipit.keys"

    actual fun saveKey(slotId: Int, key: ByteArray) {
        require(key.size == 16) { "Key must be exactly 16 bytes" }
        val account = "slot_$slotId"

        memScoped {
            val query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, null, null)!!
            val serviceRef = CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8)
            val accountRef = CFStringCreateWithCString(kCFAllocatorDefault, account, kCFStringEncodingUTF8)
            val dataRef = key.toCFData()

            CFDictionaryAddValue(query, kSecClass, kSecClassGenericPassword)
            if (serviceRef != null) CFDictionaryAddValue(query, kSecAttrService, serviceRef)
            if (accountRef != null) CFDictionaryAddValue(query, kSecAttrAccount, accountRef)
            if (dataRef != null) CFDictionaryAddValue(query, kSecValueData, dataRef)

            val status = SecItemAdd(query, null)
            if (status == errSecDuplicateItem && dataRef != null) {
                val attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, null, null)!!
                CFDictionaryAddValue(attrs, kSecValueData, dataRef)
                SecItemUpdate(query, attrs)
                CFRelease(attrs)
            }

            if (dataRef != null) CFRelease(dataRef)
            if (serviceRef != null) CFRelease(serviceRef)
            if (accountRef != null) CFRelease(accountRef)
            CFRelease(query)
        }
    }

    actual fun loadKey(slotId: Int): ByteArray? {
        val account = "slot_$slotId"

        return memScoped {
            val query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, null, null)!!
            val serviceRef = CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8)
            val accountRef = CFStringCreateWithCString(kCFAllocatorDefault, account, kCFStringEncodingUTF8)

            CFDictionaryAddValue(query, kSecClass, kSecClassGenericPassword)
            if (serviceRef != null) CFDictionaryAddValue(query, kSecAttrService, serviceRef)
            if (accountRef != null) CFDictionaryAddValue(query, kSecAttrAccount, accountRef)
            CFDictionaryAddValue(query, kSecReturnData, kCFBooleanTrue)
            CFDictionaryAddValue(query, kSecMatchLimit, kSecMatchLimitOne)

            val resultPtr = alloc<CFTypeRefVar>()
            val status = SecItemCopyMatching(query, resultPtr.ptr)

            if (serviceRef != null) CFRelease(serviceRef)
            if (accountRef != null) CFRelease(accountRef)
            CFRelease(query)

            if (status == errSecSuccess && resultPtr.value != null) {
                val resultRef = resultPtr.value!!
                @Suppress("UNCHECKED_CAST")
                val dataRef = resultRef as CFDataRef
                val bytes = dataRef.toByteArray()
                CFRelease(resultRef)
                bytes
            } else {
                null
            }
        }
    }

    actual fun deleteKey(slotId: Int) {
        val account = "slot_$slotId"

        memScoped {
            val query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, null, null)!!
            val serviceRef = CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8)
            val accountRef = CFStringCreateWithCString(kCFAllocatorDefault, account, kCFStringEncodingUTF8)

            CFDictionaryAddValue(query, kSecClass, kSecClassGenericPassword)
            if (serviceRef != null) CFDictionaryAddValue(query, kSecAttrService, serviceRef)
            if (accountRef != null) CFDictionaryAddValue(query, kSecAttrAccount, accountRef)

            SecItemDelete(query)

            if (serviceRef != null) CFRelease(serviceRef)
            if (accountRef != null) CFRelease(accountRef)
            CFRelease(query)
        }

        NSUserDefaults.standardUserDefaults.removeObjectForKey("counter_slot_$slotId")
    }

    actual fun saveCounter(slotId: Int, counter: UInt) {
        NSUserDefaults.standardUserDefaults.setObject(
            NSNumber(unsignedInt = counter),
            forKey = "counter_slot_$slotId"
        )
    }

    actual fun loadCounter(slotId: Int): UInt {
        val obj = NSUserDefaults.standardUserDefaults.objectForKey("counter_slot_$slotId")
        if (obj is NSNumber) return obj.unsignedIntValue
        return 0u
    }

    private fun ByteArray.toCFData(): CFDataRef? {
        return this.usePinned { pinned ->
            CFDataCreate(kCFAllocatorDefault, pinned.addressOf(0).reinterpret(), this.size.toLong())
        }
    }

    private fun CFDataRef.toByteArray(): ByteArray {
        val len = CFDataGetLength(this).toInt()
        val bytes = ByteArray(len)
        if (len > 0) {
            val src = CFDataGetBytePtr(this)
            bytes.usePinned { pinned ->
                memcpy(pinned.addressOf(0), src, len.toULong())
            }
        }
        return bytes
    }
}
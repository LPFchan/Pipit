package com.immogen.core

import platform.Foundation.NSData
import platform.Foundation.NSMutableDictionary
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.create
import platform.Foundation.dataWithBytes
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.SecItemUpdate
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrService
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.Security.kSecValueData
import platform.posix.memcpy
import platform.Foundation.NSUserDefaults
import platform.Foundation.NSNumber
import kotlinx.cinterop.allocArrayOf
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.readBytes
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.CoreFoundation.CFDictionaryRef
import platform.CoreFoundation.CFTypeRefVar
import kotlinx.cinterop.alloc
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value

actual class KeyStoreManager {
    
    private val service = "com.immogen.pipit.keys"
    
    actual fun saveKey(slotId: Int, key: ByteArray) {
        require(key.size == 16) { "Key must be exactly 16 bytes" }
        
        val account = "slot_$slotId"
        val data = key.toNSData()
        
        // First try to update
        val query = NSMutableDictionary().apply {
            setObject(kSecClassGenericPassword, forKey = kSecClass)
            setObject(service, forKey = kSecAttrService as NSString)
            setObject(account, forKey = kSecAttrAccount as NSString)
        }
        
        val attributesToUpdate = NSMutableDictionary().apply {
            setObject(data, forKey = kSecValueData as NSString)
        }
        
        val updateStatus = SecItemUpdate(query as CFDictionaryRef, attributesToUpdate as CFDictionaryRef)
        
        // If not found, add it
        if (updateStatus == platform.Security.errSecItemNotFound) {
            val addQuery = NSMutableDictionary().apply {
                setObject(kSecClassGenericPassword, forKey = kSecClass)
                setObject(service, forKey = kSecAttrService as NSString)
                setObject(account, forKey = kSecAttrAccount as NSString)
                setObject(data, forKey = kSecValueData as NSString)
            }
            SecItemAdd(addQuery as CFDictionaryRef, null)
        }
    }
    
    actual fun loadKey(slotId: Int): ByteArray? {
        val account = "slot_$slotId"
        
        val query = NSMutableDictionary().apply {
            setObject(kSecClassGenericPassword, forKey = kSecClass)
            setObject(service, forKey = kSecAttrService as NSString)
            setObject(account, forKey = kSecAttrAccount as NSString)
            setObject(kSecReturnData, forKey = kSecReturnData as NSString)
            setObject(kSecMatchLimitOne, forKey = kSecMatchLimit as NSString)
        }
        
        var result: CFTypeRefVar? = null
        memScoped {
            val resultPtr = alloc<CFTypeRefVar>()
            val status = SecItemCopyMatching(query as CFDictionaryRef, resultPtr.ptr)
            
            if (status == platform.Security.errSecSuccess) {
                result = resultPtr
            }
        }
        
        if (result?.value != null) {
            val data = result!!.value as NSData
            return data.toByteArray()
        }
        
        return null
    }
    
    actual fun deleteKey(slotId: Int) {
        val account = "slot_$slotId"
        
        val query = NSMutableDictionary().apply {
            setObject(kSecClassGenericPassword, forKey = kSecClass)
            setObject(service, forKey = kSecAttrService as NSString)
            setObject(account, forKey = kSecAttrAccount as NSString)
        }
        
        SecItemDelete(query as CFDictionaryRef)
        
        // Also delete counter
        NSUserDefaults.standardUserDefaults.removeObjectForKey("counter_slot_$slotId")
    }
    
    actual fun saveCounter(slotId: Int, counter: UInt) {
        // NSUserDefaults is sufficient for counter as it doesn't need encryption, just persistence
        NSUserDefaults.standardUserDefaults.setObject(
            NSNumber(unsignedInt = counter), 
            forKey = "counter_slot_$slotId"
        )
    }
    
    actual fun loadCounter(slotId: Int): UInt {
        val obj = NSUserDefaults.standardUserDefaults.objectForKey("counter_slot_$slotId")
        if (obj is NSNumber) {
            return obj.unsignedIntValue
        }
        return 0u
    }
    
    private fun ByteArray.toNSData(): NSData = memScoped {
        NSData.create(
            bytes = allocArrayOf(this@toNSData),
            length = this@toNSData.size.toULong()
        )
    }

    private fun NSData.toByteArray(): ByteArray {
        val bytes = ByteArray(length.toInt())
        if (length > 0u) {
            bytes.usePinned { pinned ->
                memcpy(pinned.addressOf(0), this.bytes, this.length)
            }
        }
        return bytes
    }
}
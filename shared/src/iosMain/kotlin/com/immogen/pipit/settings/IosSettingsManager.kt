package com.immogen.pipit.settings

import platform.Foundation.NSUserDefaults

class IosSettingsManager(private val userDefaults: NSUserDefaults = NSUserDefaults.standardUserDefaults) : SettingsManager {
    
    override fun getBoolean(key: String, defaultValue: Boolean): Boolean {
        if (userDefaults.objectForKey(key) == null) {
            return defaultValue
        }
        return userDefaults.boolForKey(key)
    }

    override fun setBoolean(key: String, value: Boolean) {
        userDefaults.setBool(value, forKey = key)
    }

    override fun getInt(key: String, defaultValue: Int): Int {
        if (userDefaults.objectForKey(key) == null) {
            return defaultValue
        }
        return userDefaults.integerForKey(key).toInt()
    }

    override fun setInt(key: String, value: Int) {
        userDefaults.setInteger(value.toLong(), forKey = key)
    }
}

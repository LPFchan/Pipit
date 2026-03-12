package com.immogen.pipit.settings

import android.content.Context
import android.content.SharedPreferences

class AndroidSettingsManager(context: Context) : SettingsManager {
    
    private val prefs: SharedPreferences = context.getSharedPreferences("pipit_settings", Context.MODE_PRIVATE)

    override fun getBoolean(key: String, defaultValue: Boolean): Boolean {
        return prefs.getBoolean(key, defaultValue)
    }

    override fun setBoolean(key: String, value: Boolean) {
        prefs.edit().putBoolean(key, value).apply()
    }

    override fun getInt(key: String, defaultValue: Int): Int {
        return prefs.getInt(key, defaultValue)
    }

    override fun setInt(key: String, value: Int) {
        prefs.edit().putInt(key, value).apply()
    }
}

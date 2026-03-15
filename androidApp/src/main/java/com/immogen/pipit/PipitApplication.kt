package com.immogen.pipit

import android.app.Application
import com.immogen.core.KeyStoreManager

class PipitApplication : Application() {
	override fun onCreate() {
		super.onCreate()
		KeyStoreManager.init(this)
	}
}

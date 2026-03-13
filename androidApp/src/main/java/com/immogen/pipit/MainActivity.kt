package com.immogen.pipit

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import com.immogen.pipit.ble.AndroidBleProximityService
import com.immogen.pipit.ble.BleService
import com.immogen.pipit.ui.PipitApp
import com.immogen.pipit.ui.theme.PipitTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private var bleService: BleService? by mutableStateOf(null)
    private val defaultBleState = com.immogen.pipit.ble.BleState()
    private val _bleStateFallback = MutableStateFlow(defaultBleState)
    private val bleStateFallback: StateFlow<com.immogen.pipit.ble.BleState> = _bleStateFallback.asStateFlow()

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as? AndroidBleProximityService.LocalBinder
            bleService = localBinder?.getBleService()
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            bleService = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bindService(
            Intent(this, AndroidBleProximityService::class.java),
            serviceConnection,
            Context.BIND_AUTO_CREATE
        )
        setContent {
            PipitTheme {
                val stateFlow = bleService?.state ?: bleStateFallback
                val bleState by stateFlow.collectAsState(initial = defaultBleState)
                Surface(modifier = Modifier.fillMaxSize()) {
                    PipitApp(
                        bleState = bleState,
                        bleService = bleService,
                        onRequestUnlock = { lifecycleScope.launch { bleService?.sendUnlockCommand() } },
                        onRequestLock = { lifecycleScope.launch { bleService?.sendLockCommand() } }
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        unbindService(serviceConnection)
        super.onDestroy()
    }
}

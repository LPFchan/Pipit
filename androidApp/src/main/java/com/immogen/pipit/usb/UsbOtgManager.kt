package com.immogen.pipit.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.InputStream
import java.io.OutputStream

// Note: Requires external libraries in actual implementation:
// implementation 'com.github.mjdev:libaums:0.8.0' // For UF2 Mass Storage
// implementation 'com.github.mik3y:usb-serial-for-android:3.4.6' // For CDC Serial

class UsbOtgManager(private val context: Context) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    
    private val _usbState = MutableStateFlow<UsbState>(UsbState.Disconnected)
    val usbState: StateFlow<UsbState> = _usbState.asStateFlow()
    
    private val scope = CoroutineScope(Dispatchers.IO)
    
    companion object {
        private const val ACTION_USB_PERMISSION = "com.immogen.pipit.USB_PERMISSION"
        private const val TAG = "UsbOtgManager"
        
        // Example VID/PIDs (Replace with actual ones for Guillemot/Uguisu)
        private const val NRF52840_VID = 0x239A // Adafruit default for example
        private const val GUILLEMOT_PID_MSC = 0x0029 // Example UF2 bootloader
        private const val GUILLEMOT_PID_CDC = 0x002A // Example Serial
        private const val UGUISU_PID_CDC = 0x002B // Example Uguisu Serial
    }

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: String) {
            when (intent) {
                ACTION_USB_PERMISSION -> {
                    synchronized(this) {
                        val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                        if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                            device?.let { connectDevice(it) }
                        } else {
                            _usbState.value = UsbState.Error("USB permission denied")
                        }
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    device?.let { requestPermission(it) }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    // Disconnect logic
                    _usbState.value = UsbState.Disconnected
                }
            }
        }
    }

    init {
        val filter = IntentFilter(ACTION_USB_PERMISSION).apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        context.registerReceiver(usbReceiver, filter)
        scanForDevices()
    }
    
    fun cleanup() {
        context.unregisterReceiver(usbReceiver)
        // Close serial ports, unmount mass storage, etc.
    }

    private fun scanForDevices() {
        usbManager.deviceList.values.forEach { device ->
            if (isSupportedDevice(device)) {
                requestPermission(device)
            }
        }
    }
    
    private fun isSupportedDevice(device: UsbDevice): Boolean {
        // Basic check for NRF52840 or specific VIDs
        return device.vendorId == NRF52840_VID 
    }

    private fun requestPermission(device: UsbDevice) {
        if (!usbManager.hasPermission(device)) {
            val permissionIntent = PendingIntent.getBroadcast(
                context, 0, Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE
            )
            usbManager.requestPermission(device, permissionIntent)
        } else {
            connectDevice(device)
        }
    }

    private fun connectDevice(device: UsbDevice) {
        _usbState.value = UsbState.Connecting
        val type = determineDeviceType(device)
        _usbState.value = UsbState.Connected(type)
        
        when (type) {
            DeviceType.GUILLEMOT_MASS_STORAGE -> setupMassStorage(device)
            DeviceType.GUILLEMOT_SERIAL, DeviceType.UGUISU_SERIAL -> setupSerial(device)
            DeviceType.UNKNOWN -> _usbState.value = UsbState.Error("Unsupported device connected")
        }
    }

    private fun determineDeviceType(device: UsbDevice): DeviceType {
        // Logic to inspect device interfaces/PIDs to determine what it is
        // For mass storage, we check if it exposes a mass storage interface
        // For serial, CDC ACM interface
        
        if (device.productId == GUILLEMOT_PID_MSC) return DeviceType.GUILLEMOT_MASS_STORAGE
        if (device.productId == GUILLEMOT_PID_CDC) return DeviceType.GUILLEMOT_SERIAL
        if (device.productId == UGUISU_PID_CDC) return DeviceType.UGUISU_SERIAL
        
        return DeviceType.UNKNOWN
    }
    
    // --- 2.2 USB Flashing (UF2 via libaums) ---
    private fun setupMassStorage(device: UsbDevice) {
        // In a real implementation, you would use libaums to mount the file system
        // e.g. val massStorageDevices = UsbMassStorageDevice.getMassStorageDevices(context)
        Log.d(TAG, "Mass storage connected")
    }

    /**
     * Flashes a UF2 file to the connected mass storage device.
     */
    fun flashFirmwareUf2(firmwareStream: InputStream, fileSize: Long) {
        if (_usbState.value !is UsbState.Connected || (_usbState.value as UsbState.Connected).deviceType != DeviceType.GUILLEMOT_MASS_STORAGE) {
            _usbState.value = UsbState.Error("Guillemot Mass Storage not connected")
            return
        }

        scope.launch {
            try {
                // Pseudo-code for libaums operations
                /*
                val massStorageDevice = UsbMassStorageDevice.getMassStorageDevices(context).firstOrNull()
                massStorageDevice?.init()
                val currentFs = massStorageDevice?.partitions?.firstOrNull()?.fileSystem
                val root = currentFs?.rootDirectory
                val flashFile = root?.createFile("flash.uf2")
                val os = UsbFileOutputStream(flashFile)
                */
                
                // Simulating copy process
                var copied: Long = 0
                val buffer = ByteArray(4096)
                var read: Int
                
                // In actual impl, read from firmwareStream and write to 'os'
                while (firmwareStream.read(buffer).also { read = it } != -1) {
                    // os.write(buffer, 0, read)
                    copied += read
                    val percent = ((copied.toFloat() / fileSize) * 100).toInt()
                    _usbState.value = UsbState.Flashing(percent)
                }
                
                // os.flush()
                // os.close()
                firmwareStream.close()
                
                _usbState.value = UsbState.FlashingSuccess
                
            } catch (e: Exception) {
                _usbState.value = UsbState.Error("Flashing failed: ${e.message}")
            }
        }
    }
    
    // --- CDC Serial (usb-serial-for-android) ---
    private fun setupSerial(device: UsbDevice) {
        // In a real implementation:
        // val driver = UsbSerialProber.getDefaultProber().probeDevice(device)
        // port = driver.ports[0]
        // port.open(usbManager.openDevice(driver.device))
        // port.setParameters(115200, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
        Log.d(TAG, "Serial connected")
    }
    
    private suspend fun writeSerialString(command: String) = withContext(Dispatchers.IO) {
        // port.write(command.toByteArray(), 1000)
    }

    // --- 2.3 USB Flashing Uguisu (CDC DFU) ---
    fun flashUguisuFirmware(firmwareStream: InputStream) {
        // Implement serial DFU protocol (often using SLIP framing or specific commands to send binary)
    }
    
    /**
     * Provisions Uguisu Slot 0 key via Serial
     */
    fun provisionUguisuKey(hexKey: String) {
         if (_usbState.value !is UsbState.Connected || (_usbState.value as UsbState.Connected).deviceType != DeviceType.UGUISU_SERIAL) {
            _usbState.value = UsbState.Error("Uguisu Serial not connected")
            return
        }
        
        scope.launch {
            try {
                // Command: PROV:0:<key>:0:Uguisu
                val command = "PROV:0:$hexKey:0:Uguisu\r\n"
                writeSerialString(command)
                // Read response to verify success
                _usbState.value = UsbState.ProvisioningSuccess
            } catch (e: Exception) {
                _usbState.value = UsbState.Error("Provisioning failed: ${e.message}")
            }
        }
    }

    // --- 2.4 Change PIN via Serial (Guillemot) ---
    /**
     * Changes the management PIN of Guillemot via physical connection
     */
    fun changeGuillemotPin(newPin: String) {
         if (_usbState.value !is UsbState.Connected || (_usbState.value as UsbState.Connected).deviceType != DeviceType.GUILLEMOT_SERIAL) {
            _usbState.value = UsbState.Error("Guillemot Serial not connected")
            return
        }
        
        if (newPin.length != 6 || !newPin.all { it.isDigit() }) {
             _usbState.value = UsbState.Error("PIN must be 6 digits")
             return
        }

        scope.launch {
            try {
                // Send SETPIN:<6digits>
                val command = "SETPIN:$newPin\r\n"
                writeSerialString(command)
                // Read response to verify success
                _usbState.value = UsbState.PinChangeSuccess
            } catch (e: Exception) {
                _usbState.value = UsbState.Error("PIN Change failed: ${e.message}")
            }
        }
    }
}

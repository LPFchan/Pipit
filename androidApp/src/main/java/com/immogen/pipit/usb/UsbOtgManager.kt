package com.immogen.pipit.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import me.jahnen.libaums.core.UsbMassStorageDevice
import me.jahnen.libaums.core.fs.FileSystem
import me.jahnen.libaums.core.fs.UsbFile
import me.jahnen.libaums.core.fs.UsbFileStreamFactory
import org.json.JSONException
import org.json.JSONObject
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets

class UsbOtgManager(private val context: Context) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

    private val _usbState = MutableStateFlow<UsbState>(UsbState.Disconnected)
    val usbState: StateFlow<UsbState> = _usbState.asStateFlow()

    private val managerJob = SupervisorJob()
    private val scope = CoroutineScope(managerJob + Dispatchers.IO)
    private val operationMutex = Mutex()

    private var receiverRegistered = false
    private var activeUsbDevice: UsbDevice? = null
    private var activeDeviceType: DeviceType? = null

    private var massStorageDevice: UsbMassStorageDevice? = null
    private var massStorageFileSystem: FileSystem? = null
    private var massStorageRoot: UsbFile? = null

    private var serialPort: UsbSerialPort? = null
    private var serialConnection: UsbDeviceConnection? = null
    private val serialReadBuffer = StringBuilder()

    companion object {
        private const val ACTION_USB_PERMISSION = "com.immogen.pipit.USB_PERMISSION"
        private const val TAG = "UsbOtgManager"

        private const val UF2_FILENAME = "FIRMWARE.UF2"
        private const val SERIAL_BAUD_RATE = 115200
        private const val SERIAL_WRITE_TIMEOUT_MS = 2_000
        private const val SERIAL_READ_SLICE_MS = 250
        private const val SERIAL_RESPONSE_TIMEOUT_MS = 12_000
        private const val SERIAL_BOOT_TIMEOUT_MS = 10_000

        private const val NRF52840_VID = 0x239A
        private const val GUILLEMOT_PID_MSC = 0x0029
        private const val GUILLEMOT_PID_CDC = 0x002A
        private const val UGUISU_PID_CDC = 0x002B
    }

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return

            when (action) {
                ACTION_USB_PERMISSION -> {
                    synchronized(this) {
                        val device = intent.parcelableExtraCompat<UsbDevice>(UsbManager.EXTRA_DEVICE)
                        if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                            device?.let { connectDevice(it) }
                        } else {
                            _usbState.value = UsbState.Error("USB permission denied")
                        }
                    }
                }

                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val device = intent.parcelableExtraCompat<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    device?.let { requestPermission(it) }
                }

                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device = intent.parcelableExtraCompat<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    if (device != null && device.deviceId == activeUsbDevice?.deviceId) {
                        scope.launch {
                            operationMutex.withLock {
                                closeActiveConnectionLocked(updateState = true)
                            }
                        }
                    }
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
        receiverRegistered = true
        scanForDevices()
    }

    fun cleanup() {
        closeActiveConnectionLocked(updateState = false)
        if (receiverRegistered) {
            context.unregisterReceiver(usbReceiver)
            receiverRegistered = false
        }
        managerJob.cancel()
    }

    private inline fun <reified T : android.os.Parcelable> Intent.parcelableExtraCompat(name: String): T? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(name, T::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(name)
        }
    }

    private fun scanForDevices() {
        usbManager.deviceList.values.forEach { device ->
            if (isSupportedDevice(device)) {
                requestPermission(device)
            }
        }
    }

    private fun isSupportedDevice(device: UsbDevice): Boolean {
        return determineDeviceType(device) != DeviceType.UNKNOWN
    }

    private fun requestPermission(device: UsbDevice) {
        if (!usbManager.hasPermission(device)) {
            val permissionIntent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(ACTION_USB_PERMISSION),
                PendingIntent.FLAG_IMMUTABLE,
            )
            usbManager.requestPermission(device, permissionIntent)
        } else {
            connectDevice(device)
        }
    }

    private fun connectDevice(device: UsbDevice) {
        _usbState.value = UsbState.Connecting
        scope.launch {
            operationMutex.withLock {
                try {
                    closeActiveConnectionLocked(updateState = false)

                    val type = determineDeviceType(device)
                    if (type == DeviceType.UNKNOWN) {
                        _usbState.value = UsbState.Error("Unsupported device connected")
                        return@withLock
                    }

                    when (type) {
                        DeviceType.GUILLEMOT_MASS_STORAGE -> setupMassStorage(device)
                        DeviceType.GUILLEMOT_SERIAL, DeviceType.UGUISU_SERIAL -> setupSerial(device)
                        DeviceType.UNKNOWN -> Unit
                    }

                    activeUsbDevice = device
                    activeDeviceType = type
                    _usbState.value = UsbState.Connected(type)
                } catch (e: Exception) {
                    closeActiveConnectionLocked(updateState = false)
                    Log.e(TAG, "Failed to connect USB device", e)
                    _usbState.value = UsbState.Error("USB connection failed: ${e.message ?: "unknown error"}")
                }
            }
        }
    }

    private fun determineDeviceType(device: UsbDevice): DeviceType {
        if (device.productId == GUILLEMOT_PID_MSC) return DeviceType.GUILLEMOT_MASS_STORAGE
        if (device.productId == GUILLEMOT_PID_CDC) return DeviceType.GUILLEMOT_SERIAL
        if (device.productId == UGUISU_PID_CDC) return DeviceType.UGUISU_SERIAL

        if (hasMassStorageInterface(device)) {
            return DeviceType.GUILLEMOT_MASS_STORAGE
        }

        if (hasSerialInterface(device)) {
            val label = listOfNotNull(device.productName, device.manufacturerName)
                .joinToString(" ")
                .lowercase()

            return when {
                "uguisu" in label -> DeviceType.UGUISU_SERIAL
                "guillemot" in label -> DeviceType.GUILLEMOT_SERIAL
                device.vendorId == NRF52840_VID -> DeviceType.GUILLEMOT_SERIAL
                else -> DeviceType.UNKNOWN
            }
        }

        return DeviceType.UNKNOWN
    }

    private fun hasMassStorageInterface(device: UsbDevice): Boolean {
        for (index in 0 until device.interfaceCount) {
            if (device.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_MASS_STORAGE) {
                return true
            }
        }
        return false
    }

    private fun hasSerialInterface(device: UsbDevice): Boolean {
        for (index in 0 until device.interfaceCount) {
            val usbInterface = device.getInterface(index)
            if (usbInterface.interfaceClass == UsbConstants.USB_CLASS_COMM ||
                usbInterface.interfaceClass == UsbConstants.USB_CLASS_CDC_DATA
            ) {
                return true
            }
        }
        return false
    }

    private fun setupMassStorage(device: UsbDevice) {
        val storageDevice = UsbMassStorageDevice.getMassStorageDevices(context)
            .firstOrNull { it.usbDevice.deviceId == device.deviceId }
            ?: throw IllegalStateException("Mass storage device not found")

        storageDevice.init()
        val partition = storageDevice.partitions.firstOrNull()
            ?: throw IllegalStateException("Mass storage device has no partitions")

        massStorageDevice = storageDevice
        massStorageFileSystem = partition.fileSystem
        massStorageRoot = partition.fileSystem.rootDirectory

        Log.d(
            TAG,
            "Mass storage ready: volume=${partition.volumeLabel}, chunkSize=${partition.fileSystem.chunkSize}",
        )
    }

    fun flashFirmwareUf2(firmwareStream: InputStream, fileSize: Long) {
        if (!isConnectedTo(DeviceType.GUILLEMOT_MASS_STORAGE)) {
            _usbState.value = UsbState.Error("Guillemot Mass Storage not connected")
            return
        }

        scope.launch {
            operationMutex.withLock {
                var outputStream: OutputStream? = null
                try {
                    val fileSystem = massStorageFileSystem
                        ?: throw IllegalStateException("Mass storage filesystem is unavailable")
                    val root = massStorageRoot
                        ?: throw IllegalStateException("Mass storage root directory is unavailable")

                    val existing = root.search(UF2_FILENAME)
                    existing?.delete()

                    val flashFile = root.createFile(UF2_FILENAME)
                    if (fileSize > 0) {
                        flashFile.length = fileSize
                    }

                    outputStream = UsbFileStreamFactory.createBufferedOutputStream(flashFile, fileSystem)

                    var copiedBytes = 0L
                    var lastPercent = -1
                    val buffer = ByteArray(fileSystem.chunkSize.coerceAtLeast(4 * 1024))

                    while (true) {
                        val read = firmwareStream.read(buffer)
                        if (read < 0) break
                        outputStream.write(buffer, 0, read)
                        copiedBytes += read

                        if (fileSize > 0) {
                            val percent = ((copiedBytes * 100) / fileSize).toInt().coerceIn(0, 100)
                            if (percent != lastPercent) {
                                lastPercent = percent
                                _usbState.value = UsbState.Flashing(percent)
                            }
                        }
                    }

                    outputStream.flush()
                    outputStream.close()
                    firmwareStream.close()

                    if (fileSize > 0 && copiedBytes != fileSize) {
                        throw IllegalStateException(
                            "Firmware copy incomplete: expected $fileSize bytes, wrote $copiedBytes bytes",
                        )
                    }

                    _usbState.value = UsbState.FlashingSuccess
                } catch (e: Exception) {
                    Log.e(TAG, "UF2 flashing failed", e)
                    _usbState.value = UsbState.Error("Flashing failed: ${e.message ?: "unknown error"}")
                } finally {
                    try {
                        outputStream?.close()
                    } catch (_: Exception) {
                    }
                    try {
                        firmwareStream.close()
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    private fun setupSerial(device: UsbDevice) {
        val prober = UsbSerialProber.getDefaultProber()
        val driver = prober.probeDevice(device)
            ?: prober.findAllDrivers(usbManager).firstOrNull { it.device.deviceId == device.deviceId }
            ?: throw IllegalStateException("Serial driver not found")

        val connection = usbManager.openDevice(driver.device)
            ?: throw IllegalStateException("Unable to open USB serial device")

        try {
            val port = driver.ports.firstOrNull()
                ?: throw IllegalStateException("USB serial port not found")
            port.open(connection)
            try {
                port.setDTR(true)
                port.setRTS(true)
            } catch (_: UnsupportedOperationException) {
            }
            port.setParameters(
                SERIAL_BAUD_RATE,
                UsbSerialPort.DATABITS_8,
                UsbSerialPort.STOPBITS_1,
                UsbSerialPort.PARITY_NONE,
            )
            try {
                port.purgeHwBuffers(true, true)
            } catch (_: UnsupportedOperationException) {
            }

            serialPort = port
            serialConnection = connection
            serialReadBuffer.clear()
            Log.d(TAG, "Serial connected on port ${port.portNumber}")
        } catch (e: Exception) {
            try {
                connection.close()
            } catch (_: Exception) {
            }
            throw e
        }
    }

    private suspend fun writeSerialString(command: String) = withContext(Dispatchers.IO) {
        val port = serialPort ?: throw IllegalStateException("Serial port not connected")
        port.write(command.toByteArray(StandardCharsets.UTF_8), SERIAL_WRITE_TIMEOUT_MS)
    }

    fun flashUguisuFirmware(firmwareStream: InputStream) {
        try {
            firmwareStream.close()
        } catch (_: Exception) {
        }
        _usbState.value = UsbState.Error("Uguisu USB firmware flashing is not implemented in this module yet")
    }

    fun provisionUguisuKey(hexKey: String) {
        if (!isConnectedTo(DeviceType.UGUISU_SERIAL)) {
            _usbState.value = UsbState.Error("Uguisu Serial not connected")
            return
        }

        if (!hexKey.matches(Regex("^[0-9A-Fa-f]{32}$"))) {
            _usbState.value = UsbState.Error("Provisioning key must be exactly 32 hex characters")
            return
        }

        scope.launch {
            operationMutex.withLock {
                try {
                    executeSerialCommandLocked(
                        command = "PROV:0:${hexKey.uppercase()}:0:Uguisu",
                        responseTimeoutMs = SERIAL_RESPONSE_TIMEOUT_MS,
                        successPredicate = { line -> line == "ACK:PROV_SUCCESS" },
                        bootPrefix = "BOOTED: Uguisu",
                    )
                    _usbState.value = UsbState.ProvisioningSuccess
                } catch (e: Exception) {
                    Log.e(TAG, "Uguisu provisioning failed", e)
                    _usbState.value = UsbState.Error("Provisioning failed: ${e.message ?: "unknown error"}")
                }
            }
        }
    }

    fun changeGuillemotPin(newPin: String) {
        if (!isConnectedTo(DeviceType.GUILLEMOT_SERIAL)) {
            _usbState.value = UsbState.Error("Guillemot Serial not connected")
            return
        }

        if (newPin.length != 6 || !newPin.all { it.isDigit() }) {
            _usbState.value = UsbState.Error("PIN must be 6 digits")
            return
        }

        scope.launch {
            operationMutex.withLock {
                try {
                    executeSerialCommandLocked(
                        command = "SETPIN:$newPin",
                        responseTimeoutMs = SERIAL_RESPONSE_TIMEOUT_MS,
                        successPredicate = { line -> isJsonOkResponse(line) },
                    )
                    _usbState.value = UsbState.PinChangeSuccess
                } catch (e: Exception) {
                    Log.e(TAG, "PIN change failed", e)
                    _usbState.value = UsbState.Error("PIN Change failed: ${e.message ?: "unknown error"}")
                }
            }
        }
    }

    private fun isConnectedTo(type: DeviceType): Boolean {
        return activeDeviceType == type
    }

    private suspend fun executeSerialCommandLocked(
        command: String,
        responseTimeoutMs: Int,
        successPredicate: (String) -> Boolean,
        bootPrefix: String? = null,
    ): String {
        drainSerialInputLocked()
        writeSerialString("$command\n")

        val response = waitForSerialLineLocked(responseTimeoutMs) { line ->
            when {
                line.startsWith("ERR:") -> throw IllegalStateException(line)
                successPredicate(line) -> true
                else -> false
            }
        }

        if (bootPrefix != null) {
            waitForSerialLineLocked(SERIAL_BOOT_TIMEOUT_MS) { line ->
                when {
                    line.startsWith("ERR:") -> throw IllegalStateException(line)
                    line.startsWith(bootPrefix) -> true
                    else -> false
                }
            }
        }

        return response
    }

    private fun isJsonOkResponse(line: String): Boolean {
        if (!line.startsWith("{")) return false

        try {
            val json = JSONObject(line)
            if (json.optString("status") == "ok") {
                return true
            }

            val reason = json.optString("reason")
            throw IllegalStateException(if (reason.isNotBlank()) reason else "Command rejected by device")
        } catch (e: JSONException) {
            throw IllegalStateException("Malformed JSON response: $line", e)
        }
    }

    private suspend fun waitForSerialLineLocked(
        timeoutMs: Int,
        linePredicate: (String) -> Boolean,
    ): String {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs

        while (SystemClock.elapsedRealtime() < deadline) {
            extractBufferedSerialLineLocked()?.let { line ->
                if (linePredicate(line)) {
                    return line
                }
            }

            val remaining = (deadline - SystemClock.elapsedRealtime()).toInt().coerceAtLeast(1)
            readSerialChunkLocked(remaining.coerceAtMost(SERIAL_READ_SLICE_MS))
        }

        extractBufferedSerialLineLocked()?.let { line ->
            if (linePredicate(line)) {
                return line
            }
        }

        throw IllegalStateException("Timed out waiting for device response")
    }

    private fun drainSerialInputLocked() {
        serialReadBuffer.setLength(0)
        val port = serialPort ?: return
        val scratch = ByteArray(256)

        repeat(4) {
            val read = try {
                port.read(scratch, 50)
            } catch (_: Exception) {
                0
            }
            if (read <= 0) {
                return
            }
        }

        serialReadBuffer.setLength(0)
    }

    private fun extractBufferedSerialLineLocked(): String? {
        val newlineIndex = serialReadBuffer.indexOf("\n")
        if (newlineIndex < 0) return null

        val line = serialReadBuffer.substring(0, newlineIndex).trim()
        serialReadBuffer.delete(0, newlineIndex + 1)
        return line
    }

    private fun readSerialChunkLocked(timeoutMs: Int) {
        val port = serialPort ?: throw IllegalStateException("Serial port not connected")
        val buffer = ByteArray(256)
        val read = port.read(buffer, timeoutMs)
        if (read > 0) {
            serialReadBuffer.append(String(buffer, 0, read, StandardCharsets.UTF_8))
        }
    }

    private fun closeActiveConnectionLocked(updateState: Boolean) {
        try {
            serialPort?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to close serial port", e)
        }
        serialPort = null

        try {
            serialConnection?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to close serial connection", e)
        }
        serialConnection = null
        serialReadBuffer.setLength(0)

        try {
            massStorageDevice?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to close mass storage device", e)
        }
        massStorageDevice = null
        massStorageFileSystem = null
        massStorageRoot = null

        activeUsbDevice = null
        activeDeviceType = null

        if (updateState) {
            _usbState.value = UsbState.Disconnected
        }
    }
}

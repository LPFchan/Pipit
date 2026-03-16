package com.immogen.pipit.ui

import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.immogen.core.ImmoCrypto
import com.immogen.core.KeyStoreManager
import com.immogen.core.toHex
import com.immogen.pipit.BuildConfig
import com.immogen.pipit.ble.BleManagementConnectMode
import com.immogen.pipit.ble.BleManagementSessionConnectionState
import com.immogen.pipit.ble.BleManagementSessionState
import com.immogen.pipit.ble.BleManagementSlot
import com.immogen.pipit.ble.BleService
import com.immogen.pipit.settings.AndroidSettingsManager
import com.immogen.pipit.settings.AppSettings
import com.immogen.pipit.usb.DeviceType
import com.immogen.pipit.usb.UsbOtgManager
import com.immogen.pipit.usb.UsbState
import java.security.SecureRandom
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private const val UnlockRssiMin = -95
private const val UnlockRssiMax = -35
private const val LockRssiMin = -105
private const val HysteresisGapDbm = 10

private data class RenameTarget(
    val slotId: Int,
    val currentName: String,
)

private data class QrDisplayState(
    val title: String,
    val body: String,
    val payload: String,
    val primaryButtonText: String,
    val deleteLocalKeyOnConfirm: Boolean,
)

private enum class PendingFlashTarget {
    GUILLEMOT
}

@Composable
fun SettingsScreen(
    bleService: BleService?,
    onClose: () -> Unit,
    onLocalKeyDeleted: () -> Unit,
) {
    val context = LocalContext.current
    val settings = remember(context) { AppSettings(AndroidSettingsManager(context)) }
    val keyStoreManager = remember { KeyStoreManager() }
    val usbManager = remember(context.applicationContext) { UsbOtgManager(context.applicationContext) }
    val usbState by usbManager.usbState.collectAsState(initial = UsbState.Disconnected)
    val transport = bleService?.managementTransport
    val emptySessionStateFlow = remember { MutableStateFlow(BleManagementSessionState()) }
    val sessionStateFlow = transport?.sessionState ?: emptySessionStateFlow
    val sessionState by sessionStateFlow.collectAsState(initial = BleManagementSessionState())
    val coroutineScope = rememberCoroutineScope()

    var refreshToken by remember { mutableIntStateOf(0) }
    var isLoadingSlots by remember { mutableStateOf(false) }
    var slotError by remember { mutableStateOf<String?>(null) }
    var loadedSlots by remember { mutableStateOf<List<BleManagementSlot>>(emptyList()) }
    var hasLoadedSlots by remember { mutableStateOf(false) }

    var isProximityEnabled by remember { mutableStateOf(settings.isProximityEnabled) }
    var unlockRssi by remember { mutableIntStateOf(settings.unlockRssi) }
    var lockRssi by remember { mutableIntStateOf(settings.lockRssi) }

    var actionBusy by remember { mutableStateOf(false) }
    var actionMessage by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var renameTarget by remember { mutableStateOf<RenameTarget?>(null) }
    var renameDraft by remember { mutableStateOf("") }
    var revokeTarget by remember { mutableStateOf<BleManagementSlot?>(null) }
    var provisionGuestSlotId by remember { mutableStateOf<Int?>(null) }
    var replaceGuestTarget by remember { mutableStateOf<BleManagementSlot?>(null) }
    var confirmTransfer by remember { mutableStateOf(false) }
    var ownerTransferPin by remember { mutableStateOf("") }
    var showOwnerTransferPin by remember { mutableStateOf(false) }
    var qrDisplayState by remember { mutableStateOf<QrDisplayState?>(null) }
    var confirmDeleteLocalKey by remember { mutableStateOf(false) }
    var changePinDraft by remember { mutableStateOf("") }
    var confirmPinDraft by remember { mutableStateOf("") }
    var showChangePinDialog by remember { mutableStateOf(false) }
    var pendingFlashTarget by remember { mutableStateOf<PendingFlashTarget?>(null) }

    val localSlotId = remember(refreshToken) { determineLocalPhoneSlotId(keyStoreManager) }
    val displaySlots = remember(loadedSlots) { buildDisplaySlots(loadedSlots) }
    val isOwner = localSlotId == 1
    val selfSlot = remember(displaySlots, localSlotId) {
        displaySlots.firstOrNull { it.id == localSlotId }
    }

    suspend fun ensureConnected() {
        val currentTransport = transport ?: error("Settings transport is unavailable.")
        currentTransport.connect(BleManagementConnectMode.STANDARD)
    }

    suspend fun refreshSlots() {
        val currentTransport = transport ?: error("Settings transport is unavailable.")
        ensureConnected()
        loadedSlots = currentTransport.requestSlots().slots.sortedBy { it.id }
        hasLoadedSlots = true
    }

    suspend fun executeOwnerWrite(statusText: String, block: suspend () -> Unit) {
        val currentTransport = transport ?: error("Settings transport is unavailable.")
        actionBusy = true
        actionError = null
        actionMessage = statusText
        try {
            ensureConnected()
            currentTransport.identify(1)
            block()
            refreshSlots()
            actionMessage = "$statusText complete."
        } catch (error: Throwable) {
            actionError = error.message ?: "Management action failed."
        } finally {
            actionBusy = false
        }
    }

    suspend fun buildMigrationQrPayload(pin: String?): QrDisplayState {
        val slotId = localSlotId ?: error("No local key is stored on this device.")
        val key = keyStoreManager.loadKey(slotId) ?: error("No local key is stored for slot $slotId.")
        val counter = keyStoreManager.loadCounter(slotId)
        val slotName = (selfSlot?.name?.takeIf { it.isNotBlank() } ?: defaultSlotName(slotId)).take(24)
        val payload = if (slotId == 1) {
            val finalPin = pin?.takeIf { it.length == 6 } ?: error("Owner transfer requires your 6-digit PIN.")
            if (!ImmoCrypto.isInitialized()) {
                ImmoCrypto.initialize()
            }
            val salt = ByteArray(ImmoCrypto.QR_SALT_LEN).also(SecureRandom()::nextBytes)
            val derivedKey = ImmoCrypto.deriveKey(finalPin, salt)
            val encryptedKey = ImmoCrypto.encryptProvisionedKey(derivedKey, salt, key)
            buildEncryptedProvisioningUri(slotId, salt, encryptedKey, counter, slotName)
        } else {
            buildPlainProvisioningUri(slotId, key, counter, slotName)
        }

        val body = if (slotId == 1) {
            "Scan this on your new phone. The new phone will ask for your management PIN before importing the owner key."
        } else {
            "Scan this on your new phone. Guest transfers stay plaintext and do not require a PIN."
        }

        return QrDisplayState(
            title = "Transfer to New Phone",
            body = body,
            payload = payload,
            primaryButtonText = "Done — I've Scanned",
            deleteLocalKeyOnConfirm = true,
        )
    }

    suspend fun awaitUsbTerminalState(success: (UsbState) -> Boolean): UsbState {
        return usbManager.usbState
            .drop(1)
            .first { state -> success(state) || state is UsbState.Error }
    }

    suspend fun provisionGuestSlot(slotId: Int, replaceExisting: Boolean) {
        val key = ByteArray(16).also(SecureRandom()::nextBytes)
        val slotName = guestSlotDefaultName(slotId)
        executeOwnerWrite(
            statusText = if (replaceExisting) "Replacing guest slot $slotId" else "Provisioning guest slot $slotId"
        ) {
            if (replaceExisting) {
                transport?.revoke(slotId)
            }
            transport?.provision(slotId, key, 0u, slotName)
            qrDisplayState = QrDisplayState(
                title = if (replaceExisting) "Replacement Key Ready" else "Guest Key Ready",
                body = "Scan this on the guest phone. No PIN is required for guest provisioning.",
                payload = buildPlainProvisioningUri(slotId, key, 0u, slotName),
                primaryButtonText = "Done",
                deleteLocalKeyOnConfirm = false,
            )
        }
    }

    suspend fun replaceUguisu() {
        val key = ByteArray(16).also(SecureRandom()::nextBytes)
        actionBusy = true
        actionError = null
        actionMessage = "Provisioning the new Uguisu key over USB..."
        try {
            val usbConnected = usbState as? UsbState.Connected
                ?: error("Connect the new Uguisu over USB-C OTG first.")
            if (usbConnected.deviceType != DeviceType.UGUISU_SERIAL) {
                error("Connect an Uguisu serial device before replacing Slot 0.")
            }

            usbManager.provisionUguisuKey(key.toHex())
            when (val result = awaitUsbTerminalState { it is UsbState.ProvisioningSuccess }) {
                is UsbState.Error -> error(result.message)
                else -> Unit
            }

            executeOwnerWrite("Syncing the new Uguisu key to Guillemot") {
                transport?.provision(0, key, 0u, "Uguisu")
            }
        } catch (error: Throwable) {
            actionError = error.message ?: "Uguisu replacement failed."
            actionBusy = false
        }
    }

    suspend fun changeManagementPin() {
        actionBusy = true
        actionError = null
        actionMessage = "Changing the Guillemot management PIN over USB..."
        try {
            val usbConnected = usbState as? UsbState.Connected
                ?: error("Connect Guillemot over USB-C OTG first.")
            if (usbConnected.deviceType != DeviceType.GUILLEMOT_SERIAL) {
                error("PIN changes require a Guillemot serial connection.")
            }
            usbManager.changeGuillemotPin(changePinDraft)
            when (val result = awaitUsbTerminalState { it is UsbState.PinChangeSuccess }) {
                is UsbState.Error -> error(result.message)
                else -> actionMessage = "PIN changed. Existing BLE bonds stay valid; new management pairings use the new PIN."
            }
        } catch (error: Throwable) {
            actionError = error.message ?: "PIN change failed."
        } finally {
            actionBusy = false
        }
    }

    suspend fun flashGuillemotFirmware(uri: Uri) {
        actionBusy = true
        actionError = null
        actionMessage = "Flashing Guillemot firmware over USB..."
        try {
            val usbConnected = usbState as? UsbState.Connected
                ?: error("Connect Guillemot in UF2 mass-storage mode first.")
            if (usbConnected.deviceType != DeviceType.GUILLEMOT_MASS_STORAGE) {
                error("Firmware flashing requires Guillemot mass-storage mode.")
            }

            val descriptor = context.contentResolver.openAssetFileDescriptor(uri, "r")
                ?: error("Unable to read the selected UF2 file.")
            val fileSize = descriptor.length.coerceAtLeast(0L)
            descriptor.close()

            val stream = context.contentResolver.openInputStream(uri)
                ?: error("Unable to open the selected UF2 file.")
            usbManager.flashFirmwareUf2(stream, fileSize)
            when (val result = awaitUsbTerminalState { it is UsbState.FlashingSuccess }) {
                is UsbState.Error -> error(result.message)
                else -> actionMessage = "Firmware flash complete."
            }
        } catch (error: Throwable) {
            actionError = error.message ?: "Firmware flash failed."
        } finally {
            actionBusy = false
        }
    }

    val uf2Picker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri ->
        val selectedTarget = pendingFlashTarget
        pendingFlashTarget = null
        if (uri == null || selectedTarget == null) {
            return@rememberLauncherForActivityResult
        }
        coroutineScope.launch {
            when (selectedTarget) {
                PendingFlashTarget.GUILLEMOT -> flashGuillemotFirmware(uri)
            }
        }
    }

    LaunchedEffect(transport, refreshToken) {
        slotError = null
        hasLoadedSlots = false
        loadedSlots = emptyList()

        if (transport == null) {
            isLoadingSlots = false
            slotError = "Settings transport is unavailable."
            return@LaunchedEffect
        }

        isLoadingSlots = true
        try {
            refreshSlots()
        } catch (error: Throwable) {
            slotError = error.message ?: "Unable to load vehicle slots."
            runCatching { transport.disconnect() }
        } finally {
            isLoadingSlots = false
        }
    }

    DisposableEffect(transport, usbManager) {
        onDispose {
            coroutineScope.launch {
                runCatching { transport?.disconnect() }
            }
            usbManager.cleanup()
        }
    }

    fun updateProximityEnabled(enabled: Boolean) {
        isProximityEnabled = enabled
        settings.isProximityEnabled = enabled
    }

    fun updateUnlockRssi(nextValue: Int) {
        val clampedUnlock = nextValue.coerceIn(UnlockRssiMin, UnlockRssiMax)
        val adjustedLock = lockRssi.coerceAtMost(clampedUnlock - HysteresisGapDbm)
        unlockRssi = clampedUnlock
        lockRssi = adjustedLock.coerceAtLeast(LockRssiMin)
        settings.unlockRssi = unlockRssi
        settings.lockRssi = lockRssi
    }

    fun updateLockRssi(nextValue: Int) {
        val maxLockRssi = unlockRssi - HysteresisGapDbm
        val clampedLock = nextValue.coerceIn(LockRssiMin, maxLockRssi)
        lockRssi = clampedLock
        settings.lockRssi = lockRssi
    }

    qrDisplayState?.let { qrState ->
        QrDisplayDialog(
            state = qrState,
            onDismiss = { qrDisplayState = null },
            onConfirm = {
                qrDisplayState = null
                if (qrState.deleteLocalKeyOnConfirm) {
                    confirmDeleteLocalKey = true
                }
            },
        )
    }

    if (renameTarget != null) {
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        val finalTarget = renameTarget ?: return@TextButton
                        renameTarget = null
                        coroutineScope.launch {
                            executeOwnerWrite("Renaming slot ${finalTarget.slotId}") {
                                transport?.rename(finalTarget.slotId, renameDraft.take(24))
                            }
                        }
                    },
                    enabled = renameDraft.isNotBlank() && renameDraft.length <= 24,
                ) {
                    Text("Rename")
                }
            },
            dismissButton = {
                TextButton(onClick = { renameTarget = null }) {
                    Text("Cancel")
                }
            },
            title = { Text("Rename Guest Slot") },
            text = {
                OutlinedTextField(
                    value = renameDraft,
                    onValueChange = { renameDraft = it.take(24) },
                    label = { Text("Device name") },
                    singleLine = true,
                )
            },
        )
    }

    revokeTarget?.let { slot ->
        AlertDialog(
            onDismissRequest = { revokeTarget = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        revokeTarget = null
                        coroutineScope.launch {
                            executeOwnerWrite("Revoking slot ${slot.id}") {
                                transport?.revoke(slot.id)
                            }
                        }
                    },
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { revokeTarget = null }) {
                    Text("Cancel")
                }
            },
            title = { Text("Revoke ${slotDisplayName(slot)}?") },
            text = { Text("This device will be permanently locked out.") },
        )
    }

    provisionGuestSlotId?.let { slotId ->
        AlertDialog(
            onDismissRequest = { provisionGuestSlotId = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        provisionGuestSlotId = null
                        coroutineScope.launch { provisionGuestSlot(slotId, replaceExisting = false) }
                    },
                ) {
                    Text("Create Key")
                }
            },
            dismissButton = {
                TextButton(onClick = { provisionGuestSlotId = null }) {
                    Text("Cancel")
                }
            },
            title = { Text("Add a guest key?") },
            text = { Text("This will create a key for Slot $slotId (${guestSlotDefaultName(slotId)}). The guest will be able to lock and unlock only.") },
        )
    }

    replaceGuestTarget?.let { slot ->
        AlertDialog(
            onDismissRequest = { replaceGuestTarget = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        replaceGuestTarget = null
                        coroutineScope.launch { provisionGuestSlot(slot.id, replaceExisting = true) }
                    },
                ) {
                    Text("Replace")
                }
            },
            dismissButton = {
                TextButton(onClick = { replaceGuestTarget = null }) {
                    Text("Cancel")
                }
            },
            title = { Text("Replace ${slotDisplayName(slot)}?") },
            text = { Text("This permanently locks out the old device and creates a new key for the replacement phone.") },
        )
    }

    if (confirmTransfer) {
        AlertDialog(
            onDismissRequest = { confirmTransfer = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmTransfer = false
                        if (localSlotId == 1) {
                            ownerTransferPin = ""
                            showOwnerTransferPin = true
                        } else {
                            coroutineScope.launch {
                                try {
                                    qrDisplayState = buildMigrationQrPayload(pin = null)
                                    actionError = null
                                } catch (error: Throwable) {
                                    actionError = error.message ?: "Unable to generate the migration QR."
                                }
                            }
                        }
                    },
                ) {
                    Text("Generate QR Code")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmTransfer = false }) {
                    Text("Cancel")
                }
            },
            title = { Text("Transfer your key to a new phone?") },
            text = { Text("This generates a QR code for your new phone to scan. After the transfer, this phone will no longer work as a key.") },
        )
    }

    if (showOwnerTransferPin) {
        AlertDialog(
            onDismissRequest = { showOwnerTransferPin = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        coroutineScope.launch {
                            try {
                                qrDisplayState = buildMigrationQrPayload(pin = ownerTransferPin)
                                actionError = null
                                showOwnerTransferPin = false
                            } catch (error: Throwable) {
                                actionError = error.message ?: "Unable to generate the migration QR."
                            }
                        }
                    },
                    enabled = ownerTransferPin.length == 6,
                ) {
                    Text("Generate")
                }
            },
            dismissButton = {
                TextButton(onClick = { showOwnerTransferPin = false }) {
                    Text("Cancel")
                }
            },
            title = { Text("Enter your 6-digit PIN") },
            text = {
                OutlinedTextField(
                    value = ownerTransferPin,
                    onValueChange = { ownerTransferPin = it.filter(Char::isDigit).take(6) },
                    label = { Text("PIN") },
                    keyboardOptions = KeyboardOptions.Default,
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                )
            },
        )
    }

    if (confirmDeleteLocalKey) {
        AlertDialog(
            onDismissRequest = { confirmDeleteLocalKey = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDeleteLocalKey = false
                        val finalLocalSlotId = localSlotId
                        if (finalLocalSlotId != null) {
                            keyStoreManager.deleteKey(finalLocalSlotId)
                            onLocalKeyDeleted()
                        }
                    },
                ) {
                    Text("Delete Key")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDeleteLocalKey = false }) {
                    Text("Cancel")
                }
            },
            title = { Text("Delete this phone's key?") },
            text = { Text("The key will be permanently deleted from this phone.") },
        )
    }

    if (showChangePinDialog) {
        AlertDialog(
            onDismissRequest = { showChangePinDialog = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        showChangePinDialog = false
                        coroutineScope.launch { changeManagementPin() }
                    },
                    enabled = changePinDraft.length == 6 && changePinDraft == confirmPinDraft,
                ) {
                    Text("Change PIN")
                }
            },
            dismissButton = {
                TextButton(onClick = { showChangePinDialog = false }) {
                    Text("Cancel")
                }
            },
            title = { Text("Change Management PIN") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = changePinDraft,
                        onValueChange = { changePinDraft = it.filter(Char::isDigit).take(6) },
                        label = { Text("New PIN") },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = confirmPinDraft,
                        onValueChange = { confirmPinDraft = it.filter(Char::isDigit).take(6) },
                        label = { Text("Confirm PIN") },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                    )
                    if (confirmPinDraft.isNotEmpty() && changePinDraft != confirmPinDraft) {
                        Text(
                            text = "PIN entries must match.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            },
        )
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Settings",
                        style = MaterialTheme.typography.headlineMedium
                    )
                    Text(
                        text = settingsSubtitle(localSlotId),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                }
                TextButton(onClick = onClose) {
                    Text("Close")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (actionMessage != null || actionError != null || actionBusy) {
                    SettingsSection(title = "STATUS") {
                        if (actionBusy) {
                            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            Spacer(modifier = Modifier.height(12.dp))
                        }
                        actionMessage?.let {
                            Text(
                                text = it,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                            )
                        }
                        actionError?.let {
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = it,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                }

                if (localSlotId == null) {
                    SettingsSection(title = "Key Status") {
                        Text(
                            text = "This device does not have a locally stored phone key. Settings stays read-only until onboarding finishes.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                        )
                    }
                }

                SettingsSection(
                    title = "PROXIMITY",
                    subtitle = "These controls are persisted locally and already drive the existing BLE unlock and lock logic."
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "Background Unlock",
                                style = MaterialTheme.typography.titleMedium
                            )
                            Text(
                                text = if (isProximityEnabled) {
                                    "Automatic unlock and lock are enabled."
                                } else {
                                    "Manual control only."
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                            )
                        }
                        Switch(
                            checked = isProximityEnabled,
                            onCheckedChange = ::updateProximityEnabled
                        )
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    RssiControl(
                        title = "Unlock RSSI",
                        value = unlockRssi,
                        enabled = isProximityEnabled,
                        rangeLabel = "Closer to 0 unlocks sooner.",
                        valueRange = UnlockRssiMin.toFloat()..UnlockRssiMax.toFloat(),
                        onValueChange = { updateUnlockRssi(it.roundToInt()) }
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    RssiControl(
                        title = "Lock RSSI",
                        value = lockRssi,
                        enabled = isProximityEnabled,
                        rangeLabel = "Always at least 10 dBm weaker than unlock.",
                        valueRange = LockRssiMin.toFloat()..(unlockRssi - HysteresisGapDbm).toFloat(),
                        onValueChange = { updateLockRssi(it.roundToInt()) }
                    )
                }

                if (isOwner) {
                    SettingsSection(
                        title = "KEYS",
                        subtitle = "Live slots from Guillemot over the existing management transport. Owner writes always re-identify before mutating a slot."
                    ) {
                        when {
                            isLoadingSlots -> LoadingMessage(sessionState = sessionState)
                            slotError != null -> ErrorMessage(message = requireNotNull(slotError), retry = { refreshToken += 1 })
                            hasLoadedSlots -> {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    displaySlots.forEach { slot ->
                                        OwnerSlotRow(
                                            slot = slot,
                                            localSlotId = localSlotId,
                                            onProvisionGuest = { provisionGuestSlotId = slot.id },
                                            onRenameGuest = {
                                                renameTarget = RenameTarget(slot.id, slotDisplayName(slot))
                                                renameDraft = slotDisplayName(slot)
                                            },
                                            onReplaceGuest = { replaceGuestTarget = slot },
                                            onDeleteGuest = { revokeTarget = slot },
                                        )
                                    }
                                }
                            }
                            else -> Text(
                                text = "Waiting to open the management session.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                            )
                        }
                    }

                    SettingsSection(
                        title = "DEVICE",
                        subtitle = "Owner migration stays BLE-only. Slot 0 maintenance, PIN changes, and Guillemot flashing consume the existing Android USB backend."
                    ) {
                        Button(
                            onClick = { confirmTransfer = true },
                            enabled = !actionBusy,
                        ) {
                            Text("Transfer to New Phone")
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                        Button(
                            onClick = { coroutineScope.launch { replaceUguisu() } },
                            enabled = !actionBusy,
                        ) {
                            Text("Replace Uguisu (USB)")
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                        OutlinedButton(
                            onClick = {
                                changePinDraft = ""
                                confirmPinDraft = ""
                                showChangePinDialog = true
                            },
                            enabled = !actionBusy,
                        ) {
                            Text("Change PIN (USB)")
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                        OutlinedButton(
                            onClick = {
                                pendingFlashTarget = PendingFlashTarget.GUILLEMOT
                                uf2Picker.launch(arrayOf("application/octet-stream", "*/*"))
                            },
                            enabled = !actionBusy,
                        ) {
                            Text("Flash Guillemot UF2")
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = "Uguisu firmware flashing is still blocked by the USB backend; the existing module only provisions its key right now.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        UsbStatusCard(usbState = usbState)
                    }
                } else {
                    SettingsSection(
                        title = "YOUR KEY",
                        subtitle = "Guests only manage their own migration and local proximity preferences."
                    ) {
                        when {
                            selfSlot != null -> {
                                SlotRow(slot = selfSlot, localSlotId = localSlotId)
                                Spacer(modifier = Modifier.height(12.dp))
                                Button(
                                    onClick = { confirmTransfer = true },
                                    enabled = !actionBusy,
                                ) {
                                    Text("Transfer to New Phone")
                                }
                            }
                            hasLoadedSlots -> Text(
                                text = "Your phone slot could not be matched to the current slot list.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                            )
                            isLoadingSlots -> LoadingMessage(sessionState = sessionState)
                            slotError != null -> ErrorMessage(
                                message = requireNotNull(slotError),
                                retry = { refreshToken += 1 }
                            )
                            else -> Text(
                                text = "Waiting for a management session.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                            )
                        }
                    }
                }

                SettingsSection(
                    title = "ABOUT",
                    subtitle = if (isOwner) {
                        "Session state, app build, and current slot context."
                    } else {
                        "Read-only vehicle slot overview, app build, and session state."
                    }
                ) {
                    SessionStatus(sessionState = sessionState)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = "Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    if (!isOwner) {
                        SlotSectionBody(
                            slots = displaySlots,
                            localSlotId = localSlotId,
                            hasLoadedSlots = hasLoadedSlots,
                            isLoadingSlots = isLoadingSlots,
                            slotError = slotError,
                            retry = { refreshToken += 1 }
                        )
                    } else {
                        Text(
                            text = "Local phone slot: $localSlotId",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsSection(
    title: String,
    subtitle: String? = null,
    content: @Composable () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
        ),
        shape = RoundedCornerShape(20.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold
            )
            if (!subtitle.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )
            }
            Spacer(modifier = Modifier.height(16.dp))
            content()
        }
    }
}

@Composable
private fun OwnerSlotRow(
    slot: BleManagementSlot,
    localSlotId: Int?,
    onProvisionGuest: () -> Unit,
    onRenameGuest: () -> Unit,
    onReplaceGuest: () -> Unit,
    onDeleteGuest: () -> Unit,
) {
    var menuExpanded by remember(slot.id) { mutableStateOf(false) }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        tonalElevation = 1.dp,
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Slot ${slot.id} · ${slotTierLabel(slot.id)}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = slotDisplayName(slot),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.78f)
                    )
                }
                when {
                    slot.id == 0 -> Text(
                        text = slotBadge(slot, localSlotId),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )

                    slot.id == localSlotId -> Text(
                        text = slotBadge(slot, localSlotId),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )

                    slot.id in 2..3 && slot.used -> {
                        Box {
                            IconButton(onClick = { menuExpanded = true }) {
                                Text(
                                    text = "⋮",
                                    style = MaterialTheme.typography.titleLarge,
                                    fontFamily = FontFamily.Monospace,
                                )
                            }
                            DropdownMenu(
                                expanded = menuExpanded,
                                onDismissRequest = { menuExpanded = false },
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Rename") },
                                    onClick = {
                                        menuExpanded = false
                                        onRenameGuest()
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text("Replace") },
                                    onClick = {
                                        menuExpanded = false
                                        onReplaceGuest()
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text("Delete") },
                                    onClick = {
                                        menuExpanded = false
                                        onDeleteGuest()
                                    },
                                )
                            }
                        }
                    }

                    else -> Text(
                        text = slotBadge(slot, localSlotId),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            Text(
                text = when {
                    slot.id == 0 -> "Hardware slot. Replace over USB-C OTG when swapping in a new Uguisu."
                    slot.used -> "Counter ${slot.counter}"
                    slot.id in 2..3 -> "Available for provisioning"
                    else -> "Owner slot should normally already be provisioned."
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
            )

            if (slot.id in 2..3 && !slot.used) {
                OutlinedButton(onClick = onProvisionGuest) {
                    Text("Add Guest Key")
                }
            }
        }
    }
}

@Composable
private fun SlotSectionBody(
    slots: List<BleManagementSlot>,
    localSlotId: Int?,
    hasLoadedSlots: Boolean,
    isLoadingSlots: Boolean,
    slotError: String?,
    retry: () -> Unit
) {
    when {
        isLoadingSlots -> LoadingMessage(sessionState = null)
        slotError != null -> ErrorMessage(message = requireNotNull(slotError), retry = retry)
        hasLoadedSlots && slots.isEmpty() -> Text(
            text = "No slots were returned by the vehicle.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
        )
        hasLoadedSlots -> {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                slots.forEach { slot ->
                    SlotRow(slot = slot, localSlotId = localSlotId)
                }
            }
        }
        else -> Text(
            text = "Waiting to open the management session.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
        )
    }
}

@Composable
private fun SlotRow(
    slot: BleManagementSlot,
    localSlotId: Int?
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        tonalElevation = 1.dp,
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Slot ${slot.id} · ${slotTierLabel(slot.id)}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = slotDisplayName(slot),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.78f)
                    )
                }
                Text(
                    text = slotBadge(slot = slot, localSlotId = localSlotId),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Text(
                text = if (slot.id == 0) {
                    "Hardware slot"
                } else if (slot.used) {
                    "Counter ${slot.counter}"
                } else {
                    "Available for provisioning"
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
            )
        }
    }
}

@Composable
private fun UsbStatusCard(usbState: UsbState) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = "USB Status",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = usbStatusLabel(usbState),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
            )
        }
    }
}

@Composable
private fun QrDisplayDialog(
    state: QrDisplayState,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    val qrBitmap = remember(state.payload) { generateQrBitmap(state.payload) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(state.primaryButtonText)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
        title = { Text(state.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = state.body,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Image(
                    bitmap = qrBitmap.asImageBitmap(),
                    contentDescription = state.title,
                    modifier = Modifier
                        .size(240.dp)
                        .background(androidx.compose.ui.graphics.Color.White, RoundedCornerShape(16.dp))
                        .padding(12.dp),
                )
                Text(
                    text = "Provisioning payload is hidden for security. Use only the QR code to transfer.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                )
            }
        },
    )
}

@Composable
private fun SessionStatus(sessionState: BleManagementSessionState) {
    val statusText = when (sessionState.connectionState) {
        BleManagementSessionConnectionState.DISCONNECTED -> "Disconnected"
        BleManagementSessionConnectionState.CONNECTING -> "Connecting to management GATT"
        BleManagementSessionConnectionState.DISCOVERING -> "Discovering management characteristics"
        BleManagementSessionConnectionState.READY -> "Management session ready"
        BleManagementSessionConnectionState.ERROR -> sessionState.lastError ?: "Management session failed"
    }

    Text(
        text = statusText,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
    )
    if (sessionState.deviceAddress != null) {
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "Device ${sessionState.deviceAddress}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
        )
    }
}

@Composable
private fun RssiControl(
    title: String,
    value: Int,
    enabled: Boolean,
    rangeLabel: String,
    valueRange: ClosedFloatingPointRange<Float>,
    onValueChange: (Float) -> Unit
) {
    val safeRange = if (valueRange.endInclusive < valueRange.start) {
        valueRange.start..valueRange.start
    } else {
        valueRange
    }

    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(
                text = "$value dBm",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = rangeLabel,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
        )
        Slider(
            value = value.toFloat().coerceIn(safeRange.start, safeRange.endInclusive),
            onValueChange = onValueChange,
            valueRange = safeRange,
            enabled = enabled
        )
    }
}

@Composable
private fun LoadingMessage(sessionState: BleManagementSessionState?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(modifier = Modifier.width(20.dp).height(20.dp), strokeWidth = 2.dp)
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = sessionState?.let { managementStatusText(it) } ?: "Loading slots...",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
        )
    }
}

@Composable
private fun ErrorMessage(
    message: String,
    retry: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error
        )
        OutlinedButton(onClick = retry) {
            Text("Retry")
        }
    }
}

private fun settingsSubtitle(localSlotId: Int?): String {
    return when (localSlotId) {
        1 -> "Owner controls, guest provisioning, migration, and USB maintenance"
        2, 3 -> "Guest controls, migration, and read-only slot overview"
        else -> "Read-only slot overview and proximity settings"
    }
}

private fun determineLocalPhoneSlotId(keyStoreManager: KeyStoreManager): Int? {
    for (slotId in 1..3) {
        if (keyStoreManager.loadKey(slotId) != null) {
            return slotId
        }
    }
    return null
}

private fun buildDisplaySlots(slots: List<BleManagementSlot>): List<BleManagementSlot> {
    val slotsById = slots.associateBy { it.id }
    return (0..3).map { slotId ->
        slotsById[slotId] ?: BleManagementSlot(
            id = slotId,
            used = false,
            counter = 0u,
            name = if (slotId == 0) "Uguisu" else ""
        )
    }
}

private fun slotTierLabel(slotId: Int): String {
    return when (slotId) {
        0 -> "HARDWARE KEY"
        1 -> "OWNER"
        2, 3 -> "GUEST"
        else -> "PHONE SLOT"
    }
}

private fun slotDisplayName(slot: BleManagementSlot): String {
    if (slot.name.isNotBlank()) {
        return slot.name
    }
    return defaultSlotName(slot.id, slot.used)
}

private fun defaultSlotName(slotId: Int, used: Boolean = true): String {
    return when (slotId) {
        0 -> "Uguisu"
        2 -> if (used) "Guest 1" else "Empty"
        3 -> if (used) "Guest 2" else "Empty"
        1 -> if (used) "Owner Phone" else "Owner"
        else -> if (used) "Provisioned" else "Empty"
    }
}

private fun guestSlotDefaultName(slotId: Int): String = when (slotId) {
    2 -> "Guest 1"
    3 -> "Guest 2"
    else -> "Guest"
}

private fun slotBadge(slot: BleManagementSlot, localSlotId: Int?): String {
    return when {
        slot.id == localSlotId -> "THIS PHONE"
        slot.id == 0 -> "HARDWARE"
        slot.used -> "ACTIVE"
        else -> "EMPTY"
    }
}

private fun managementStatusText(sessionState: BleManagementSessionState): String {
    return when (sessionState.connectionState) {
        BleManagementSessionConnectionState.DISCONNECTED -> "Opening management session..."
        BleManagementSessionConnectionState.CONNECTING -> "Connecting to Guillemot over management GATT..."
        BleManagementSessionConnectionState.DISCOVERING -> "Discovering management characteristics..."
        BleManagementSessionConnectionState.READY -> "Loading slot data..."
        BleManagementSessionConnectionState.ERROR -> sessionState.lastError ?: "Management session failed."
    }
}

private fun buildPlainProvisioningUri(
    slotId: Int,
    key: ByteArray,
    counter: UInt,
    name: String,
): String {
    return Uri.Builder()
        .scheme("immogen")
        .authority("prov")
        .appendQueryParameter("slot", slotId.toString())
        .appendQueryParameter("key", key.toHex())
        .appendQueryParameter("ctr", counter.toString())
        .appendQueryParameter("name", name)
        .build()
        .toString()
}

private fun buildEncryptedProvisioningUri(
    slotId: Int,
    salt: ByteArray,
    encryptedKey: ByteArray,
    counter: UInt,
    name: String,
): String {
    return Uri.Builder()
        .scheme("immogen")
        .authority("prov")
        .appendQueryParameter("slot", slotId.toString())
        .appendQueryParameter("salt", salt.toHex())
        .appendQueryParameter("ekey", encryptedKey.toHex())
        .appendQueryParameter("ctr", counter.toString())
        .appendQueryParameter("name", name)
        .build()
        .toString()
}

private fun generateQrBitmap(payload: String, size: Int = 768): Bitmap {
    val matrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, size, size)
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) {
        for (y in 0 until size) {
            bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
        }
    }
    return bitmap
}

private fun usbStatusLabel(usbState: UsbState): String {
    return when (usbState) {
        UsbState.Disconnected -> "No supported USB device is connected."
        UsbState.Connecting -> "Negotiating USB access..."
        is UsbState.Connected -> when (usbState.deviceType) {
            DeviceType.GUILLEMOT_MASS_STORAGE -> "Guillemot mass-storage mode detected. Ready for UF2 flashing."
            DeviceType.GUILLEMOT_SERIAL -> "Guillemot serial link detected. Ready for PIN changes."
            DeviceType.UGUISU_SERIAL -> "Uguisu serial link detected. Ready for Slot 0 replacement."
            DeviceType.UNKNOWN -> "Unsupported USB device."
        }
        is UsbState.Error -> usbState.message
        is UsbState.Flashing -> "Flashing firmware... ${usbState.progressPercent}%"
        UsbState.FlashingSuccess -> "Firmware flashing completed successfully."
        UsbState.PinChangeSuccess -> "PIN change completed successfully."
        UsbState.ProvisioningSuccess -> "Uguisu provisioning completed successfully."
    }
}
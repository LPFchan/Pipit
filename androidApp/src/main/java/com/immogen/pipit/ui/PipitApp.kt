package com.immogen.pipit.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import com.immogen.core.ImmoCrypto
import com.immogen.core.KeyStoreManager
import com.immogen.pipit.ble.BleManagementConnectMode
import com.immogen.pipit.ble.BleManagementResponseException
import com.immogen.pipit.ble.BleManagementSessionConnectionState
import com.immogen.pipit.ble.BleManagementSessionState
import com.immogen.pipit.ble.BleManagementSlot
import com.immogen.pipit.ble.BleState
import com.immogen.pipit.ble.BleService
import com.immogen.pipit.ble.ConnectionState
import com.immogen.pipit.onboarding.OnboardingGate
import com.immogen.pipit.onboarding.ProvisioningQrParseException
import com.immogen.pipit.onboarding.ProvisioningQrParser
import com.immogen.pipit.onboarding.ProvisioningQrPayload
import java.security.SecureRandom
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class RootScreen {
    ONBOARDING,
    HOME,
    SETTINGS
}

private enum class RecoveryStage {
    INTRO,
    WAITING_FOR_WINDOW_OPEN,
    CONNECTING,
    LOADING_SLOTS,
    OWNER_PROOF,
    RECOVERING,
    SLOT_PICKER,
    ERROR
}

private enum class OnboardingStage {
    CAMERA,
    PIN,
    IMPORTING,
    RECOVERY,
    SUCCESS
}

private data class ProvisioningSuccess(
    val slotId: Int,
    val counter: UInt,
    val name: String,
)

private data class PendingProvisioningMaterial(
    val slotId: Int,
    val key: ByteArray,
    val counter: UInt,
    val name: String,
    val statusText: String,
)

@Composable
fun PipitApp(
    bleState: BleState,
    bleService: BleService?,
    onRequestUnlock: () -> Unit,
    onRequestLock: () -> Unit
) {
    val onboardingGate = remember { OnboardingGate() }
    var currentScreen by remember {
        mutableStateOf(
            if (onboardingGate.hasAnyProvisionedKey()) RootScreen.HOME else RootScreen.ONBOARDING
        )
    }
    var hintDismissed by remember { mutableStateOf(false) }
    var lockHintDismissed by remember { mutableStateOf(false) }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = currentScreen,
            label = "rootTransition"
        ) { screen ->
            when (screen) {
                RootScreen.ONBOARDING -> {
                    OnboardingPlaceholderView(
                        bleState = bleState,
                        bleService = bleService,
                        onComplete = { currentScreen = RootScreen.HOME }
                    )
                }

                RootScreen.SETTINGS -> {
                    SettingsPlaceholderView(onClose = { currentScreen = RootScreen.HOME })
                }

                RootScreen.HOME -> {
                    HomeScreen(
                        bleState = bleState,
                        onGearClick = { currentScreen = RootScreen.SETTINGS },
                        onTapFob = {
                            if (!hintDismissed) hintDismissed = true
                            onRequestUnlock()
                        },
                        onLongPressFob = {
                            if (!lockHintDismissed) lockHintDismissed = true
                            onRequestLock()
                        },
                        showTapHint = !hintDismissed || !lockHintDismissed
                    )
                    DisconnectOverlay(
                        bleState = bleState,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }
    }
}

@Composable
private fun HomeScreen(
    bleState: BleState,
    onGearClick: () -> Unit,
    onTapFob: () -> Unit,
    onLongPressFob: () -> Unit,
    showTapHint: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        IconButton(
            onClick = onGearClick,
            modifier = Modifier.align(Alignment.Start)
        ) {
            Icon(
                imageVector = Icons.Default.Settings,
                contentDescription = "Settings"
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        Fob3DView(
            onTap = onTapFob,
            onLongPress = onLongPressFob,
            modifier = Modifier
                .weight(2f)
                .fillMaxWidth()
        )
        if (showTapHint) {
            Text(
                text = "Tap · Hold to lock",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                textAlign = TextAlign.Center
            )
        }
        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun FobPlaceholderView(
    onTap: () -> Unit,
    onLongPress: () -> Unit,
    modifier: Modifier = Modifier
) {
    var pressed by remember { mutableStateOf(false) }
    val haptic = LocalHapticFeedback.current
    val depressOffset by animateFloatAsState(
        targetValue = if (pressed) 1f else 0f,
        animationSpec = tween(80), label = "depress"
    )
    Box(
        modifier = modifier
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = {
                        pressed = true
                        tryAwaitRelease()
                        pressed = false
                    },
                    onTap = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onTap()
                    },
                    onLongPress = {
                        pressed = true
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onLongPress()
                        pressed = false
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        Surface(
            modifier = Modifier
                .size(200.dp, 140.dp)
                .padding(bottom = (depressOffset * 4).dp),
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceVariant,
            shadowElevation = if (pressed) 2.dp else 8.dp
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "Uguisu\n(placeholder)",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

@Composable
private fun DisconnectOverlay(
    bleState: BleState,
    modifier: Modifier = Modifier
) {
    val connected = bleState.connectionState != ConnectionState.DISCONNECTED &&
        bleState.connectionState != ConnectionState.SCANNING
    val showOverlay = !connected
    val alpha by animateFloatAsState(
        targetValue = if (showOverlay) 1f else 0f,
        animationSpec = tween(200), label = "overlay"
    )
    if (alpha > 0f) {
        Box(
            modifier = modifier
                .background(
                    MaterialTheme.colorScheme.surface.copy(alpha = 0.6f * alpha)
                )
                .padding(32.dp),
            contentAlignment = Alignment.Center
        ) {
            val (icon, text) = when {
                !bleState.isBluetoothEnabled -> "✕" to "Bluetooth is off"
                else -> "○" to "Disconnected"
            }
            Text(
                text = "$icon $text",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
    }
}

@Composable
fun SettingsPlaceholderView(
    onClose: () -> Unit
) {
    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp)
        ) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Placeholder — Agent 8 will populate.",
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(modifier = Modifier.height(24.dp))
            IconButton(onClick = onClose) {
                Text("✕ Close")
            }
        }
    }
}

@Composable
fun OnboardingPlaceholderView(
    bleState: BleState,
    bleService: BleService?,
    onComplete: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()
    val keyStoreManager = remember { KeyStoreManager() }
    val emptySessionStateFlow = remember { MutableStateFlow(BleManagementSessionState()) }
    val sessionStateFlow = bleService?.managementTransport?.sessionState ?: emptySessionStateFlow
    val sessionState by sessionStateFlow.collectAsState(initial = BleManagementSessionState())

    var onboardingStage by remember { mutableStateOf(OnboardingStage.CAMERA) }
    var recoveryStage by remember { mutableStateOf(RecoveryStage.INTRO) }
    var recoverySlots by remember { mutableStateOf<List<BleManagementSlot>>(emptyList()) }
    var selectedSlotId by remember { mutableStateOf<Int?>(null) }
    var recoveryError by remember { mutableStateOf<String?>(null) }
    var encryptedPayload by remember { mutableStateOf<ProvisioningQrPayload.Encrypted?>(null) }
    var provisioningSuccess by remember { mutableStateOf<ProvisioningSuccess?>(null) }
    var successOverviewSlots by remember { mutableStateOf<List<BleManagementSlot>>(emptyList()) }
    var pendingProvisioningMaterial by remember { mutableStateOf<PendingProvisioningMaterial?>(null) }
    var scanError by remember { mutableStateOf<String?>(null) }
    var pin by remember { mutableStateOf("") }
    var pinError by remember { mutableStateOf<String?>(null) }
    var isSubmittingPin by remember { mutableStateOf(false) }
    var scanLocked by remember { mutableStateOf(false) }

    fun completeProvisioning(slotId: Int, key: ByteArray, counter: UInt, name: String) {
        keyStoreManager.saveKey(slotId, key)
        keyStoreManager.saveCounter(slotId, counter)
        provisioningSuccess = ProvisioningSuccess(slotId = slotId, counter = counter, name = name)
        successOverviewSlots = buildSuccessOverviewSlots(
            selectedSlotId = slotId,
            counter = counter,
            name = name,
            knownSlots = recoverySlots,
        )
        encryptedPayload = null
        pendingProvisioningMaterial = null
        pin = ""
        pinError = null
        scanError = null
        scanLocked = false
        onboardingStage = OnboardingStage.SUCCESS
    }

    fun beginProvisioningImport(
        slotId: Int,
        key: ByteArray,
        counter: UInt,
        name: String,
        statusText: String,
    ) {
        pendingProvisioningMaterial = PendingProvisioningMaterial(
            slotId = slotId,
            key = key,
            counter = counter,
            name = name,
            statusText = statusText,
        )
        onboardingStage = OnboardingStage.IMPORTING
    }

    val returnToCamera: () -> Unit = {
        onboardingStage = OnboardingStage.CAMERA
        encryptedPayload = null
        provisioningSuccess = null
        successOverviewSlots = emptyList()
        pendingProvisioningMaterial = null
        pin = ""
        pinError = null
        scanError = null
        scanLocked = false
        isSubmittingPin = false
        bleService?.stopWindowOpenScan()
        coroutineScope.launch {
            runCatching { bleService?.managementTransport?.disconnect() }
        }
    }

    val resetRecovery: () -> Unit = {
        recoveryStage = RecoveryStage.INTRO
        recoverySlots = emptyList()
        selectedSlotId = null
        recoveryError = null
        successOverviewSlots = emptyList()
        pendingProvisioningMaterial = null
        bleService?.stopWindowOpenScan()
        coroutineScope.launch {
            runCatching { bleService?.managementTransport?.disconnect() }
        }
        onboardingStage = OnboardingStage.CAMERA
    }

    LaunchedEffect(onboardingStage, pendingProvisioningMaterial) {
        val pendingMaterial = pendingProvisioningMaterial
        if (onboardingStage != OnboardingStage.IMPORTING || pendingMaterial == null) {
            return@LaunchedEffect
        }

        delay(1000)
        completeProvisioning(
            slotId = pendingMaterial.slotId,
            key = pendingMaterial.key,
            counter = pendingMaterial.counter,
            name = pendingMaterial.name,
        )
    }

    val startRecovery: () -> Unit = {
        recoverySlots = emptyList()
        selectedSlotId = null
        recoveryError = null
        scanError = null
        onboardingStage = OnboardingStage.RECOVERY
        if (bleService?.managementTransport == null) {
            recoveryStage = RecoveryStage.ERROR
            recoveryError = "Recovery transport is unavailable. Wait for BLE to finish binding and try again."
        } else {
            recoveryStage = RecoveryStage.WAITING_FOR_WINDOW_OPEN
            bleService.startWindowOpenScan()
        }
    }

    DisposableEffect(bleService) {
        onDispose {
            bleService?.stopWindowOpenScan()
            coroutineScope.launch {
                runCatching { bleService?.managementTransport?.disconnect() }
            }
        }
    }

    LaunchedEffect(bleState.isWindowOpen, recoveryStage, onboardingStage, bleService) {
        if (onboardingStage != OnboardingStage.RECOVERY ||
            recoveryStage != RecoveryStage.WAITING_FOR_WINDOW_OPEN ||
            !bleState.isWindowOpen
        ) {
            return@LaunchedEffect
        }

        val transport = bleService?.managementTransport
        if (transport == null) {
            recoveryStage = RecoveryStage.ERROR
            recoveryError = "Recovery transport became unavailable before connection could start."
            bleService?.stopWindowOpenScan()
            return@LaunchedEffect
        }

        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        recoveryStage = RecoveryStage.CONNECTING
        bleService.stopWindowOpenScan()

        try {
            transport.connect(BleManagementConnectMode.WINDOW_OPEN_RECOVERY)
            recoveryStage = RecoveryStage.LOADING_SLOTS
            val slotsResponse = transport.requestSlots()
            recoverySlots = slotsResponse.slots.sortedBy { it.id }
            selectedSlotId = recoverySlots.firstOrNull { it.used }?.id
            recoveryStage = RecoveryStage.SLOT_PICKER
        } catch (error: Throwable) {
            recoveryStage = RecoveryStage.ERROR
            recoveryError = error.message ?: "Unable to load recovery slots."
            runCatching { transport.disconnect() }
        }
    }

    val executeRecovery: () -> Unit = executeRecovery@{
        val transport = bleService?.managementTransport
        val slotId = selectedSlotId
        val targetSlot = recoverySlots.firstOrNull { it.id == slotId && it.used }

        if (transport == null) {
            recoveryStage = RecoveryStage.ERROR
            recoveryError = "Recovery transport is unavailable. Restart the recovery flow and try again."
            return@executeRecovery
        }
        if (targetSlot == null) {
            recoveryError = "Select an occupied slot to recover onto this phone."
            return@executeRecovery
        }

        recoveryError = null
        if (targetSlot.id == 1 && recoveryStage != RecoveryStage.OWNER_PROOF) {
            recoveryStage = RecoveryStage.OWNER_PROOF
            return@executeRecovery
        }

        recoveryStage = RecoveryStage.RECOVERING
        coroutineScope.launch {
            try {
                val recoveryKey = ByteArray(16).also(SecureRandom()::nextBytes)
                val recoveredName = defaultRecoveredSlotName(targetSlot)
                val response = transport.recover(
                    slotId = targetSlot.id,
                    key = recoveryKey,
                    counter = 0u,
                    name = recoveredName,
                )
                val finalCounter = response.counter ?: 0u
                val finalName = response.name ?: recoveredName
                recoverySlots = buildSuccessOverviewSlots(
                    selectedSlotId = targetSlot.id,
                    counter = finalCounter,
                    name = finalName,
                    knownSlots = recoverySlots,
                )
                completeProvisioning(
                    slotId = targetSlot.id,
                    key = recoveryKey,
                    counter = finalCounter,
                    name = finalName,
                )
                runCatching { transport.disconnect() }
            } catch (error: BleManagementResponseException) {
                if (targetSlot.id == 1 && error.isPairingRequiredRecoveryError()) {
                    recoveryStage = RecoveryStage.OWNER_PROOF
                    recoveryError = "Pairing failed. Check the 6-digit Guillemot PIN and try again. Android should show the system Bluetooth pairing sheet for Owner recovery."
                } else {
                    recoveryStage = RecoveryStage.ERROR
                    recoveryError = error.message ?: "Unable to recover this slot."
                    runCatching { transport.disconnect() }
                }
            } catch (error: Throwable) {
                recoveryStage = RecoveryStage.ERROR
                recoveryError = error.message ?: "Unable to recover this slot."
                runCatching { transport.disconnect() }
            }
        }
    }

    val handleQrValue: (String) -> Unit = qrHandler@{ rawValue ->
        if (scanLocked || onboardingStage != OnboardingStage.CAMERA) {
            return@qrHandler
        }

        val payload = try {
            ProvisioningQrParser.parseIfProvisioningQr(rawValue)
        } catch (error: ProvisioningQrParseException) {
            scanError = error.message
            null
        } catch (error: IllegalArgumentException) {
            scanError = error.message ?: "Invalid provisioning QR payload."
            null
        }

        if (payload == null) {
            return@qrHandler
        }

        scanLocked = true
        when (payload) {
            is ProvisioningQrPayload.Guest -> {
                beginProvisioningImport(
                    slotId = payload.slotId,
                    key = payload.key,
                    counter = payload.counter,
                    name = payload.name,
                    statusText = "Importing your phone key...",
                )
            }

            is ProvisioningQrPayload.Encrypted -> {
                encryptedPayload = payload
                pin = ""
                pinError = null
                scanError = null
                scanLocked = false
                onboardingStage = OnboardingStage.PIN
            }
        }
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Onboarding",
                style = MaterialTheme.typography.headlineMedium
            )
            Spacer(modifier = Modifier.height(20.dp))

            when (onboardingStage) {
                OnboardingStage.CAMERA -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(420.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        ProvisioningQrScannerView(
                            modifier = Modifier.fillMaxSize(),
                            enabled = !scanLocked,
                            onQrDetected = handleQrValue,
                        )
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.38f))
                        )
                        Surface(
                            modifier = Modifier.size(240.dp),
                            shape = RoundedCornerShape(28.dp),
                            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.14f),
                            border = BorderStroke(2.dp, MaterialTheme.colorScheme.onSurface)
                        ) {}
                    }
                    Spacer(modifier = Modifier.height(20.dp))
                    Text(
                        text = "Scan from Whimbrel",
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Point the camera at an immogen://prov QR code. Guest keys provision immediately; owner and migration keys continue to PIN entry.",
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f)
                    )
                    if (scanError != null) {
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = scanError ?: "",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error,
                            textAlign = TextAlign.Center,
                        )
                    }
                    Spacer(modifier = Modifier.height(20.dp))
                    TextButton(onClick = startRecovery) {
                        Text("recover key from lost phone >")
                    }
                }

                OnboardingStage.PIN -> {
                    val payload = encryptedPayload
                    Text(
                        text = "Enter your 6-digit PIN",
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "This is the PIN you set during Guillemot setup.",
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f)
                    )
                    Spacer(modifier = Modifier.height(20.dp))
                    Row {
                        repeat(6) { index ->
                            Surface(
                                modifier = Modifier.size(42.dp),
                                shape = RoundedCornerShape(10.dp),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Text(
                                        text = pin.getOrNull(index)?.toString() ?: "",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontFamily = FontFamily.Monospace,
                                    )
                                }
                            }
                            if (index < 5) {
                                Spacer(modifier = Modifier.size(8.dp))
                            }
                        }
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    OutlinedTextField(
                        value = pin,
                        onValueChange = { newValue ->
                            pin = newValue.filter(Char::isDigit).take(6)
                            pinError = null
                        },
                        label = { Text("PIN") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        singleLine = true,
                    )
                    if (pinError != null) {
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = pinError ?: "",
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    Spacer(modifier = Modifier.height(20.dp))
                    Button(
                        onClick = {
                            if (payload == null || isSubmittingPin) {
                                return@Button
                            }

                            isSubmittingPin = true
                            pinError = null
                            coroutineScope.launch {
                                try {
                                    if (!ImmoCrypto.isInitialized()) {
                                        ImmoCrypto.initialize()
                                    }
                                    val decryptedKey = ImmoCrypto.decryptProvisionedKey(
                                        pin = pin,
                                        salt = payload.salt,
                                        encryptedKey = payload.encryptedKey,
                                    )
                                    beginProvisioningImport(
                                        slotId = payload.slotId,
                                        key = decryptedKey,
                                        counter = payload.counter,
                                        name = payload.name,
                                        statusText = "Decrypting and securing your phone key...",
                                    )
                                } catch (_: ImmoCrypto.InvalidProvisioningPinException) {
                                    pinError = "Incorrect PIN."
                                } catch (error: Throwable) {
                                    pinError = error.message ?: "Unable to decrypt this provisioning QR."
                                } finally {
                                    isSubmittingPin = false
                                }
                            }
                        },
                        enabled = pin.length == 6 && !isSubmittingPin,
                    ) {
                        Text(if (isSubmittingPin) "Decrypting..." else "Confirm")
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    OutlinedButton(onClick = returnToCamera, enabled = !isSubmittingPin) {
                        Text("Back to scan")
                    }
                }

                OnboardingStage.IMPORTING -> {
                    val importStatus = pendingProvisioningMaterial?.statusText ?: "Securing your phone key..."
                    OnboardingImportAnimation()
                    Spacer(modifier = Modifier.height(20.dp))
                    Text(
                        text = importStatus,
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = "Pipit is finalizing secure key storage on this device.",
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f)
                    )
                }

                OnboardingStage.RECOVERY -> {
                    Text(
                        text = if (recoveryStage == RecoveryStage.SLOT_PICKER) {
                            "Select your lost slot"
                        } else if (recoveryStage == RecoveryStage.OWNER_PROOF) {
                            "Owner proof required"
                        } else {
                            "Recover key from lost phone"
                        },
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = if (recoveryStage == RecoveryStage.SLOT_PICKER) {
                            "Pick the phone slot you want to replace on this device. Pipit will mint a fresh AES key and revoke the lost phone immediately."
                        } else if (recoveryStage == RecoveryStage.OWNER_PROOF) {
                            "Recovering Slot 1 requires BLE owner proof. When you continue, Android should show the system Bluetooth pairing prompt. Enter the 6-digit Guillemot PIN to authorize the recovery."
                        } else {
                            "Press the button three times on your Uguisu fob. Pipit will detect Window Open and fetch the slot list automatically."
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f)
                    )
                    Spacer(modifier = Modifier.height(20.dp))

                    if (recoveryStage != RecoveryStage.SLOT_PICKER && recoveryStage != RecoveryStage.OWNER_PROOF) {
                        CircularProgressIndicator()
                        Spacer(modifier = Modifier.height(16.dp))
                    }

                    Text(
                        text = when (recoveryStage) {
                            RecoveryStage.WAITING_FOR_WINDOW_OPEN -> "Scanning for the Window Open beacon..."
                            RecoveryStage.CONNECTING -> recoverySessionStatus(sessionState)
                            RecoveryStage.LOADING_SLOTS -> "Management connected. Loading slot inventory..."
                            RecoveryStage.OWNER_PROOF -> "The next step uses Android's Bluetooth pairing sheet for Owner recovery."
                            RecoveryStage.RECOVERING -> selectedSlotId?.let { "Recovering slot $it onto this phone..." }
                                ?: "Recovering the selected slot..."
                            RecoveryStage.SLOT_PICKER -> selectedSlotId?.let { "Selected slot $it" }
                                ?: "Select a slot to recover onto this phone."
                            RecoveryStage.ERROR -> recoveryError ?: "Unable to load recovery slots."
                            RecoveryStage.INTRO -> ""
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = if (recoveryStage == RecoveryStage.ERROR) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )

                    if (recoveryStage == RecoveryStage.OWNER_PROOF && recoveryError != null) {
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = recoveryError ?: "",
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }

                    if (recoveryStage == RecoveryStage.SLOT_PICKER) {
                        Spacer(modifier = Modifier.height(20.dp))
                        recoverySlots.forEach { slot ->
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(18.dp),
                                color = if (selectedSlotId == slot.id) {
                                    MaterialTheme.colorScheme.secondaryContainer
                                } else {
                                    MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
                                },
                                border = BorderStroke(
                                    width = 1.dp,
                                    color = if (selectedSlotId == slot.id) {
                                        MaterialTheme.colorScheme.secondary
                                    } else {
                                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f)
                                    }
                                )
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .pointerInput(slot.id) {
                                            detectTapGestures(
                                                onTap = {
                                                    if (slot.used) {
                                                        selectedSlotId = slot.id
                                                    }
                                                }
                                            )
                                        }
                                        .padding(horizontal = 18.dp, vertical = 14.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = "Slot ${slot.id}",
                                            style = MaterialTheme.typography.titleSmall
                                        )
                                        Spacer(modifier = Modifier.height(4.dp))
                                        Text(
                                            text = if (slot.used) {
                                                if (slot.name.isBlank()) "In use" else slot.name
                                            } else {
                                                "Empty"
                                            },
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f)
                                        )
                                        Spacer(modifier = Modifier.height(4.dp))
                                        Text(
                                            text = slotTierLabel(slot.id),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                                        )
                                    }
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text(
                                            text = if (slot.used) "IN USE" else "EMPTY",
                                            style = MaterialTheme.typography.labelMedium,
                                            color = if (slot.used) {
                                                MaterialTheme.colorScheme.primary
                                            } else {
                                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                                            }
                                        )
                                        Spacer(modifier = Modifier.height(4.dp))
                                        Text(
                                            text = "ctr ${slot.counter}",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                        )
                                    }
                                }
                            }
                            Spacer(modifier = Modifier.height(12.dp))
                        }

                        Button(
                            onClick = executeRecovery,
                            enabled = selectedSlotId != null,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Recover this slot")
                        }
                    } else if (recoveryStage == RecoveryStage.OWNER_PROOF) {
                        Spacer(modifier = Modifier.height(20.dp))
                        Button(
                            onClick = executeRecovery,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Continue to pairing")
                        }
                    }

                    Spacer(modifier = Modifier.height(20.dp))
                    if (recoveryStage == RecoveryStage.ERROR) {
                        Button(onClick = startRecovery) {
                            Text("Try again")
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                    }
                    OutlinedButton(onClick = resetRecovery) {
                        Text("Back to scan")
                    }
                }

                OnboardingStage.SUCCESS -> {
                    val success = provisioningSuccess ?: ProvisioningSuccess(
                        slotId = -1,
                        counter = 0u,
                        name = "",
                    )
                    Text(
                        text = "You're all set.",
                        style = MaterialTheme.typography.titleLarge,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = "The key has been stored in the secure keystore on this device.",
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f)
                    )
                    Spacer(modifier = Modifier.height(20.dp))
                    successOverviewSlots.forEach { slot ->
                        val isSelected = slot.id == success.slotId
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(18.dp),
                            color = if (isSelected) {
                                MaterialTheme.colorScheme.secondaryContainer
                            } else {
                                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
                            },
                            border = BorderStroke(
                                width = 1.dp,
                                color = if (isSelected) {
                                    MaterialTheme.colorScheme.secondary
                                } else {
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f)
                                }
                            )
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 18.dp, vertical = 14.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "Slot ${slot.id}",
                                        style = MaterialTheme.typography.titleSmall,
                                    )
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = if (slot.name.isBlank()) "Empty" else slot.name,
                                        style = MaterialTheme.typography.bodyMedium,
                                    )
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = slotTierLabel(slot.id),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                                    )
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(
                                        text = when {
                                            slot.id == 0 -> "KEY"
                                            isSelected -> "THIS PHONE"
                                            slot.used -> "ACTIVE"
                                            else -> "EMPTY"
                                        },
                                        style = MaterialTheme.typography.labelMedium,
                                        color = if (slot.used || slot.id == 0) {
                                            MaterialTheme.colorScheme.primary
                                        } else {
                                            MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                                        }
                                    )
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        text = if (slot.id == 0) "Hardware fob" else "Counter ${slot.counter}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                                    )
                                }
                            }
                        }
                        Spacer(modifier = Modifier.height(12.dp))
                    }
                    Spacer(modifier = Modifier.height(20.dp))
                    Button(onClick = onComplete) {
                        Text("Continue")
                    }
                }
            }
        }
    }
}

private fun recoverySessionStatus(sessionState: BleManagementSessionState): String {
    return when (sessionState.connectionState) {
        BleManagementSessionConnectionState.DISCONNECTED -> "Window Open detected. Starting management connection..."
        BleManagementSessionConnectionState.CONNECTING -> "Connecting to Guillemot over recovery GATT..."
        BleManagementSessionConnectionState.DISCOVERING -> "Enabling management characteristics..."
        BleManagementSessionConnectionState.READY -> "Management session ready. Fetching slots..."
        BleManagementSessionConnectionState.ERROR -> sessionState.lastError ?: "Management session failed."
    }
}

private fun buildSuccessOverviewSlots(
    selectedSlotId: Int,
    counter: UInt,
    name: String,
    knownSlots: List<BleManagementSlot>,
): List<BleManagementSlot> {
    return (0..3).map { slotId ->
        when {
            slotId == 0 -> BleManagementSlot(id = 0, used = true, counter = 0u, name = "Uguisu")
            slotId == selectedSlotId -> BleManagementSlot(
                id = slotId,
                used = true,
                counter = counter,
                name = name,
            )
            else -> knownSlots.firstOrNull { it.id == slotId }
                ?: BleManagementSlot(id = slotId, used = false, counter = 0u, name = "")
        }
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

private fun defaultRecoveredSlotName(slot: BleManagementSlot): String {
    if (slot.name.isNotBlank()) return slot.name

    return when (slot.id) {
        1 -> "Recovered owner phone"
        2, 3 -> "Recovered guest phone"
        else -> "Recovered phone"
    }
}

@Composable
private fun OnboardingImportAnimation(modifier: Modifier = Modifier) {
    val haptic = LocalHapticFeedback.current
    var animationStarted by remember { mutableStateOf(false) }
    val progress by animateFloatAsState(
        targetValue = if (animationStarted) 1f else 0f,
        animationSpec = tween(durationMillis = 1000),
        label = "successAnimation"
    )
    val particles = remember {
        List(12) { index ->
            val angle = (index.toFloat() / 12f) * (Math.PI.toFloat() * 2f)
            val radius = if (index % 2 == 0) 78f else 56f
            radius * cos(angle) to radius * sin(angle)
        }
    }

    LaunchedEffect(Unit) {
        animationStarted = true
        delay(780)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    Box(
        modifier = modifier
            .size(168.dp)
            .fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        particles.forEachIndexed { index, (offsetX, offsetY) ->
            val convergence = when {
                progress < 0.4f -> progress / 0.4f
                else -> 1f - ((progress - 0.4f) / 0.4f).coerceIn(0f, 1f)
            }
            val resolveAlpha = if (progress < 0.8f) 1f else 1f - ((progress - 0.8f) / 0.2f).coerceIn(0f, 1f)
            Surface(
                modifier = Modifier
                    .size(if (index % 3 == 0) 14.dp else 10.dp)
                    .graphicsLayer {
                        translationX = offsetX * convergence
                        translationY = offsetY * convergence
                        alpha = resolveAlpha
                        rotationZ = progress * 180f * if (index % 2 == 0) 1f else -1f
                    },
                shape = RoundedCornerShape(3.dp),
                color = if (progress < 0.55f) {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.9f)
                } else {
                    MaterialTheme.colorScheme.secondary
                }
            ) {}
        }

        Icon(
            imageVector = Icons.Default.VpnKey,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.secondary,
            modifier = Modifier
                .size(56.dp)
                .graphicsLayer {
                    val reveal = ((progress - 0.72f) / 0.28f).coerceIn(0f, 1f)
                    alpha = reveal
                    scaleX = 0.7f + (0.3f * reveal)
                    scaleY = 0.7f + (0.3f * reveal)
                }
        )
    }
}

private fun BleManagementResponseException.isPairingRequiredRecoveryError(): Boolean {
    val code = response.code?.lowercase().orEmpty()
    val message = response.message?.lowercase().orEmpty()
    return code == "locked" || "pairing" in message || "authentication" in message
}

package com.immogen.pipit.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.WifiTethering
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.immogen.core.ImmoCrypto
import com.immogen.core.KeyStoreManager
import com.immogen.pipit.BuildConfig
import com.immogen.pipit.ble.BleManagementConnectMode
import com.immogen.pipit.ble.BleManagementResponseException
import com.immogen.pipit.ble.BleManagementSessionConnectionState
import com.immogen.pipit.ble.BleManagementSessionState
import com.immogen.pipit.ble.BleManagementSlot
import com.immogen.pipit.ble.BleService
import com.immogen.pipit.ble.BleState
import com.immogen.pipit.onboarding.ProvisioningQrParseException
import com.immogen.pipit.onboarding.ProvisioningQrParser
import com.immogen.pipit.onboarding.ProvisioningQrPayload
import java.security.SecureRandom
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

// ── Colours matching iOS OnboardingMockup ─────────────────────────────────────

private val AccentBlue          = Color(0xFF0A84FF)
private val SuccessCardBg       = Color(0xFF262626)
private val SecondaryText       = Color.White.copy(alpha = 0.88f)
private val TertiaryText        = Color(0xFF8B8B91)
private val MutedText           = Color.White.copy(alpha = 0.26f)
private val DividerColor        = Color.White.copy(alpha = 0.10f)
private val InactiveBadgeBg     = Color(0xFFAAAAAB)

// ── Enums & data classes ──────────────────────────────────────────────────────

internal enum class RecoveryStage {
    INTRO,
    WAITING_FOR_WINDOW_OPEN,
    CONNECTING,
    LOADING_SLOTS,
    OWNER_PROOF,
    RECOVERING,
    SLOT_PICKER,
    ERROR,
}

internal enum class OnboardingStage {
    CAMERA,
    PIN,
    IMPORTING,
    LOCATION_PERMISSION,
    SUCCESS,
}

internal data class ProvisioningSuccess(
    val slotId: Int,
    val counter: UInt,
    val name: String,
)

internal data class PendingProvisioningMaterial(
    val slotId: Int,
    val key: ByteArray,
    val counter: UInt,
    val name: String,
    val statusText: String,
)

// ── Main onboarding composable ────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingPlaceholderView(
    bleState: BleState,
    bleService: BleService?,
    onComplete: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val context = LocalContext.current
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
    var isRecoverySheetOpen by remember { mutableStateOf(false) }
    var lastScannedQrPayload by remember { mutableStateOf<String?>(null) }

    val recoverySheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // Location permission launcher (Android Q+ only)
    val locationPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {
        onboardingStage = OnboardingStage.SUCCESS
    }

    fun shouldAskLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) != PackageManager.PERMISSION_GRANTED
    }

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
        onboardingStage = if (shouldAskLocationPermission()) {
            OnboardingStage.LOCATION_PERMISSION
        } else {
            OnboardingStage.SUCCESS
        }
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
        isRecoverySheetOpen = false
        coroutineScope.launch {
            runCatching { bleService?.managementTransport?.disconnect() }
        }
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
        isRecoverySheetOpen = true
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

    LaunchedEffect(bleState.isWindowOpen, recoveryStage, isRecoverySheetOpen, bleService) {
        if (!isRecoverySheetOpen ||
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
                isRecoverySheetOpen = false
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
                    recoveryError = "Pairing failed. Check the 6-digit Guillemot PIN and try again."
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

        lastScannedQrPayload = rawValue
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

    val debugInjectQr: (String) -> Unit = { rawValue ->
        if (BuildConfig.DEBUG) {
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
            onboardingStage = OnboardingStage.CAMERA
            handleQrValue(rawValue)
        }
    }

    // ── Root: full-screen black ───────────────────────────────────────────────

    Box(modifier = Modifier
        .fillMaxSize()
        .background(Color.Black)
    ) {
        AnimatedContent(
            targetState = onboardingStage,
            transitionSpec = {
                (fadeIn(tween(240)) + slideInVertically(tween(240)) { it / 4 }) togetherWith
                (fadeOut(tween(200)) + slideOutVertically(tween(200)) { -it / 4 })
            },
            label = "onboardingStage",
        ) { stage ->
            when (stage) {

                // ── CAMERA ───────────────────────────────────────────────────
                OnboardingStage.CAMERA -> {
                    CameraStage(
                        scanLocked = scanLocked,
                        scanError = scanError,
                        onQrDetected = handleQrValue,
                        onRecoveryClick = startRecovery,
                        onDebugInjectQr = debugInjectQr,
                        keyStoreManager = keyStoreManager,
                        context = context,
                    )
                }

                // ── PIN ──────────────────────────────────────────────────────
                OnboardingStage.PIN -> {
                    PinStage(
                        pin = pin,
                        onPinChange = { pin = it.filter(Char::isDigit).take(6); pinError = null },
                        pinError = pinError,
                        isSubmitting = isSubmittingPin,
                        onConfirm = {
                            val payload = encryptedPayload ?: return@PinStage
                            if (isSubmittingPin) return@PinStage
                            isSubmittingPin = true
                            pinError = null
                            coroutineScope.launch {
                                try {
                                    if (!ImmoCrypto.isInitialized()) ImmoCrypto.initialize()
                                    val decryptedKey = if (BuildConfig.DEBUG &&
                                        pin == "123456" &&
                                        payload.salt.size == 16 &&
                                        payload.encryptedKey.size == 24
                                    ) {
                                        ByteArray(16) { 0x42.toByte() }
                                    } else {
                                        ImmoCrypto.decryptProvisionedKey(
                                            pin = pin,
                                            salt = payload.salt,
                                            encryptedKey = payload.encryptedKey,
                                        )
                                    }
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
                        onCancel = returnToCamera,
                    )
                }

                // ── IMPORTING ────────────────────────────────────────────────
                OnboardingStage.IMPORTING -> {
                    ImportingStage(lastScannedQrPayload = lastScannedQrPayload)
                }

                // ── LOCATION PERMISSION ──────────────────────────────────────
                OnboardingStage.LOCATION_PERMISSION -> {
                    LocationPermissionStage(
                        onEnable = {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                locationPermLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                            } else {
                                onboardingStage = OnboardingStage.SUCCESS
                            }
                        },
                        onSkip = { onboardingStage = OnboardingStage.SUCCESS },
                    )
                }

                // ── SUCCESS ──────────────────────────────────────────────────
                OnboardingStage.SUCCESS -> {
                    SuccessStage(
                        overviewSlots = successOverviewSlots,
                        provisioningSuccess = provisioningSuccess,
                        onComplete = onComplete,
                    )
                }
            }
        }

        // Recovery bottom sheet — presented over the camera stage
        if (isRecoverySheetOpen) {
            ModalBottomSheet(
                onDismissRequest = resetRecovery,
                sheetState = recoverySheetState,
                containerColor = Color(0xFF1C1C1E),
                contentColor = Color.White,
            ) {
                RecoverySheetContent(
                    recoveryStage = recoveryStage,
                    recoverySlots = recoverySlots,
                    selectedSlotId = selectedSlotId,
                    recoveryError = recoveryError,
                    sessionState = sessionState,
                    onSelectSlot = { selectedSlotId = it },
                    onExecuteRecovery = executeRecovery,
                    onRetry = startRecovery,
                    onClose = resetRecovery,
                    debugInjectQr = debugInjectQr,
                )
            }
        }
    }
}

// ── Camera stage ──────────────────────────────────────────────────────────────

@Composable
private fun CameraStage(
    scanLocked: Boolean,
    scanError: String?,
    onQrDetected: (String) -> Unit,
    onRecoveryClick: () -> Unit,
    onDebugInjectQr: (String) -> Unit,
    keyStoreManager: KeyStoreManager,
    context: android.content.Context,
) {
    Box(modifier = Modifier.fillMaxSize()) {
        // Camera preview — fills entire screen
        ProvisioningQrScannerView(
            modifier = Modifier.fillMaxSize(),
            enabled = !scanLocked,
            onQrDetected = onQrDetected,
        )

        // Top gradient (reduces scan zone contrast)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(210.dp)
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.68f),
                            Color.Black.copy(alpha = 0.18f),
                            Color.Transparent,
                        )
                    )
                )
                .align(Alignment.TopCenter),
        )

        // Bottom gradient (improves label readability)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(320.dp)
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.14f),
                            Color.Black.copy(alpha = 0.82f),
                        )
                    )
                )
                .align(Alignment.BottomCenter),
        )

        // Cutout scrim — semi-transparent overlay with transparent rounded-rect hole
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
        ) {
            drawRect(color = Color.Black.copy(alpha = 0.52f))
            val cutoutPx = 246.dp.toPx()
            drawRoundRect(
                color = Color.Transparent,
                topLeft = Offset((size.width - cutoutPx) / 2f, (size.height - cutoutPx) / 2f),
                size = Size(cutoutPx, cutoutPx),
                cornerRadius = CornerRadius(34.dp.toPx()),
                blendMode = BlendMode.Clear,
            )
        }

        // "Pipit" app title — top center
        Text(
            text = "Pipit",
            style = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold),
            color = Color.White,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 52.dp),
        )

        // "Scan from Whimbrel" label — just below the cutout
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Offset below cutout: half-screen height + cutout/2 + 20dp gap
            Spacer(modifier = Modifier.weight(1f))
            // Reserve space for the cutout itself
            Spacer(modifier = Modifier.height(123.dp + 20.dp)) // 246/2 + gap

            if (scanError != null) {
                Box(
                    modifier = Modifier
                        .background(Color.Black.copy(alpha = 0.48f), RoundedCornerShape(14.dp))
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                ) {
                    Text(
                        text = scanError,
                        style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                        color = Color.Red.copy(alpha = 0.92f),
                        textAlign = TextAlign.Center,
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
            }

            Text(
                text = "Scan from Whimbrel",
                style = TextStyle(fontSize = 23.sp, fontWeight = FontWeight.Bold),
                color = Color.White,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.weight(1f))
        }

        // "Forgot your old phone?" link — bottom center
        TextButton(
            onClick = onRecoveryClick,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 32.dp),
        ) {
            Text(
                text = "Forgot your old phone?",
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Medium),
                color = AccentBlue,
            )
        }

        // Debug wrench menu — top trailing corner
        if (BuildConfig.DEBUG) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(end = 16.dp, top = 52.dp),
                contentAlignment = Alignment.TopEnd,
            ) {
                var wrenchExpanded by remember { mutableStateOf(false) }
                IconButton(onClick = { wrenchExpanded = true }) {
                    Icon(
                        imageVector = Icons.Default.Build,
                        contentDescription = "Debug menu",
                        tint = Color.White,
                    )
                }
                DropdownMenu(
                    expanded = wrenchExpanded,
                    onDismissRequest = { wrenchExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("Simulate guest QR (slot 3)") },
                        onClick = {
                            wrenchExpanded = false
                            onDebugInjectQr("immogen://prov?slot=3&ctr=0&key=00112233445566778899aabbccddeeff&name=Guest%20Android")
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Simulate owner QR (slot 1)") },
                        onClick = {
                            wrenchExpanded = false
                            onDebugInjectQr("immogen://prov?slot=1&ctr=0&salt=00112233445566778899aabbccddeeff&ekey=00112233445566778899aabbccddeeff0011223344556677&name=Owner%20Android")
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Hard reset app and permissions") },
                        onClick = {
                            wrenchExpanded = false
                            for (slotId in 0..3) { runCatching { keyStoreManager.deleteKey(slotId) } }
                            context.getSharedPreferences("debug_sim_transport", android.content.Context.MODE_PRIVATE)
                                .edit().clear().apply()
                            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                            if (launchIntent != null) {
                                context.startActivity(Intent.makeRestartActivityTask(launchIntent.component))
                            }
                            Runtime.getRuntime().exit(0)
                        },
                    )
                }
            }
        }
    }
}

// ── PIN stage ─────────────────────────────────────────────────────────────────

@Composable
private fun PinStage(
    pin: String,
    onPinChange: (String) -> Unit,
    pinError: String?,
    isSubmitting: Boolean,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        delay(200)
        runCatching { focusRequester.requestFocus() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            Icon(
                imageVector = Icons.Default.VpnKey,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(40.dp),
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = "Enter PIN",
                style = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Bold),
                color = Color.White,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "The 6-digit PIN set during Guillemot setup.",
                style = TextStyle(fontSize = 16.sp),
                color = Color.White.copy(alpha = 0.55f),
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(44.dp))

            // Hidden text input capturing key events; visual boxes drawn below
            Box {
                BasicTextField(
                    value = pin,
                    onValueChange = { onPinChange(it) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .alpha(0.0001f) // invisible but focusable
                        .focusRequester(focusRequester),
                    textStyle = TextStyle(color = Color.Transparent),
                    singleLine = true,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.align(Alignment.Center),
                ) {
                    repeat(6) { index ->
                        PinDigitBox(filled = index < pin.length)
                    }
                }
            }

            if (pinError != null) {
                Spacer(modifier = Modifier.height(14.dp))
                Text(
                    text = pinError,
                    style = TextStyle(fontSize = 14.sp),
                    color = Color.Red.copy(alpha = 0.85f),
                    textAlign = TextAlign.Center,
                )
            } else {
                Spacer(modifier = Modifier.height(30.dp))
            }

            Spacer(modifier = Modifier.height(32.dp))

            if (isSubmitting) {
                CircularProgressIndicator(color = Color.White)
            } else {
                Button(
                    onClick = onConfirm,
                    enabled = pin.length == 6,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(58.dp),
                    shape = RoundedCornerShape(19.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (pin.length == 6) AccentBlue else Color.White.copy(alpha = 0.16f),
                        contentColor = Color.White,
                        disabledContainerColor = Color.White.copy(alpha = 0.16f),
                        disabledContentColor = Color.White.copy(alpha = 0.5f),
                    ),
                ) {
                    Text(
                        text = "Continue",
                        style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold),
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            TextButton(
                onClick = onCancel,
                enabled = !isSubmitting,
            ) {
                Text(
                    text = "Cancel",
                    style = TextStyle(fontSize = 17.sp),
                    color = Color.White.copy(alpha = 0.55f),
                )
            }
            Spacer(modifier = Modifier.height(44.dp))
        }
    }
}

@Composable
private fun PinDigitBox(filled: Boolean) {
    Box(
        modifier = Modifier
            .size(width = 46.dp, height = 56.dp)
            .background(
                color = if (filled) Color.White.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.07f),
                shape = RoundedCornerShape(11.dp),
            )
            .border(
                width = if (filled) 1.5.dp else 1.dp,
                color = if (filled) Color.White.copy(alpha = 0.75f) else Color.White.copy(alpha = 0.18f),
                shape = RoundedCornerShape(11.dp),
            ),
        contentAlignment = Alignment.Center,
    ) {
        if (filled) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .background(Color.White, CircleShape),
            )
        }
    }
}

// ── Importing stage ───────────────────────────────────────────────────────────

@Composable
private fun ImportingStage(lastScannedQrPayload: String?) {
    val haptic = LocalHapticFeedback.current
    val qrBitmap = remember(lastScannedQrPayload) {
        lastScannedQrPayload?.let { generateQrBitmapOnboarding(it) }
    }

    LaunchedEffect(Unit) {
        delay(900)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(88.dp))
            if (qrBitmap != null) {
                Image(
                    bitmap = qrBitmap.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier
                        .size(378.dp)
                        .background(Color.White, RoundedCornerShape(2.dp)),
                )
            } else {
                Icon(
                    imageVector = Icons.Default.VpnKey,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(120.dp),
                )
            }
            Spacer(modifier = Modifier.height(36.dp))
            Text(
                text = "Decoding\u2026",
                style = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.SemiBold),
                color = Color.White.copy(alpha = 0.80f),
            )
            Spacer(modifier = Modifier.weight(1f))
        }
    }
}

// ── Location permission stage ─────────────────────────────────────────────────

@Composable
private fun LocationPermissionStage(
    onEnable: () -> Unit,
    onSkip: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(110.dp))

            Icon(
                imageVector = Icons.Outlined.WifiTethering,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(74.dp),
            )
            Spacer(modifier = Modifier.height(34.dp))

            Text(
                text = "Proximity Unlock",
                style = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.SemiBold),
                color = Color.White,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(40.dp))

            Column(
                modifier = Modifier.padding(horizontal = 44.dp),
                verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                Text(
                    "Pipit can automatically unlock your vehicle when you walk up to it.",
                    style = TextStyle(fontSize = 17.sp),
                    color = SecondaryText,
                    textAlign = TextAlign.Center,
                )
                Text(
                    "This requires \"Always Allow\" location access so the app can detect your vehicle in the background.",
                    style = TextStyle(fontSize = 17.sp),
                    color = SecondaryText,
                    textAlign = TextAlign.Center,
                )
                Text(
                    "Your location is never stored or transmitted.",
                    style = TextStyle(fontSize = 17.sp),
                    color = SecondaryText,
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Button(
                onClick = onEnable,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp)
                    .height(58.dp),
                shape = RoundedCornerShape(19.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = AccentBlue,
                    contentColor = Color.White,
                ),
            ) {
                Text(
                    text = "Enable Proximity",
                    style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold),
                )
            }
            Spacer(modifier = Modifier.height(18.dp))
            TextButton(onClick = onSkip) {
                Text(
                    text = "Skip for Now",
                    style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Medium),
                    color = AccentBlue,
                )
            }
            Spacer(modifier = Modifier.height(34.dp))
        }
    }
}

// ── Success stage ─────────────────────────────────────────────────────────────

@Composable
private fun SuccessStage(
    overviewSlots: List<BleManagementSlot>,
    provisioningSuccess: ProvisioningSuccess?,
    onComplete: () -> Unit,
) {
    val success = provisioningSuccess ?: ProvisioningSuccess(slotId = -1, counter = 0u, name = "")

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(72.dp))

            Icon(
                imageVector = Icons.Outlined.CheckCircle,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(72.dp),
            )
            Spacer(modifier = Modifier.height(22.dp))
            Text(
                text = "All set!",
                style = TextStyle(fontSize = 31.sp, fontWeight = FontWeight.SemiBold),
                color = Color.White,
            )
            Spacer(modifier = Modifier.height(18.dp))

            DarkSlotCard(slots = overviewSlots, activeSlotId = success.slotId)

            Spacer(modifier = Modifier.weight(1f))

            Button(
                onClick = onComplete,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 48.dp)
                    .height(47.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = AccentBlue,
                    contentColor = Color.White,
                ),
            ) {
                Text(
                    text = "Done",
                    style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
                )
            }
            Spacer(modifier = Modifier.height(76.dp))
        }
    }
}

@Composable
private fun DarkSlotCard(slots: List<BleManagementSlot>, activeSlotId: Int) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(SuccessCardBg, RoundedCornerShape(21.dp))
            .padding(vertical = 0.dp),
    ) {
        slots.forEachIndexed { index, slot ->
            val isActive = slot.id == activeSlotId || slot.id == 0
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = 14.dp,
                        end = 20.dp,
                        top = 14.dp,
                        bottom = if (slot.id == 0) 14.dp else 2.dp,
                    ),
                verticalAlignment = Alignment.Top,
            ) {
                // "SLOT N" label column
                Text(
                    text = "SLOT ${slot.id + 1}",
                    style = TextStyle(fontSize = 11.sp),
                    color = MutedText,
                    modifier = Modifier
                        .width(44.dp)
                        .padding(top = 4.dp),
                )
                Spacer(modifier = Modifier.width(12.dp))
                // Name + tier badge
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    val displayName = if (slot.name.isBlank()) {
                        if (slot.id == 0) "Uguisu" else if (slot.used) "In use" else "Empty"
                    } else {
                        slot.name
                    }
                    Text(
                        text = displayName,
                        style = TextStyle(
                            fontSize = 16.sp,
                            fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Medium,
                        ),
                        color = if (isActive) Color.White else TertiaryText,
                    )
                    val tierLabel = slotTierLabel(slot.id)
                    Box(
                        modifier = Modifier
                            .background(
                                if (isActive) AccentBlue else InactiveBadgeBg,
                                RoundedCornerShape(50),
                            )
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Text(
                            text = tierLabel,
                            style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
                            color = Color.White,
                        )
                    }
                    if (slot.id != 0 && slot.used) {
                        Text(
                            text = "Counter ${slot.counter}",
                            style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
                            color = if (isActive) SecondaryText else MutedText,
                        )
                    } else if (slot.id == 0) {
                        Text(
                            text = "Hardware fob",
                            style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
                            color = SecondaryText,
                        )
                    }
                }
                // Checkmark for current device
                if (slot.id == activeSlotId) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Icon(
                        imageVector = Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        tint = AccentBlue,
                        modifier = Modifier.size(22.dp).padding(top = 4.dp),
                    )
                }
            }
            if (index < slots.size - 1) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(0.5.dp)
                        .background(DividerColor),
                )
            }
        }
    }
}

// ── Recovery sheet content ────────────────────────────────────────────────────

@Composable
private fun RecoverySheetContent(
    recoveryStage: RecoveryStage,
    recoverySlots: List<BleManagementSlot>,
    selectedSlotId: Int?,
    recoveryError: String?,
    sessionState: BleManagementSessionState,
    onSelectSlot: (Int) -> Unit,
    onExecuteRecovery: () -> Unit,
    onRetry: () -> Unit,
    onClose: () -> Unit,
    debugInjectQr: (String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Header row
        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "Recover Phone Key",
                style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
                color = Color.White,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                // Debug menu (debug builds only, left side)
                if (BuildConfig.DEBUG) {
                    var wrenchExpanded by remember { mutableStateOf(false) }
                    Box {
                        IconButton(onClick = { wrenchExpanded = true }) {
                            Icon(
                                imageVector = Icons.Default.Build,
                                contentDescription = "Debug",
                                tint = Color.White.copy(alpha = 0.6f),
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        DropdownMenu(
                            expanded = wrenchExpanded,
                            onDismissRequest = { wrenchExpanded = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Simulate guest QR (slot 3)") },
                                onClick = {
                                    wrenchExpanded = false
                                    debugInjectQr("immogen://prov?slot=3&ctr=0&key=00112233445566778899aabbccddeeff&name=Guest%20Android")
                                },
                            )
                        }
                    }
                } else {
                    Spacer(modifier = Modifier.size(48.dp))
                }

                // Close button (right side)
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .background(Color.White.copy(alpha = 0.15f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    IconButton(
                        onClick = onClose,
                        modifier = Modifier.size(38.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Close",
                            tint = Color.White.copy(alpha = 0.62f),
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Non-interactive 3D fob demo
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(280.dp),
        ) {
            FobViewer(
                buttonDepth = 0f,
                modelRotation = Triple(0f, -0.4f, 0f),
                recoveryDemoLoop = true,
                onWebViewCreated = {},
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Recovery status UI
        when (recoveryStage) {
            RecoveryStage.INTRO, RecoveryStage.WAITING_FOR_WINDOW_OPEN,
            RecoveryStage.CONNECTING, RecoveryStage.LOADING_SLOTS -> {
                Text(
                    text = "Press the button three times on your Uguisu fob to begin recovery.",
                    style = TextStyle(fontSize = 15.sp),
                    color = Color.White.copy(alpha = 0.88f),
                    textAlign = TextAlign.Center,
                )
                Spacer(modifier = Modifier.height(20.dp))
                CircularProgressIndicator(color = Color.White, modifier = Modifier.size(28.dp))
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = when (recoveryStage) {
                        RecoveryStage.WAITING_FOR_WINDOW_OPEN -> "Scanning for Window Open beacon\u2026"
                        RecoveryStage.CONNECTING -> recoverySessionStatus(sessionState)
                        RecoveryStage.LOADING_SLOTS -> "Loading slot inventory\u2026"
                        else -> ""
                    },
                    style = TextStyle(fontSize = 14.sp),
                    color = Color.White.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center,
                )
            }

            RecoveryStage.SLOT_PICKER -> {
                Text(
                    text = "Select the slot you want to restore to this phone.",
                    style = TextStyle(fontSize = 15.sp),
                    color = Color.White.copy(alpha = 0.88f),
                    textAlign = TextAlign.Center,
                )
                Spacer(modifier = Modifier.height(12.dp))
                recoverySlots.forEach { slot ->
                    val isSelected = selectedSlotId == slot.id
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                            .background(
                                if (isSelected) AccentBlue.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.08f),
                                RoundedCornerShape(16.dp),
                            )
                            .border(
                                width = 1.dp,
                                color = if (isSelected) AccentBlue else Color.White.copy(alpha = 0.12f),
                                shape = RoundedCornerShape(16.dp),
                            )
                            .pointerInput(slot.id) {
                                detectTapGestures { if (slot.used) onSelectSlot(slot.id) }
                            }
                            .padding(horizontal = 18.dp, vertical = 12.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Slot ${slot.id}",
                                    style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
                                    color = Color.White,
                                )
                                Text(
                                    text = if (slot.used) slot.name.ifBlank { "In use" } else "Empty",
                                    style = TextStyle(fontSize = 13.sp),
                                    color = Color.White.copy(alpha = 0.6f),
                                )
                            }
                            Text(
                                text = slotTierLabel(slot.id),
                                style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
                                color = if (isSelected) AccentBlue else Color.White.copy(alpha = 0.5f),
                            )
                        }
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
                Button(
                    onClick = onExecuteRecovery,
                    enabled = selectedSlotId != null,
                    modifier = Modifier.fillMaxWidth().height(58.dp),
                    shape = RoundedCornerShape(19.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
                ) {
                    Text("Recover this slot", style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold), color = Color.White)
                }
            }

            RecoveryStage.OWNER_PROOF -> {
                Text(
                    text = "Recovering Slot 1 requires BLE owner proof. Android will show a Bluetooth pairing prompt. Enter the 6-digit Guillemot PIN to authorize.",
                    style = TextStyle(fontSize = 15.sp),
                    color = Color.White.copy(alpha = 0.88f),
                    textAlign = TextAlign.Center,
                )
                if (recoveryError != null) {
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = recoveryError,
                        style = TextStyle(fontSize = 14.sp),
                        color = Color.Red.copy(alpha = 0.92f),
                        textAlign = TextAlign.Center,
                    )
                }
                Spacer(modifier = Modifier.height(16.dp))
                Button(
                    onClick = onExecuteRecovery,
                    modifier = Modifier.fillMaxWidth().height(58.dp),
                    shape = RoundedCornerShape(19.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
                ) {
                    Text("Continue to pairing", style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold), color = Color.White)
                }
            }

            RecoveryStage.RECOVERING -> {
                CircularProgressIndicator(color = Color.White, modifier = Modifier.size(28.dp))
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = selectedSlotId?.let { "Recovering slot $it\u2026" } ?: "Recovering\u2026",
                    style = TextStyle(fontSize = 14.sp),
                    color = Color.White.copy(alpha = 0.7f),
                    textAlign = TextAlign.Center,
                )
            }

            RecoveryStage.ERROR -> {
                Text(
                    text = recoveryError ?: "Recovery failed.",
                    style = TextStyle(fontSize = 15.sp),
                    color = Color.Red.copy(alpha = 0.92f),
                    textAlign = TextAlign.Center,
                )
                Spacer(modifier = Modifier.height(16.dp))
                Button(
                    onClick = onRetry,
                    modifier = Modifier.fillMaxWidth().height(58.dp),
                    shape = RoundedCornerShape(19.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
                ) {
                    Text("Try again", style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold), color = Color.White)
                }
            }
        }
    }
}

// ── Helper functions ──────────────────────────────────────────────────────────

private fun recoverySessionStatus(sessionState: BleManagementSessionState): String {
    return when (sessionState.connectionState) {
        BleManagementSessionConnectionState.DISCONNECTED -> "Window Open detected. Starting management connection\u2026"
        BleManagementSessionConnectionState.CONNECTING -> "Connecting over recovery GATT\u2026"
        BleManagementSessionConnectionState.DISCOVERING -> "Enabling management characteristics\u2026"
        BleManagementSessionConnectionState.READY -> "Management session ready. Fetching slots\u2026"
        BleManagementSessionConnectionState.ERROR -> sessionState.lastError ?: "Management session failed."
    }
}

internal fun buildSuccessOverviewSlots(
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

internal fun slotTierLabel(slotId: Int): String {
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

internal fun BleManagementResponseException.isPairingRequiredRecoveryError(): Boolean {
    val code = response.code?.lowercase().orEmpty()
    val message = response.message?.lowercase().orEmpty()
    return code == "locked" || "pairing" in message || "authentication" in message
}

private fun generateQrBitmapOnboarding(payload: String, size: Int = 768): Bitmap {
    val matrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, size, size)
    val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
    for (x in 0 until size) {
        for (y in 0 until size) {
            bitmap.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
        }
    }
    return bitmap
}

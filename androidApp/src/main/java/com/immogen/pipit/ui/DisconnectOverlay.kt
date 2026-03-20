package com.immogen.pipit.ui

import android.content.Intent
import android.os.Build
import android.provider.Settings
import com.immogen.pipit.BuildConfig
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BluetoothDisabled
import androidx.compose.material.icons.filled.BluetoothSearching
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.immogen.pipit.ble.BleState
import com.immogen.pipit.ble.ConnectionState
import kotlinx.coroutines.delay

private const val DEV_BYPASS_OVERLAY_KEY = "DEV_BYPASS_OVERLAY"
private const val DEV_BYPASS_PREFS_NAME  = "debug_sim_transport"

@Composable
internal fun DisconnectOverlay(
    bleState: BleState,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    // Debug: "DEV: Bypass Overlay" button sets this flag so the overlay hides itself
    // (mirrors iOS DisconnectOverlaySwiftUIView + RootView DEV_BYPASS_OVERLAY UserDefaults key).
    var devBypass by remember {
        mutableStateOf(
            if (BuildConfig.DEBUG)
                context.getSharedPreferences(DEV_BYPASS_PREFS_NAME, android.content.Context.MODE_PRIVATE)
                    .getBoolean(DEV_BYPASS_OVERLAY_KEY, false)
            else false
        )
    }

    val isBluetoothOff = !bleState.isBluetoothEnabled
    val showOverlay = !devBypass && (
        bleState.connectionState == ConnectionState.DISCONNECTED ||
        bleState.connectionState == ConnectionState.SCANNING
    )

    // Scrim: simple 200ms fade (matches iOS overlay timing)
    val scrimAlpha by animateFloatAsState(
        targetValue = if (showOverlay) 1f else 0f,
        animationSpec = tween(200),
        label = "scrimAlpha",
    )

    // Content: spring entry (scale 0.88→1.0, opacity 0→1) matching iOS response:0.45 dampingFraction:0.75
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(showOverlay) {
        if (showOverlay) { delay(16); appeared = true } else appeared = false
    }
    val contentScale by animateFloatAsState(
        targetValue = if (appeared) 1f else 0.88f,
        animationSpec = spring(dampingRatio = 0.75f, stiffness = Spring.StiffnessMedium),
        label = "contentScale",
    )
    val contentAlpha by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.75f, stiffness = Spring.StiffnessMedium),
        label = "contentAlpha",
    )

    // Pulsing ring: 1.8s EaseInOut with 300ms start delay (matches iOS)
    val infiniteTransition = rememberInfiniteTransition(label = "btPulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.18f,
        animationSpec = infiniteRepeatable(
            animation = tween(1800, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseScale",
    )
    var pulseActive by remember { mutableStateOf(false) }
    LaunchedEffect(showOverlay) {
        pulseActive = false
        if (showOverlay) { delay(300); pulseActive = true }
    }

    val view = LocalView.current

    if (scrimAlpha > 0f) {
        Box(
            modifier = modifier
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.92f * scrimAlpha))
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {
                    // Error haptic on scrim tap (matches iOS UINotificationFeedbackGenerator .error)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        view.performHapticFeedback(HapticFeedbackConstants.REJECT)
                    } else {
                        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp),
                modifier = Modifier.graphicsLayer {
                    scaleX = contentScale
                    scaleY = contentScale
                    alpha  = contentAlpha
                },
            ) {
                val iconColor = if (isBluetoothOff)
                    Color(0xFFFF9500) // iOS .orange
                else
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)

                Box(contentAlignment = Alignment.Center) {
                    // Pulsing outer ring
                    Box(
                        modifier = Modifier
                            .size(88.dp)
                            .graphicsLayer {
                                val s = if (pulseActive) pulseScale else 1f
                                scaleX = s; scaleY = s
                            }
                            .background(iconColor.copy(alpha = 0.12f), CircleShape),
                    )
                    Icon(
                        imageVector = if (isBluetoothOff)
                            Icons.Default.BluetoothDisabled
                        else
                            Icons.Default.BluetoothSearching,
                        contentDescription = null,
                        tint = iconColor,
                        modifier = Modifier.size(34.dp),
                    )
                }

                // Status text
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = if (isBluetoothOff) "Bluetooth Off" else "Not Connected",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        text = if (isBluetoothOff)
                            "Enable Bluetooth to connect to Uguisu."
                        else
                            "Searching for Uguisu nearby\u2026",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 40.dp),
                    )
                }

                // "Open Settings" — only shown when Bluetooth is off (matches iOS)
                if (isBluetoothOff) {
                    OutlinedButton(
                        onClick = {
                            context.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        },
                    ) {
                        Icon(
                            imageVector = Icons.Default.Settings,
                            contentDescription = null,
                            modifier = Modifier
                                .size(18.dp)
                                .padding(end = 4.dp),
                        )
                        Text("Open Settings")
                    }
                }
            }

            // DEV: Bypass Overlay button — pinned to bottom of scrim, debug builds only
            // (mirrors iOS DisconnectOverlaySwiftUIView ZStack bottom VStack button)
            if (BuildConfig.DEBUG) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(bottom = 52.dp),
                    contentAlignment = Alignment.BottomCenter,
                ) {
                    TextButton(
                        onClick = {
                            context.getSharedPreferences(DEV_BYPASS_PREFS_NAME, android.content.Context.MODE_PRIVATE)
                                .edit().putBoolean(DEV_BYPASS_OVERLAY_KEY, true).apply()
                            devBypass = true
                        },
                    ) {
                        Text(
                            text = "DEV: Bypass Overlay",
                            color = Color(0xFFFFCC00),
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }
        }
    }
}

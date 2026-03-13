package com.immogen.pipit.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.immogen.pipit.ble.BleState
import com.immogen.pipit.ble.BleService
import com.immogen.pipit.ble.ConnectionState

@Composable
fun PipitApp(
    bleState: BleState,
    bleService: BleService?,
    onRequestUnlock: () -> Unit,
    onRequestLock: () -> Unit
) {
    var showSettings by remember { mutableStateOf(false) }
    var showOnboarding by remember { mutableStateOf(false) }
    var hintDismissed by remember { mutableStateOf(false) }
    var lockHintDismissed by remember { mutableStateOf(false) }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = showSettings,
            label = "settingsTransition"
        ) { isSettings ->
            if (isSettings) {
                SettingsPlaceholderView(onClose = { showSettings = false })
            } else {
                HomeScreen(
                bleState = bleState,
                onGearClick = { showSettings = true },
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
                        tryAwaitRelease()
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
    onComplete: () -> Unit
) {
    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "Onboarding",
                style = MaterialTheme.typography.headlineMedium
            )
            Text(
                text = "Placeholder — Agent 7 will populate.",
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(modifier = Modifier.weight(1f))
            androidx.compose.material3.Button(onClick = onComplete) {
                Text("Done")
            }
        }
    }
}

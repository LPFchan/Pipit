package com.immogen.pipit.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback

/**
 * 3D fob view using Three.js (via WebView). Loads Uguisu.glb,
 * maps tap = unlock and long-press = lock, and animates button depression.
 */
@Composable
fun Fob3DView(
    onTap: () -> Unit,
    onLongPress: () -> Unit,
    modifier: Modifier = Modifier
) {
    val haptic = LocalHapticFeedback.current
    var pressed by remember { mutableStateOf(false) }
    val depressTarget by animateFloatAsState(
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
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        onLongPress()
                    }
                )
            }
    ) {
        FobViewer(
            ledColor = Color.Green,
            isActive = true, // Always active — vehicle in range
            ledBrightness = 1.0f,
            buttonDepth = depressTarget,
            // Slight model rotation to show best angle by default
            modelRotation = Triple(0f, -0.4f, 0f)
        )
    }
}

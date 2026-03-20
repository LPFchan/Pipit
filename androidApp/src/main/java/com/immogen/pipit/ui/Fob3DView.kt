package com.immogen.pipit.ui

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import android.webkit.WebView
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Interactive 3D fob view matching iOS FobInteractiveViewer behaviour:
 *
 * - Single tap (or double-tap) → unlock + green LED flash
 * - 3+ taps within 400 ms window → rainbow LED (window open signal)
 * - 500 ms long-press → lock + red LED flash
 * - Drag (> 24 dp, outside button zone and nav bar zone) → camera orbit
 * - Pinch → camera zoom
 * - Button depression animates 80 ms EaseOut on press, 150 ms EaseIn on release
 *
 * Gesture orbit sensitivity: 0.006 rad/px (matches iOS).
 * Haptics: light on press-down, medium on tap confirm, heavy on long-press.
 */
@Composable
fun Fob3DView(
    onTap: () -> Unit,
    onLongPress: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val view = LocalView.current
    val density = LocalDensity.current
    val navBarBottomPx = WindowInsets.navigationBars.getBottom(density)
    val handler = remember { Handler(Looper.getMainLooper()) }

    // WebView reference captured from FobViewer after creation
    var webViewRef by remember { mutableStateOf<WebView?>(null) }

    // Generation counter to discard stale async raycast results
    var hitTestGen by remember { mutableIntStateOf(0) }

    // Multi-tap accumulator; LaunchedEffect fires the action 400 ms after last tap
    var tapCount by remember { mutableIntStateOf(0) }

    // Button visual state — drives buttonDepth in FobViewer
    var pressed by remember { mutableStateOf(false) }
    val pressDepth by animateFloatAsState(
        targetValue = if (pressed) 1f else 0f,
        animationSpec = if (pressed) tween(80, easing = EaseOut)
                        else        tween(150, easing = EaseIn),
        label = "buttonDepth",
    )

    // 400 ms multi-tap window — restarts on every tap increment
    LaunchedEffect(tapCount) {
        if (tapCount == 0) return@LaunchedEffect
        delay(400L)
        val count = tapCount
        tapCount = 0
        val wv = webViewRef ?: return@LaunchedEffect
        if (count >= 3) {
            // 3+ taps → window (rainbow) command; no unlock callback (matches iOS)
            wv.evaluateJavascript("window.playLedWindow()", null)
        } else {
            wv.evaluateJavascript("window.playLedUnlock()", null)
            onTap()
        }
    }

    Box(
        modifier = modifier.pointerInput(webViewRef, navBarBottomPx) {
            // Constants matching iOS FobInteractiveViewer
            val orbitThresholdPx = with(density) { 24.dp.toPx() }
            val navZoneExtraPx   = with(density) { 32.dp.toPx() }

            awaitEachGesture {
                val down    = awaitFirstDown(requireUnconsumed = false)
                val gen     = ++hitTestGen
                val downPos = down.position

                // Press-down haptic (light — press feedback)
                haptic(view, HapticFeedbackConstants.VIRTUAL_KEY)
                pressed = true

                // Async raycast: assume button zone until JS responds.
                // Conservatively suppresses orbit when touch originates on the button.
                var buttonZone = true
                webViewRef?.let { wv ->
                    val nx = (downPos.x / size.width).coerceIn(0f, 1f)
                    val ny = (downPos.y / size.height).coerceIn(0f, 1f)
                    wv.evaluateJavascript("window.fobInteractableAtNormalized($nx, $ny)") { result ->
                        if (hitTestGen == gen) buttonZone = result?.trim() == "true"
                    }
                }

                // Suppress orbit if drag starts inside the system nav bar zone
                val navZoneTop = size.height - navBarBottomPx - navZoneExtraPx
                val inNavZone  = downPos.y >= navZoneTop

                var isDragging  = false
                var isLongPress = false
                var cumDrag     = Offset.Zero
                var prevPinchDist = -1f
                val primaryId   = down.id

                // Long-press timer: 500 ms (iOS uses 0.5 s)
                // Handler runs on Main — safe to read/write local vars since coroutine
                // is suspended at awaitPointerEvent when the Runnable fires.
                val longPressRunnable = Runnable {
                    if (!isDragging) {
                        isLongPress = true
                        pressed = false
                        haptic(view, HapticFeedbackConstants.LONG_PRESS)
                        onLongPress()
                        webViewRef?.evaluateJavascript("window.playLedLock()", null)
                    }
                }
                handler.postDelayed(longPressRunnable, 500L)

                try {
                    loop@ while (true) {
                        val event   = awaitPointerEvent(pass = PointerEventPass.Main)
                        val primary = event.changes.find { it.id == primaryId }

                        // Pointer lift → end gesture
                        if (primary == null || !primary.pressed) break@loop

                        val activePtrs = event.changes.filter { it.pressed }

                        if (activePtrs.size >= 2) {
                            // ── Pinch-to-zoom ─────────────────────────────────
                            if (!isDragging) {
                                isDragging = true
                                handler.removeCallbacks(longPressRunnable)
                                pressed = false
                            }
                            val p1   = activePtrs[0].position
                            val p2   = activePtrs[1].position
                            val dist = (p1 - p2).getDistance()
                            if (prevPinchDist > 0f) {
                                val zoom = dist / prevPinchDist
                                webViewRef?.evaluateJavascript(
                                    "window.flushCameraGestures(0.0, 0.0, $zoom)", null
                                )
                            }
                            prevPinchDist = dist
                            event.changes.forEach { it.consume() }
                        } else {
                            // ── Single-pointer drag / orbit ───────────────────
                            prevPinchDist = -1f
                            val drag = primary.position - primary.previousPosition
                            cumDrag += drag

                            if (!isDragging && !isLongPress && !buttonZone && !inNavZone &&
                                cumDrag.getDistance() > orbitThresholdPx
                            ) {
                                isDragging = true
                                handler.removeCallbacks(longPressRunnable)
                                pressed = false
                            }

                            if (isDragging) {
                                // Orbit sensitivity 0.006 rad/px (matches iOS)
                                val dTheta = -drag.x * 0.006f
                                val dPhi   =  drag.y * 0.006f
                                webViewRef?.evaluateJavascript(
                                    "window.flushCameraGestures($dTheta, $dPhi, 1.0)", null
                                )
                                primary.consume()
                            }
                        }
                    }
                } finally {
                    handler.removeCallbacks(longPressRunnable)
                    pressed = false
                }

                // Confirmed tap: no long-press and no orbit
                if (!isLongPress && !isDragging) {
                    haptic(view, HapticFeedbackConstants.VIRTUAL_KEY) // medium tap confirm
                    tapCount++
                }
            }
        }
    ) {
        FobViewer(
            buttonDepth      = pressDepth,
            modelRotation    = Triple(0f, -0.4f, 0f),
            onWebViewCreated = { wv -> webViewRef = wv },
        )
    }
}

/**
 * Wraps [android.view.View.performHapticFeedback] with a safe API-level fallback.
 * [HapticFeedbackConstants.KEYBOARD_PRESS] requires API 27; older devices fall back to
 * [HapticFeedbackConstants.VIRTUAL_KEY].
 */
private fun haptic(view: android.view.View, constant: Int) {
    val safe = if (constant == HapticFeedbackConstants.KEYBOARD_PRESS &&
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1
    ) HapticFeedbackConstants.VIRTUAL_KEY else constant
    view.performHapticFeedback(safe)
}

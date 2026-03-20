package com.immogen.pipit.ui

import android.annotation.SuppressLint
import android.graphics.Color
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Embedded Three.js fob viewer backed by a system WebView.
 *
 * The viewer HTML/JS lives in assets/viewer.html — the Android build pulls it
 * from ../../assets/ via the sourceSets["main"].assets.srcDirs configuration,
 * so it is shared with the iOS Resources copy automatically.
 *
 * Uguisu.glb must be placed in androidApp/src/main/assets/Uguisu.glb
 * (or anywhere under the assets source dirs above).
 *
 * Three.js is loaded from CDN at runtime — requires internet on first load.
 * For offline builds see the bundling instructions in viewer.html.
 *
 * @param ledColor        Current LED colour expressed as a Compose [ComposeColor].
 * @param isActive        Whether the LED is illuminated.
 * @param ledBrightness   Perceived brightness, 0.0–1.0. Default: 1.
 * @param buttonDepth     Physical press depth: 0.0 = resting, 1.0 = fully pressed.
 * @param modelPosition   Position offset from centre in metres (x, y, z). Default: (0,0,0).
 * @param modelScale      Uniform scale multiplier. Default: 1 (no change).
 * @param modelRotation   Euler rotation angles in radians, XYZ order. Default: (0,0,0).
 * @param onWebViewCreated Called once after the WebView is created, allowing the caller to
 *                         capture a reference for direct JS bridge calls (camera gestures,
 *                         LED commands, raycast hit-testing).
 * @param modifier        Layout modifier applied to the WebView.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun FobViewer(
    ledColor: ComposeColor = ComposeColor.Unspecified,
    isActive: Boolean = false,
    ledBrightness: Float = 1f,
    buttonDepth: Float = 0f,
    modelPosition: Triple<Float, Float, Float> = Triple(0f, 0f, 0f),
    modelScale: Float = 1f,
    modelRotation: Triple<Float, Float, Float> = Triple(0f, 0f, 0f),
    onWebViewCreated: ((WebView) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    val webView = remember {
        WebView(context).apply {
            setBackgroundColor(Color.TRANSPARENT)

            isClickable = true
            isFocusable  = true

            settings.apply {
                javaScriptEnabled  = true
                domStorageEnabled  = true

                // Required so ES module imports in viewer.html can fetch
                // Three.js from CDN while the document origin is file://.
                @Suppress("DEPRECATION")
                allowFileAccessFromFileURLs      = true
                @Suppress("DEPRECATION")
                allowUniversalAccessFromFileURLs = true

                mediaPlaybackRequiresUserGesture = false
            }

            webChromeClient = WebChromeClient()
            webViewClient   = WebViewClient()

            loadUrl("file:///android_asset/viewer.html")
        }.also { onWebViewCreated?.invoke(it) }
    }

    // LED colour + active state + brightness
    LaunchedEffect(ledColor, isActive, ledBrightness) {
        val r = (ledColor.red   * 255).toInt()
        val g = (ledColor.green * 255).toInt()
        val b = (ledColor.blue  * 255).toInt()
        val active = if (isActive) "true" else "false"
        webView.evaluateJavascript(
            "if (window.setLedState) window.setLedState($r, $g, $b, $active, $ledBrightness);",
            null
        )
    }

    // Button actuation depth
    LaunchedEffect(buttonDepth) {
        webView.evaluateJavascript(
            "if (window.setButtonDepth) window.setButtonDepth($buttonDepth);",
            null
        )
    }

    // Model transform
    LaunchedEffect(modelPosition, modelScale, modelRotation) {
        val (px, py, pz) = modelPosition
        val (rx, ry, rz) = modelRotation
        webView.evaluateJavascript(
            "if (window.setModelTransform) window.setModelTransform($px, $py, $pz, $modelScale, $rx, $ry, $rz);",
            null
        )
    }

    AndroidView(
        factory  = { webView },
        modifier = modifier,
    )

    DisposableEffect(Unit) {
        onDispose { webView.destroy() }
    }
}

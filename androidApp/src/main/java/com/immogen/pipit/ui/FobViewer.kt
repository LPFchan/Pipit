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
 * The viewer HTML/JS lives in assets/viewer.html (shared asset source set,
 * so it is in both androidApp/src/main/assets/ and ../../assets/).
 * Three.js is loaded from CDN at runtime — the device needs internet access on
 * first load. For offline builds, see the bundling instructions in viewer.html.
 *
 * @param ledColor  Current LED colour expressed as a Compose [ComposeColor].
 * @param isActive  Whether the LED is illuminated.
 * @param modifier  Layout modifier applied to the WebView.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun FobViewer(
    ledColor: ComposeColor,
    isActive: Boolean,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    val webView = remember {
        WebView(context).apply {
            // Transparent so the native layout background shows through
            setBackgroundColor(Color.TRANSPARENT)

            isClickable = true
            isFocusable  = true

            settings.apply {
                javaScriptEnabled  = true
                domStorageEnabled  = true

                // Required so ES module imports in viewer.html can fetch
                // Three.js from CDN while the document origin is file://.
                // This is the standard pattern for embedded hybrid WebViews.
                @Suppress("DEPRECATION")
                allowFileAccessFromFileURLs    = true
                @Suppress("DEPRECATION")
                allowUniversalAccessFromFileURLs = true

                mediaPlaybackRequiresUserGesture = false
            }

            webChromeClient = WebChromeClient()
            webViewClient   = WebViewClient()

            // viewer.html is in the assets/ source set root, so it is
            // available at the android_asset:// root without a subdirectory.
            loadUrl("file:///android_asset/viewer.html")
        }
    }

    // Push LED state into the viewer whenever ledColor or isActive changes.
    // The JS guard `if (window.setLedState)` is safe during the brief window
    // between page load and script execution.
    LaunchedEffect(ledColor, isActive) {
        val r = (ledColor.red   * 255).toInt()
        val g = (ledColor.green * 255).toInt()
        val b = (ledColor.blue  * 255).toInt()
        val active = if (isActive) "true" else "false"
        webView.evaluateJavascript(
            "if (window.setLedState) window.setLedState($r, $g, $b, $active);",
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

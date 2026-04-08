package com.immogen.pipit.ui

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView

// ── LedCommand ────────────────────────────────────────────────────────────────

/**
 * A one-shot LED animation trigger. Mirrors the iOS LedCommand struct.
 *
 * Increment [id] each time you want to re-fire the same [kind] so that two
 * consecutive unlocks both play. [FobViewer] only dispatches a JS animation
 * call when [id] changes, preventing re-fires on unrelated recompositions.
 */
data class LedCommand(val kind: Kind, val id: Int = 0) {
    enum class Kind {
        /** Stop any running animation; LED returns to the static [setLedState] colour. */
        IDLE,
        /** Green fade-in 300 ms / hold 150 ms / fade-out 300 ms. */
        UNLOCK,
        /** Red, same timing as UNLOCK. */
        LOCK,
        /** Rainbow HSV sweep over 1500 ms. */
        WINDOW,
        /** Blue 500/200/500/50 ms prov-pulse loop (cancelled by the next command). */
        PROV,
        /** Low-battery green flash. */
        LOW_BAT_UNLOCK,
        /** Low-battery red flash. */
        LOW_BAT_LOCK,
    }
    companion object {
        val idle = LedCommand(Kind.IDLE, 0)
    }
}

// ── JS bridge ─────────────────────────────────────────────────────────────────

/** Receives messages from viewer.html via window.webkit.messageHandlers shim. */
private class ViewerJsBridge(private val onModelReady: () -> Unit) {
    @JavascriptInterface
    fun postMessage(name: String, data: String) {
        when (name) {
            "modelReady" -> Handler(Looper.getMainLooper()).post(onModelReady)
            "log"        -> Log.d("PipitViewer", "[JS] $data")
        }
    }
}

// ── FobViewer ─────────────────────────────────────────────────────────────────

/**
 * Embedded Three.js fob viewer backed by a system WebView.
 *
 * @param ledColor        Static LED colour (base state between animations).
 * @param isActive        Whether the LED is illuminated.
 * @param ledBrightness   Perceived brightness, 0.0–1.0.
 * @param ledCommand      One-shot animation trigger. Only fired when [LedCommand.id]
 *                        changes — prevents re-firing on unrelated recompositions.
 *                        Mirrors the iOS LedCommand deduplication pattern.
 * @param buttonDepth     Physical press depth: 0.0 = resting, 1.0 = fully pressed.
 * @param modelPosition   Position offset from centre in metres (x, y, z).
 * @param modelScale      Uniform scale multiplier.
 * @param modelRotation   Euler rotation angles in radians, XYZ order.
 * @param recoveryDemoLoop When true, starts the looping triple-press + rainbow LED demo
 *                         used in the onboarding recovery sheet (mirrors iOS recoverySheetDemoLoop).
 * @param onModelReady    Called once after Three.js reports the GLB is loaded — safe
 *                        to start animations or apply transforms from here.
 * @param onWebViewCreated Called once after the WebView is created (for direct JS bridge
 *                         calls such as camera gestures and raycast hit-testing).
 * @param modifier        Layout modifier applied to the WebView.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun FobViewer(
    ledColor: ComposeColor = ComposeColor.Unspecified,
    isActive: Boolean = false,
    ledBrightness: Float = 1f,
    ledCommand: LedCommand = LedCommand.idle,
    buttonDepth: Float = 0f,
    modelPosition: Triple<Float, Float, Float> = Triple(0f, 0f, 0f),
    modelScale: Float = 1f,
    modelRotation: Triple<Float, Float, Float> = Triple(0f, 0f, 0f),
    recoveryDemoLoop: Boolean = false,
    onModelReady: (() -> Unit)? = null,
    onWebViewCreated: ((WebView) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    // Incremented on the main thread when viewer.html fires window.webkit.messageHandlers.modelReady.
    // LaunchedEffects key on this so they re-run (with current param values) when the model loads.
    val modelReadyTrigger = remember { mutableIntStateOf(0) }

    // Deduplication: only dispatch a ledCommand JS call when its id changes.
    // Mirrors iOS Coordinator.lastLedCommandId check in applyState().
    val lastLedCommandId = remember { mutableIntStateOf(-1) }

    val ASSET_BASE = "https://appassets.androidplatform.net/assets/"

    // WebKit message-handler shim: viewer.html calls window.webkit.messageHandlers.X.postMessage(data).
    // This shim forwards those calls to AndroidBridge.postMessage(name, data) so the native
    // ViewerJsBridge can receive modelReady and log messages without any changes to viewer.html.
    val webkitShim = """
        <script>
        (function(){
            var h={};
            ['modelReady','log'].forEach(function(n){
                h[n]={postMessage:function(d){
                    if(window.AndroidBridge)window.AndroidBridge.postMessage(n,JSON.stringify(d||{}));
                }};
            });
            window.webkit={messageHandlers:h};
        })();
        </script>
    """.trimIndent()

    // Android GFXSTREAM compositor workaround — mirrors existing logic, unchanged.
    val preserveDrawingBufferPatch = """
        <script>
        (function(){
            var _wgl=null,_ovl=null,_ctx=null;
            HTMLCanvasElement.prototype.getContext=(function(orig){
                return function(type,opts){
                    if(type==='webgl2'||type==='webgl'){
                        opts=Object.assign({},opts||{},{preserveDrawingBuffer:true});
                        var gl=orig.call(this,type,opts);
                        if(gl&&!_wgl){_wgl=this;_init();}
                        return gl;
                    }
                    return orig.call(this,type,opts);
                };
            })(HTMLCanvasElement.prototype.getContext);
            function _init(){
                _ovl=document.createElement('canvas');
                Object.assign(_ovl.style,{
                    position:'fixed',top:'0',left:'0',
                    zIndex:'999',pointerEvents:'none'
                });
                (function _append(){
                    if(document.body){
                        document.body.appendChild(_ovl);
                        _ctx=_ovl.getContext('2d');
                        requestAnimationFrame(_tick);
                    } else { setTimeout(_append,20); }
                })();
            }
            function _tick(){
                requestAnimationFrame(_tick);
                if(!_ctx||!_wgl||!_wgl.width)return;
                if(_ovl.width!==_wgl.width){
                    _ovl.width=_wgl.width; _ovl.height=_wgl.height;
                    _ovl.style.width=_wgl.style.width;
                    _ovl.style.height=_wgl.style.height;
                }
                _ctx.clearRect(0,0,_ovl.width,_ovl.height);
                _ctx.drawImage(_wgl,0,0);
            }
        })();
        </script>
    """.trimIndent()

    val webView = remember {
        WebView(context).apply {
            setBackgroundColor(android.graphics.Color.argb(255, 28, 30, 40))

            isClickable = true
            isFocusable  = true

            settings.apply {
                javaScriptEnabled  = true
                domStorageEnabled  = true
                @Suppress("DEPRECATION")
                allowFileAccessFromFileURLs      = true
                @Suppress("DEPRECATION")
                allowUniversalAccessFromFileURLs = true
                mediaPlaybackRequiresUserGesture = false
            }

            // JS→native bridge: receives modelReady and log from the webkitShim above.
            addJavascriptInterface(
                ViewerJsBridge { modelReadyTrigger.intValue++ },
                "AndroidBridge"
            )

            WebView.setWebContentsDebuggingEnabled(true)

            webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(msg: ConsoleMessage): Boolean {
                    val level = when (msg.messageLevel()) {
                        ConsoleMessage.MessageLevel.ERROR   -> Log.ERROR
                        ConsoleMessage.MessageLevel.WARNING -> Log.WARN
                        else                               -> Log.DEBUG
                    }
                    Log.println(level, "PipitViewer", "${msg.message()} [${msg.sourceId()}:${msg.lineNumber()}]")
                    return true
                }
            }
            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                    Log.d("PipitViewer", "onPageStarted: $url")
                }
                override fun onPageFinished(view: WebView, url: String) {
                    Log.d("PipitViewer", "onPageFinished: $url")
                    view.evaluateJavascript("""
                        (function() {
                            var bd = document.getElementById('pipitViewerBackdrop');
                            var cvs = document.querySelector('canvas');
                            if (cvs) {
                                cvs.style.transform = 'translateZ(0)';
                                cvs.style.willChange = 'transform';
                            }
                            var styleTag = document.createElement('style');
                            styleTag.textContent =
                                '#pipitViewerBackdrop { position: absolute !important; }';
                            document.head.appendChild(styleTag);
                            window.dispatchEvent(new Event('resize'));
                            if (bd) bd.style.opacity = '1';
                            console.log('[Pipit-D] innerW=' + window.innerWidth
                                + ' innerH=' + window.innerHeight
                                + ' bdOpacity=' + (bd ? getComputedStyle(bd).opacity : 'no-bd')
                                + ' bdBg=' + (bd ? bd.style.background.slice(0,40) : 'no-bd'));
                            if (cvs) {
                                var gl = cvs.getContext('webgl2') || cvs.getContext('webgl');
                                console.log('[Pipit-D] canvas=' + cvs.width + 'x' + cvs.height
                                    + ' gl=' + (gl ? 'ok' : 'null')
                                    + (gl ? ' lost=' + gl.isContextLost() : ''));
                                if (gl) console.log('[Pipit-D] glError=' + gl.getError());
                            } else {
                                console.log('[Pipit-D] no canvas found');
                            }
                            setTimeout(function() {
                                var cvs2 = document.querySelector('canvas');
                                var op   = cvs2 ? getComputedStyle(cvs2).opacity : 'no-canvas';
                                console.log('[Pipit-D] t=2s canvasOpacity=' + op);
                                if (cvs2) {
                                    var r = cvs2.getBoundingClientRect();
                                    console.log('[Pipit-D] canvasRect top=' + r.top
                                        + ' left=' + r.left + ' w=' + r.width + ' h=' + r.height);
                                }
                            }, 2000);
                        })();
                    """.trimIndent(), null)
                }
                override fun onReceivedError(view: WebView, errorCode: Int, description: String, failingUrl: String) {
                    Log.e("PipitViewer", "onReceivedError $errorCode $description @ $failingUrl")
                }
                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest,
                ): WebResourceResponse? {
                    val url = request.url.toString()
                    if (!url.startsWith(ASSET_BASE)) return null
                    val assetPath = url.removePrefix(ASSET_BASE)
                    Log.d("PipitViewer", "asset: $assetPath")
                    val mimeType = when {
                        assetPath.endsWith(".html")                      -> "text/html"
                        assetPath.endsWith(".js")                        -> "application/javascript"
                        assetPath.endsWith(".glb")                       -> "model/gltf-binary"
                        assetPath.endsWith(".gltf")                      -> "model/gltf+json"
                        assetPath.endsWith(".png")                       -> "image/png"
                        assetPath.endsWith(".jpg") || assetPath.endsWith(".jpeg") -> "image/jpeg"
                        assetPath.endsWith(".hdr")                       -> "image/x-hdr"
                        else                                             -> "application/octet-stream"
                    }
                    return try {
                        var stream = context.assets.open(assetPath)
                        if (assetPath == "materials.js") {
                            val patched = stream.bufferedReader().readText().replace(
                                "\"bodyBackground\": \"radial-gradient(ellipse at 50% 38%, #ffffff 0%, #b5b5b5 100%)\"",
                                "\"bodyBackground\": \"radial-gradient(ellipse at 50% 38%, #1c1e28 0%, #09090c 100%)\"",
                            )
                            stream = patched.byteInputStream()
                        }
                        WebResourceResponse(mimeType, "utf-8", stream)
                    } catch (e: Exception) {
                        Log.e("PipitViewer", "asset not found: $assetPath", e)
                        null
                    }
                }
            }

            val html = try {
                context.assets.open("viewer.html").bufferedReader().use { it.readText() }
                    .replace("local://app/", ASSET_BASE)
                    // Inject webkit shim first so it's ready before viewer.html scripts run,
                    // then the WebGL compositor patch.
                    .replace("<head>", "<head>$webkitShim$preserveDrawingBufferPatch")
                    .also { Log.d("PipitViewer", "viewer.html loaded (${it.length} chars)") }
            } catch (e: Exception) {
                Log.e("PipitViewer", "Failed to read viewer.html from assets", e)
                "<html><body><p style='color:red'>viewer.html asset missing</p></body></html>"
            }
            loadDataWithBaseURL(ASSET_BASE, html, "text/html", "utf-8", null)
        }.also { onWebViewCreated?.invoke(it) }
    }

    // ── Model ready callback ───────────────────────────────────────────────────
    // Fires after Three.js signals modelReady via the JS bridge.
    // Uses the *current* onModelReady value (not the one captured at first composition).
    LaunchedEffect(modelReadyTrigger.intValue) {
        if (modelReadyTrigger.intValue > 0) onModelReady?.invoke()
    }

    // ── Static LED state ──────────────────────────────────────────────────────
    // Deferred until modelReady so the JS function actually exists.
    // Re-runs when any LED param changes OR when the model first becomes ready.
    LaunchedEffect(ledColor, isActive, ledBrightness, modelReadyTrigger.intValue) {
        if (modelReadyTrigger.intValue == 0) return@LaunchedEffect
        val r = (ledColor.red   * 255).toInt()
        val g = (ledColor.green * 255).toInt()
        val b = (ledColor.blue  * 255).toInt()
        val active = if (isActive) "true" else "false"
        webView.evaluateJavascript(
            "if (window.setLedState) window.setLedState($r, $g, $b, $active, $ledBrightness);",
            null
        )
    }

    // ── One-shot LED animation (deduplication) ────────────────────────────────
    // Mirrors iOS applyState(): only fires when ledCommand.id changes.
    // LaunchedEffect naturally deduplicates since it only re-runs when its keys change.
    LaunchedEffect(ledCommand.id, modelReadyTrigger.intValue) {
        if (modelReadyTrigger.intValue == 0) return@LaunchedEffect
        if (ledCommand.id == lastLedCommandId.intValue) return@LaunchedEffect
        lastLedCommandId.intValue = ledCommand.id
        val js = when (ledCommand.kind) {
            LedCommand.Kind.IDLE           -> "if(window.stopLedAnim)window.stopLedAnim();"
            LedCommand.Kind.UNLOCK         -> "if(window.playLedUnlock)window.playLedUnlock();"
            LedCommand.Kind.LOCK           -> "if(window.playLedLock)window.playLedLock();"
            LedCommand.Kind.WINDOW         -> "if(window.playLedWindow)window.playLedWindow();"
            LedCommand.Kind.PROV           -> "if(window.startLedProv)window.startLedProv();"
            LedCommand.Kind.LOW_BAT_UNLOCK -> "if(window.playLedLowBat)window.playLedLowBat(0,255,0);"
            LedCommand.Kind.LOW_BAT_LOCK   -> "if(window.playLedLowBat)window.playLedLowBat(255,0,0);"
        }
        webView.evaluateJavascript(js, null)
    }

    // ── Button actuation depth ────────────────────────────────────────────────
    LaunchedEffect(buttonDepth) {
        webView.evaluateJavascript(
            "if (window.setButtonDepth) window.setButtonDepth($buttonDepth);",
            null
        )
    }

    // ── Model transform ───────────────────────────────────────────────────────
    LaunchedEffect(modelPosition, modelScale, modelRotation, modelReadyTrigger.intValue) {
        if (modelReadyTrigger.intValue == 0) return@LaunchedEffect
        val (px, py, pz) = modelPosition
        val (rx, ry, rz) = modelRotation
        webView.evaluateJavascript(
            "if (window.setModelTransform) window.setModelTransform($px, $py, $pz, $modelScale, $rx, $ry, $rz);",
            null
        )
    }

    // ── Recovery demo loop ────────────────────────────────────────────────────
    // Mirrors iOS recoverySheetDemoLoop: starts the looping triple-press + rainbow
    // LED demo used in the onboarding recovery sheet. Deferred until modelReady.
    LaunchedEffect(recoveryDemoLoop, modelReadyTrigger.intValue) {
        if (recoveryDemoLoop && modelReadyTrigger.intValue > 0) {
            webView.evaluateJavascript(
                "if(window.setRecoveryDemoChrome)window.setRecoveryDemoChrome(true);" +
                "if(window.startRecoveryTriplePressDemo)window.startRecoveryTriplePressDemo();",
                null
            )
        } else if (!recoveryDemoLoop) {
            webView.evaluateJavascript(
                "if(window.stopRecoveryTriplePressDemo)window.stopRecoveryTriplePressDemo();" +
                "if(window.setRecoveryDemoChrome)window.setRecoveryDemoChrome(false);",
                null
            )
        }
    }

    AndroidView(
        factory  = { webView },
        modifier = modifier,
    )

    DisposableEffect(Unit) {
        onDispose {
            if (recoveryDemoLoop) {
                webView.evaluateJavascript(
                    "if(window.stopRecoveryTriplePressDemo)window.stopRecoveryTriplePressDemo();",
                    null
                )
            }
            webView.destroy()
        }
    }
}

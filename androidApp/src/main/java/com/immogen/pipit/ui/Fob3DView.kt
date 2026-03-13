package com.immogen.pipit.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import io.github.sceneview.Scene
import io.github.sceneview.math.Position
import io.github.sceneview.node.ModelNode
import io.github.sceneview.rememberCameraManipulator
import io.github.sceneview.rememberCameraNode
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberEnvironmentLoader
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberNode

/**
 * 3D fob view using SceneView (Filament). Loads uguisu_placeholder.glb,
 * maps tap = unlock and long-press = lock, and animates button depression (~1–2mm).
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
    val modelNodeRef = remember { mutableStateOf<ModelNode?>(null) }

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
        val engine = rememberEngine()
        val modelLoader = rememberModelLoader(engine)
        val environmentLoader = rememberEnvironmentLoader(engine)
        val centerNode = rememberNode(engine)

        val cameraNode = rememberCameraNode(engine) {
            position = Position(y = -0.02f, z = 0.12f)
            lookAt(centerNode)
            centerNode.addChildNode(this)
        }
        val fallbackNode = rememberNode(engine)

        Scene(
            modifier = Modifier.fillMaxSize(),
            engine = engine,
            modelLoader = modelLoader,
            cameraNode = cameraNode,
            cameraManipulator = rememberCameraManipulator(
                orbitHomePosition = cameraNode.worldPosition,
                targetPosition = centerNode.worldPosition
            ),
            childNodes = listOf(
                centerNode,
                rememberNode {
                    try {
                        val instance = modelLoader.createModelInstance(
                            assetFileLocation = "uguisu_placeholder.glb"
                        )
                        ModelNode(
                            modelInstance = instance,
                            scaleToUnits = 0.08f
                        ).also { modelNodeRef.value = it }
                    } catch (e: Exception) {
                        modelNodeRef.value = null
                        fallbackNode
                    }
                }
            ),
            environment = try {
                environmentLoader.createEnvironment(
                    skybox = io.github.sceneview.loaders.Skybox.Builder()
                        .color(0.75f, 0.75f, 0.8f, 1f)
                        .build(engine)
                )
            } catch (e: Exception) {
                null
            },
            onFrame = {
                val zOffset = -0.002f * depressTarget
                modelNodeRef.value?.position = Position(z = zOffset)
            }
        )
    }
}

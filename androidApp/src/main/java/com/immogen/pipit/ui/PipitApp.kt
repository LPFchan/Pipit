package com.immogen.pipit.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.immogen.pipit.ble.BleState
import com.immogen.pipit.ble.BleService
import com.immogen.pipit.ble.ConnectionState
import com.immogen.pipit.onboarding.OnboardingGate

private enum class RootScreen {
    ONBOARDING,
    HOME,
    SETTINGS
}

@Composable
fun PipitApp(
    bleState: BleState,
    bleService: BleService?,
    onRequestUnlock: () -> Unit,
    onRequestLock: () -> Unit,
    debugSetConnectionState: ((ConnectionState) -> Unit)? = null,
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
            transitionSpec = {
                when {
                    // Settings slides in/out from the trailing edge (matches iOS asymmetric move+opacity)
                    initialState == RootScreen.HOME && targetState == RootScreen.SETTINGS ->
                        (slideInHorizontally(tween(280)) { it } + fadeIn(tween(280))) togetherWith
                        (slideOutHorizontally(tween(280)) { -it / 4 } + fadeOut(tween(140)))
                    initialState == RootScreen.SETTINGS && targetState == RootScreen.HOME ->
                        (slideInHorizontally(tween(280)) { -it / 4 } + fadeIn(tween(140))) togetherWith
                        (slideOutHorizontally(tween(280)) { it } + fadeOut(tween(280)))
                    else ->
                        fadeIn(tween(280)) togetherWith fadeOut(tween(280))
                }
            },
            label = "rootTransition",
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
                    SettingsScreen(
                        bleService = bleService,
                        onClose = { currentScreen = RootScreen.HOME },
                        onLocalKeyDeleted = { currentScreen = RootScreen.ONBOARDING },
                        debugSetConnectionState = debugSetConnectionState,
                    )
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

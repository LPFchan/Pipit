package com.immogen.pipit.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.immogen.pipit.ble.BleState

@Composable
internal fun HomeScreen(
    bleState: BleState,
    onGearClick: () -> Unit,
    onTapFob: () -> Unit,
    onLongPressFob: () -> Unit,
    showTapHint: Boolean,
) {
    Box(modifier = Modifier.fillMaxSize()) {
        // 3D fob fills the whole screen
        Fob3DView(
            onTap = onTapFob,
            onLongPress = onLongPressFob,
            modifier = Modifier.fillMaxSize(),
        )

        // Gear button — circular material background, top-start (matches iOS RootView gearshape button)
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.72f),
            tonalElevation = 2.dp,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 16.dp, top = 16.dp)
                .size(36.dp),
        ) {
            IconButton(
                onClick = onGearClick,
                modifier = Modifier.size(36.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Settings,
                    contentDescription = "Settings",
                    modifier = Modifier.size(18.dp),
                )
            }
        }

        // Hint pill — capsule with secondary background, bottom-center (matches iOS Capsule hint)
        AnimatedVisibility(
            visible = showTapHint,
            enter = fadeIn(tween(400)),
            exit  = fadeOut(tween(400)),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 24.dp),
        ) {
            Surface(
                shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.8f),
            ) {
                Text(
                    text = "Hold to lock, tap to unlock",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}

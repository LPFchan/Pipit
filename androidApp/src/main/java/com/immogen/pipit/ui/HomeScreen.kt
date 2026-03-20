package com.immogen.pipit.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
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
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
    ) {
        IconButton(
            onClick = onGearClick,
            modifier = Modifier.align(Alignment.Start),
        ) {
            Icon(
                imageVector = Icons.Default.Settings,
                contentDescription = "Settings",
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        Fob3DView(
            onTap = onTapFob,
            onLongPress = onLongPressFob,
            modifier = Modifier
                .weight(2f)
                .fillMaxWidth(),
        )
        // Hint text fades out on first interaction (400 ms EaseOut, matches iOS)
        AnimatedVisibility(
            visible = showTapHint,
            enter = fadeIn(tween(400)),
            exit  = fadeOut(tween(400)),
        ) {
            Text(
                text = "Tap \u00b7 Hold to lock",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                textAlign = TextAlign.Center,
            )
        }
        Spacer(modifier = Modifier.weight(1f))
    }
}

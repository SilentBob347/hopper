package com.aengix.hopper.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aengix.hopper.vpn.VpnController

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServerLibraryScreen(
    vpn: VpnController,
    onBack: () -> Unit,
    onServerDetail: (String) -> Unit,
    onRequestCameraPermission: () -> Boolean,
) {
    val state by vpn.state.collectAsState()
    var showImport by remember { mutableStateOf(false) }
    var showScanner by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Servers") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    Button(onClick = { showImport = true }) { Text("Import") }
                    Button(onClick = {
                        if (onRequestCameraPermission()) showScanner = true
                    }) { Text("Scan QR") }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            if (state.servers.isEmpty()) {
                Text(
                    "No servers — scan a QR code or import JSON from deploy.sh.",
                    modifier = Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                state.servers.forEach { server ->
                    ListItem(
                        headlineContent = { Text(server.displayName) },
                        supportingContent = {
                            Text("${server.trimmedUser}@${server.trimmedHost}:${server.port}")
                        },
                        modifier = Modifier.padding(horizontal = 8.dp),
                        overlineContent = null,
                    )
                    Button(onClick = { onServerDetail(server.id) }) {
                        Text("Details")
                    }
                }
            }
        }
    }

    if (showImport) {
        ImportJsonDialog(
            onDismiss = { showImport = false },
            onImport = { hop ->
                vpn.addServer(hop)
                showImport = false
            },
            onError = vpn::setError,
        )
    }

    if (showScanner) {
        QRScannerScreen(
            onDismiss = { showScanner = false },
            onScan = { payload ->
                runCatching {
                    com.aengix.hopper.data.HopQRParser.parse(payload)
                }.onSuccess { hop ->
                    vpn.addServer(hop)
                    showScanner = false
                }.onFailure { error ->
                    vpn.setError(error.message)
                }
            },
        )
    }
}

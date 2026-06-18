package com.aengix.hopper.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.vpn.VpnController
import com.aengix.hopper.vpn.VpnStatus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    vpn: VpnController,
    onConfigureChains: () -> Unit,
    onChainDetail: (String) -> Unit,
    onRequestVpnConnect: (restartHopperd: Boolean) -> Unit,
) {
    val state by vpn.state.collectAsState()
    val vpnStatus by vpn.vpnStatus.collectAsState()
    val provisionStatus by vpn.provisionStatus.collectAsState()
    val errorMessage by vpn.errorMessage.collectAsState()
    var showConnectOptions by remember { mutableStateOf(false) }
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("${HopConstants.APP_DISPLAY_NAME} ${HopConstants.appVersion(context)}") })
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            Text("Chain", style = MaterialTheme.typography.titleMedium)
            val chain = state.selectedChain
            if (chain != null) {
                ChainPicker(
                    chains = state.chains,
                    selectedId = state.selectedChainID,
                    onSelect = vpn::selectChain,
                )
                Text(
                    text = chainRouteSummary(state.activeHops),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .padding(top = 4.dp)
                        .clickable { onChainDetail(chain.id) },
                )
            } else {
                Text(
                    "No chain selected",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            TextButton(onClick = onConfigureChains) {
                Text("Configure chains")
            }

            Text("Connect", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
            val entry = state.entryHop
            if (entry != null) {
                Text(entry.displayName, style = MaterialTheme.typography.titleSmall)
                Text(
                    "${entry.trimmedUser}@${entry.trimmedHost}:${entry.port}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text(
                    "Add servers and build a chain (entry → exit).",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            val connected = vpnStatus == VpnStatus.Connected
            val busy = vpnStatus == VpnStatus.Connecting || vpnStatus == VpnStatus.Disconnecting
            Button(
                onClick = {
                    if (connected || busy) {
                        vpn.disconnect()
                    } else {
                        showConnectOptions = true
                    }
                },
                enabled = !busy && entry != null && provisionStatus == null,
                modifier = Modifier.padding(top = 8.dp),
            ) {
                Text(if (connected) "Disconnect" else "Connect")
            }

            Text(
                statusLabel(vpnStatus),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )

            provisionStatus?.let {
                Text(it, color = MaterialTheme.colorScheme.tertiary, modifier = Modifier.padding(top = 4.dp))
            }

            val hops = state.activeHops
            if (hops.isNotEmpty()) {
                Text("Route", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
                hops.forEachIndexed { index, hop ->
                    ListItem(
                        headlineContent = { Text(chainRole(index, hops.size, hop)) },
                        supportingContent = {
                            Text("${hop.trimmedUser}@${hop.trimmedHost}:${hop.port}")
                        },
                    )
                }
            }

            errorMessage?.let {
                Text("Error", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
                Text(it, color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (showConnectOptions) {
        AlertDialog(
            onDismissRequest = { showConnectOptions = false },
            title = { Text("Connect to chain") },
            text = {
                Column {
                    Text(
                        "Restart hopperd on all nodes if you've changed the chain or are having connection issues on the servers. Leave off for faster reconnects.",
                    )
                    TextButton(onClick = {
                        showConnectOptions = false
                        onRequestVpnConnect(false)
                    }) { Text("Connect") }
                    TextButton(onClick = {
                        showConnectOptions = false
                        onRequestVpnConnect(true)
                    }) { Text("Connect & restart hopperd") }
                    TextButton(onClick = { showConnectOptions = false }) { Text("Cancel") }
                }
            },
            confirmButton = {},
        )
    }
}

@Composable
private fun ChainPicker(
    chains: List<com.aengix.hopper.model.HopChain>,
    selectedId: String?,
    onSelect: (String?) -> Unit,
) {
    chains.forEach { chain ->
        ListItem(
            headlineContent = { Text(chain.displayName) },
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onSelect(chain.id) },
            trailingContent = {
                if (chain.id == selectedId) {
                    Text("✓")
                }
            },
        )
    }
}

private fun chainRouteSummary(hops: List<HopNodeProfile>): String = when {
    hops.isEmpty() -> "No servers in chain"
    hops.size == 1 -> hops[0].displayName
    else -> "${hops.first().displayName} → ${hops.last().displayName} (${hops.size} hops)"
}

private fun chainRole(index: Int, total: Int, hop: HopNodeProfile): String {
    val role = when {
        total == 1 -> "Exit"
        index == 0 -> "Entry"
        index == total - 1 -> "Exit"
        else -> "Relay"
    }
    return "${index + 1}. $role — ${hop.displayName}"
}

private fun statusLabel(status: VpnStatus): String = when (status) {
    VpnStatus.Connected -> "Connected"
    VpnStatus.Connecting -> "Connecting…"
    VpnStatus.Disconnecting -> "Disconnecting…"
    VpnStatus.Disconnected -> "Disconnected"
}

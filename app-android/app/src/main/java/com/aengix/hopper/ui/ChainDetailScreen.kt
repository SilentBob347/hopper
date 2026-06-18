package com.aengix.hopper.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.unit.dp
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.vpn.VpnController

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChainDetailScreen(
    vpn: VpnController,
    chainId: String,
    onBack: () -> Unit,
) {
    val state by vpn.state.collectAsState()
    val chain = state.chains.firstOrNull { it.id == chainId }
    val hops = chain?.let { state.resolveHops(it) }.orEmpty()
    var name by remember(chain?.name) { mutableStateOf(chain?.name.orEmpty()) }
    var showAddServer by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(chain?.displayName ?: "Chain") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        if (chain == null) {
            Text("Chain not found", modifier = Modifier.padding(padding).padding(16.dp))
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            Text("Name", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = name,
                onValueChange = {
                    name = it
                    vpn.renameChain(chainId, it)
                },
                label = { Text("Chain name") },
                modifier = Modifier.fillMaxWidth(),
            )

            Text(
                "Route (entry → exit)",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 16.dp),
            )

            if (hops.isEmpty()) {
                Text("Add servers from your library.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                hops.forEachIndexed { index, hop ->
                    ListItem(
                        headlineContent = { Text(roleLabel(index, hops.size, hop)) },
                        supportingContent = {
                            Text("${hop.trimmedUser}@${hop.trimmedHost}:${hop.port}")
                        },
                    )
                }
            }

            val available = state.servers.filter { server -> server.id !in chain.hopIDs }
            Button(
                onClick = { showAddServer = true },
                enabled = available.isNotEmpty(),
                modifier = Modifier.padding(top = 8.dp),
            ) {
                Text("Add server…")
            }
        }
    }

    if (showAddServer && chain != null) {
        val available = state.servers.filter { server -> server.id !in chain.hopIDs }
        AlertDialog(
            onDismissRequest = { showAddServer = false },
            title = { Text("Add server") },
            text = {
                Column {
                    available.forEach { server ->
                        ListItem(
                            headlineContent = { Text(server.displayName) },
                            supportingContent = {
                                Text("${server.trimmedUser}@${server.trimmedHost}:${server.port}")
                            },
                            modifier = Modifier.clickable {
                                vpn.addServerToChain(chainId, server.id)
                                showAddServer = false
                            },
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showAddServer = false }) { Text("Cancel") }
            },
        )
    }
}

private fun roleLabel(index: Int, total: Int, hop: HopNodeProfile): String {
    val role = when {
        total == 1 -> "Exit"
        index == 0 -> "Entry"
        index == total - 1 -> "Exit"
        else -> "Relay"
    }
    return "${index + 1}. $role — ${hop.displayName}"
}

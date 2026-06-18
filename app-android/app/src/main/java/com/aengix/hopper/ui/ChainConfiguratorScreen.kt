package com.aengix.hopper.ui

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aengix.hopper.model.HopChain
import com.aengix.hopper.vpn.VpnController

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChainConfiguratorScreen(
    vpn: VpnController,
    onBack: () -> Unit,
    onChainDetail: (String) -> Unit,
    onOpenServers: () -> Unit,
) {
    val state by vpn.state.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Chains") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            Button(onClick = onOpenServers, modifier = Modifier.padding(bottom = 8.dp)) {
                Text("Server library")
            }
            Text(
                "Scan QR codes or import JSON here to add servers. Then build chains from those servers below.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 16.dp),
            )

            Text("Chains", style = MaterialTheme.typography.titleMedium)
            if (state.chains.isEmpty()) {
                Text(
                    "Create a chain and add servers in entry → exit order.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                state.chains.forEach { chain ->
                    ListItem(
                        headlineContent = { Text(chain.displayName) },
                        supportingContent = { Text(chainSummary(state, chain)) },
                        trailingContent = {
                            if (state.selectedChainID == chain.id) Text("✓")
                        },
                        modifier = Modifier.clickable { onChainDetail(chain.id) },
                    )
                    Button(onClick = { vpn.selectChain(chain.id) }) {
                        Text("Use")
                    }
                }
            }

            Button(
                onClick = {
                    val id = vpn.addChain()
                    vpn.selectChain(id)
                },
                modifier = Modifier.padding(top = 8.dp),
            ) {
                Text("New chain")
            }
        }
    }
}

private fun chainSummary(state: com.aengix.hopper.model.AppState, chain: HopChain): String {
    val hops = state.resolveHops(chain)
    return when {
        hops.isEmpty() -> "No servers"
        hops.size == 1 -> "1 hop — ${hops[0].displayName}"
        else -> "${hops.size} hops — ${hops.first().displayName} → ${hops.last().displayName}"
    }
}

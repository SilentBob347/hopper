package com.aengix.hopper.provision

import com.aengix.hopper.model.ChainTopology
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.model.HopReadyReport
import com.aengix.hopper.ssh.HopSSH
import com.aengix.hopper.util.HopErrorDetails
import com.aengix.hopper.util.TunnelLog

sealed class ChainProvisionerException(message: String) : Exception(message) {
    data object EmptyChain : ChainProvisionerException("Add at least one hop (entry → exit order).")
    data class InvalidReadyJson(val output: String) :
        ChainProvisionerException("Server did not return ready JSON. Output: ${output.takeLast(200)}")
    data class MissingPubkey(val hop: String) :
        ChainProvisionerException("Could not read SSH public key on $hop.")
    data class ProvisionFailed(val detail: String) : ChainProvisionerException(detail)
}

object ChainProvisioner {
    fun provision(
        chainId: String,
        chain: List<HopNodeProfile>,
        restartHopperd: Boolean = false,
        onProgress: ((index: Int, total: Int, message: String) -> Unit)? = null,
    ): List<HopReadyReport> {
        if (chain.isEmpty()) throw ChainProvisionerException.EmptyChain

        val total = chain.size
        val reports = mutableListOf<HopReadyReport>()
        val overlay = ChainTopology.overlayCIDR(chainId)
        val skipIfRunning = !restartHopperd

        if (restartHopperd) {
            onProgress?.invoke(total - 1, total, "Stopping previous hopperd on all hops…")
            chain.forEach { stopNode(it, chainId) }
        }

        var downstreamListenPort: Int? = null

        for (i in (total - 1 downTo 0)) {
            val hop = chain[i]
            val label = hop.displayName
            onProgress?.invoke(i, total, "Configuring $label…")
            TunnelLog.info("Chain provision hop[$i] $label")

            if (i < total - 1) {
                val downstream = chain[i + 1]
                val pubkey = fetchPubkey(hop)
                trustPubkey(pubkey, downstream, chainId)
            }

            val report = startNode(
                chainId = chainId,
                hop = hop,
                index = i,
                isExit = i == total - 1,
                next = chain.getOrNull(i + 1),
                nextTunnelPort = downstreamListenPort,
                overlay = overlay,
                skipIfRunning = skipIfRunning,
            )
            downstreamListenPort = report.listen_port ?: ChainTopology.listenPort(chainId)
            reports += report
            onProgress?.invoke(i, total, "$label ready (${report.mode} ${report.addr})")
        }

        return reports.asReversed()
    }

    private fun stopNode(hop: HopNodeProfile, chainId: String) {
        val install = hop.resolvedInstallDir
        val cmd = "cd ${shellQuote(install)} && ./hopperctl start --chain-id ${shellQuote(chainId)} --stop-only"
        runCatching {
            HopSSH.withSession(hop) { client ->
                HopSSH.runCommand(client, cmd)
            }
            TunnelLog.info("Stopped previous hopperd on ${hop.displayName}")
        }.onFailure {
            TunnelLog.info("Stop hopperd on ${hop.displayName} (non-fatal): ${HopErrorDetails.describe(it)}")
        }
    }

    private fun fetchPubkey(hop: HopNodeProfile): String {
        return HopSSH.withSession(hop) { client ->
            val output = HopSSH.runCommand(client, "cat ~/.hopper/id_ed25519.pub").trim()
            if (!output.startsWith("ssh-")) {
                throw ChainProvisionerException.MissingPubkey(hop.displayName)
            }
            output
        }
    }

    private fun trustPubkey(pubkey: String, hop: HopNodeProfile, chainId: String) {
        val install = hop.resolvedInstallDir
        val cmd = "cd ${shellQuote(install)} && ./hopperctl start --chain-id ${shellQuote(chainId)} --trust-pubkey ${shellQuote(pubkey)} --trust-only"
        HopSSH.withSession(hop) { client ->
            HopSSH.runCommand(client, cmd)
        }
        TunnelLog.info("Trusted upstream key on ${hop.displayName}")
    }

    private fun startNode(
        chainId: String,
        hop: HopNodeProfile,
        index: Int,
        isExit: Boolean,
        next: HopNodeProfile?,
        nextTunnelPort: Int?,
        overlay: String,
        skipIfRunning: Boolean,
    ): HopReadyReport {
        val install = hop.resolvedInstallDir
        val addr = ChainTopology.overlayAddr(chainId, index)
        val args = buildList {
            add("--chain-id"); add(chainId)
            add("--role"); add(if (isExit) "exit" else "relay")
            add("--addr"); add(addr)
            add("--index"); add(index.toString())
            add("--overlay"); add(overlay)
            if (skipIfRunning) {
                add("--if-running"); add("skip")
            }
            if (next != null) {
                add("--next-host"); add(next.trimmedHost)
                add("--next-port"); add(next.port.toString())
                add("--next-user"); add(next.trimmedUser)
                if (nextTunnelPort != null) {
                    add("--next-tunnel-port"); add(nextTunnelPort.toString())
                }
            }
        }

        val argString = args.joinToString(" ") { shellQuote(it) }
        val cmd = "cd ${shellQuote(install)} && ./hopperctl start $argString"

        return HopSSH.withSession(hop) { client ->
            val output = HopSSH.runCommand(client, cmd)
            HopReadyReport.parse(output)
        }
    }

    private fun shellQuote(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"
}

private val HopNodeProfile.resolvedInstallDir: String
    get() {
        val trimmed = installDir.trim()
        return trimmed.ifEmpty { com.aengix.hopper.model.HopConstants.DEFAULT_INSTALL_DIR }
    }

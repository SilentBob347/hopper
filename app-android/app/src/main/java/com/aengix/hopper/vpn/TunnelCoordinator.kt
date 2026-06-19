package com.aengix.hopper.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.ssh.SSHHopConnector
import com.aengix.hopper.ssh.SSHHopSession
import com.aengix.hopper.tunnel.IPTunnelEngine
import com.aengix.hopper.util.TunnelLog
import kotlinx.coroutines.delay
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetAddress

class TunnelCoordinator(
    private val vpnService: VpnService,
) {
    var onSessionFailure: ((String) -> Unit)? = null

    private var sshSession: SSHHopSession? = null
    private var ipEngine: IPTunnelEngine? = null
    private var tunInterface: ParcelFileDescriptor? = null

    suspend fun prepare(hop: HopNodeProfile): ParcelFileDescriptor {
        val builder = vpnService.Builder()
        builder.setSession(HopConstants.APP_DISPLAY_NAME)
        builder.setMtu(HopConstants.TUNNEL_MTU)
        builder.addAddress(HopConstants.TUNNEL_IPV4_ADDRESS, 24)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")

        resolveIPv4(hop.trimmedHost)?.let { entryIp ->
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                builder.excludeRoute(android.net.IpPrefix(InetAddress.getByName(entryIp), 32))
            }
            TunnelLog.info("Entry hop excluded from routes: $entryIp")
        }

        val iface = establishInterface(builder)
        tunInterface = iface

        TunnelLog.info("SSH entry ${hop.trimmedUser}@${hop.trimmedHost}:${hop.port}")
        sshSession = SSHHopConnector.connect(entry = hop) { socket ->
            vpnService.protect(socket)
        }
        return iface
    }

    private suspend fun establishInterface(builder: VpnService.Builder): ParcelFileDescriptor {
        val retryDelaysMs = listOf(0L, 300L, 700L, 1500L)
        for ((attempt, delayMs) in retryDelaysMs.withIndex()) {
            if (delayMs > 0) {
                TunnelLog.info("VPN establish retry ${attempt + 1}/${retryDelaysMs.size} after ${delayMs}ms")
                delay(delayMs)
            }
            builder.establish()?.let { return it }
        }
        throw TunnelCoordinatorException(VPN_INTERFACE_UNAVAILABLE)
    }

    fun startRelay(tunInterface: ParcelFileDescriptor) {
        val stream = sshSession?.chainStream
            ?: throw TunnelCoordinatorException("SSH chain stream is not available.")

        val input = FileInputStream(tunInterface.fileDescriptor)
        val output = FileOutputStream(tunInterface.fileDescriptor)
        val engine = IPTunnelEngine(stream, input, output)
        engine.onFailure = { message -> handleFailure(message) }
        ipEngine = engine
        engine.start()
        TunnelLog.info("L3 iptunnel engine running")
    }

    fun stop() {
        ipEngine?.stop()
        ipEngine = null

        runCatching { tunInterface?.close() }
        tunInterface = null

        val session = sshSession
        sshSession = null
        session?.chainStream?.close()
        runCatching { session?.client?.disconnect() }
    }

    private fun handleFailure(message: String) {
        TunnelLog.error(message)
        onSessionFailure?.invoke(message)
    }

    private fun resolveIPv4(host: String): String? {
        return runCatching {
            InetAddress.getByName(host).hostAddress?.takeIf { it.contains('.') }
        }.getOrNull()
    }
}

const val VPN_INTERFACE_UNAVAILABLE =
    "Could not establish VPN interface. If another VPN is active, disconnect it or confirm the system prompt to switch, then try again."

class TunnelCoordinatorException(message: String) : Exception(message)

object TunnelBootstrap {
    const val HOP_KEY = "hop"

    fun hopJson(hop: HopNodeProfile): String = Json.encodeToString(hop)
}

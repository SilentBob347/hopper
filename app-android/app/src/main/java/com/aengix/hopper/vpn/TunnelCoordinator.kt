package com.aengix.hopper.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.ssh.SSHHopConnector
import com.aengix.hopper.ssh.SSHHopSession
import com.aengix.hopper.tunnel.IPTunnelEngine
import com.aengix.hopper.util.HopErrorDetails
import com.aengix.hopper.util.TunnelLog
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

    fun prepare(hop: HopNodeProfile): ParcelFileDescriptor {
        TunnelLog.info("SSH entry ${hop.trimmedUser}@${hop.trimmedHost}:${hop.port}")
        val session = SSHHopConnector.connect(entry = hop) { socket ->
            vpnService.protect(socket)
        }
        sshSession = session

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

        val iface = builder.establish()
            ?: throw TunnelCoordinatorException("Could not establish VPN interface.")
        tunInterface = iface
        return iface
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

class TunnelCoordinatorException(message: String) : Exception(message)

object TunnelBootstrap {
    const val HOP_KEY = "hop"

    fun hopJson(hop: HopNodeProfile): String = Json.encodeToString(hop)
}

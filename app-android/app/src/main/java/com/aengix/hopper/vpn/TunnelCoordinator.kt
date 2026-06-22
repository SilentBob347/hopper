package com.aengix.hopper.vpn

import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import com.aengix.hopper.model.ChainTopology
import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.model.TunnelConnectContext
import com.aengix.hopper.ssh.SSHHopConnector
import com.aengix.hopper.ssh.SSHHopSession
import com.aengix.hopper.tunnel.IPTunnelAssignClient
import com.aengix.hopper.tunnel.IPTunnelEngine
import com.aengix.hopper.util.IPv4Only
import com.aengix.hopper.util.TunnelLog
import kotlinx.coroutines.delay
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.Inet4Address

data class TunnelPrepareResult(
    val tunInterface: ParcelFileDescriptor,
    val sinkholeIPv6: Boolean,
)

class TunnelCoordinator(
    private val vpnService: VpnService,
) {
    var onSessionFailure: ((String) -> Unit)? = null

    private var sshSession: SSHHopSession? = null
    private var ipEngine: IPTunnelEngine? = null
    private var tunInterface: ParcelFileDescriptor? = null
    private var sinkholeIPv6 = false

    suspend fun prepare(hop: HopNodeProfile, context: TunnelConnectContext): TunnelPrepareResult {
        TunnelLog.info("SSH entry ${hop.trimmedUser}@${hop.trimmedHost}:${hop.port} chain=${context.chainId}")
        sshSession = SSHHopConnector.connect(entry = hop, hopperPort = context.hopperPort) { socket ->
            val protected = vpnService.protect(socket)
            if (!protected) {
                TunnelLog.error("VPN protect() failed for entry SSH socket")
            }
            protected
        }

        val clientIP = IPTunnelAssignClient.performAssign(
            stream = sshSession!!.chainStream,
            deviceId = context.deviceId,
            chainId = context.chainId,
        )
        TunnelLog.info("Assigned client overlay IP: $clientIP")

        val builder = vpnService.Builder()
        builder.setSession(HopConstants.APP_DISPLAY_NAME)
        builder.setMtu(HopConstants.TUNNEL_MTU)
        builder.addAddress(clientIP, HopConstants.TUNNEL_IPV4_MASK_BITS)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("8.8.8.8")
        sinkholeIPv6 = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
        if (sinkholeIPv6) {
            builder.addAddress(HopConstants.TUNNEL_IPV6_SINKHOLE, 128)
            builder.addRoute("::", 0)
            TunnelLog.info("IPv6 sinkhole enabled (pre-Android 10)")
        }

        runCatching { IPv4Only.resolveHost(hop.trimmedHost) }.getOrNull()?.let { entryIp ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                builder.excludeRoute(
                    android.net.IpPrefix(Inet4Address.getByName(entryIp), 32),
                )
            }
            TunnelLog.info("Entry hop excluded from routes: $entryIp")
        }

        val overlaySubnet = ChainTopology.overlaySubnet(context.chainId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            builder.excludeRoute(
                android.net.IpPrefix(Inet4Address.getByName(overlaySubnet), 24),
            )
        }

        val iface = establishInterface(builder)
        tunInterface = iface
        delay(500)

        return TunnelPrepareResult(iface, sinkholeIPv6)
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
        val engine = IPTunnelEngine(stream, input, output, dropNonIPv4 = sinkholeIPv6)
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
}

const val VPN_INTERFACE_UNAVAILABLE =
    "Could not establish VPN interface. If another VPN is active, disconnect it or confirm the system prompt to switch, then try again."

class TunnelCoordinatorException(message: String) : Exception(message)

object TunnelBootstrap {
    const val HOP_KEY = "hop"
    const val CONTEXT_KEY = "context"

    fun hopJson(hop: HopNodeProfile): String = Json.encodeToString(hop)

    fun contextJson(context: TunnelConnectContext): String = Json.encodeToString(context)
}

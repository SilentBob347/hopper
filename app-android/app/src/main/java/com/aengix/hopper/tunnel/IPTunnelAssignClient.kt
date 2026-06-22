package com.aengix.hopper.tunnel

import com.aengix.hopper.ssh.SSHByteStream
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
private data class AssignRequest(
    val device_id: String,
    val chain_id: String,
)

@Serializable
private data class AssignResponse(
    val addr: String? = null,
    val lease_ttl: Int? = null,
    val error: String? = null,
)

object IPTunnelAssignClient {
    private val json = Json { ignoreUnknownKeys = true }

    fun performAssign(stream: SSHByteStream, deviceId: String, chainId: String): String {
        val req = AssignRequest(device_id = deviceId, chain_id = chainId)
        val reqFrame = IPTunnelFrame(IPTunnelFrameType.ASSIGN_REQ, json.encodeToString(req).toByteArray())
        stream.write(reqFrame.encoded())

        val header = stream.readFully(IPTunnelFrame.HEADER_LENGTH)
        val payloadLength = ((header[2].toInt() and 0xFF) shl 8) or (header[3].toInt() and 0xFF)
        val payload = if (payloadLength > 0) stream.readFully(payloadLength) else ByteArray(0)
        val responseBytes = header + payload
        val respFrame = IPTunnelFrame.decode(responseBytes)
        if (respFrame.type != IPTunnelFrameType.ASSIGN_RESP) {
            throw IPTunnelProtocolException("expected assign response")
        }
        val resp = json.decodeFromString<AssignResponse>(respFrame.payload.decodeToString())
        resp.error?.let { throw IPTunnelProtocolException(it) }
        return resp.addr ?: throw IPTunnelProtocolException("missing addr")
    }
}

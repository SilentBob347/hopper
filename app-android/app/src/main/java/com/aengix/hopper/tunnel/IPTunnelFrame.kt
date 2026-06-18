package com.aengix.hopper.tunnel

enum class IPTunnelFrameType(val raw: Byte) {
    DATA(1),
    KEEPALIVE(2),
    ;

    companion object {
        fun fromRaw(value: Byte): IPTunnelFrameType? = entries.firstOrNull { it.raw == value }
    }
}

class IPTunnelProtocolException(message: String) : Exception(message)

data class IPTunnelFrame(
    val type: IPTunnelFrameType,
    val payload: ByteArray = ByteArray(0),
) {
    fun encoded(): ByteArray {
        val body = payload
        val data = ByteArray(HEADER_LENGTH + body.size)
        data[0] = 1
        data[1] = type.raw
        data.storeUInt16BE(body.size, 2)
        if (body.isNotEmpty()) {
            body.copyInto(data, HEADER_LENGTH)
        }
        return data
    }

    companion object {
        const val HEADER_LENGTH = 4
        const val MAX_PACKET_LENGTH = 65_535

        fun decode(data: ByteArray): IPTunnelFrame {
            if (data.size < HEADER_LENGTH) throw IPTunnelProtocolException("truncated")
            if (data[0] != 1.toByte()) throw IPTunnelProtocolException("badVersion")

            val type = IPTunnelFrameType.fromRaw(data[1])
                ?: throw IPTunnelProtocolException("badType")

            val payloadLength = data.uint16BE(2)
            if (payloadLength > MAX_PACKET_LENGTH) throw IPTunnelProtocolException("packetTooLarge")

            return when (type) {
                IPTunnelFrameType.DATA -> {
                    if (payloadLength <= 0 || data.size < HEADER_LENGTH + payloadLength) {
                        throw IPTunnelProtocolException("truncated")
                    }
                    IPTunnelFrame(type, data.copyOfRange(HEADER_LENGTH, HEADER_LENGTH + payloadLength))
                }
                IPTunnelFrameType.KEEPALIVE -> {
                    if (payloadLength != 0) throw IPTunnelProtocolException("truncated")
                    IPTunnelFrame(type)
                }
            }
        }
    }
}

private fun ByteArray.uint16BE(offset: Int): Int =
    ((this[offset].toInt() and 0xFF) shl 8) or (this[offset + 1].toInt() and 0xFF)

private fun ByteArray.storeUInt16BE(value: Int, offset: Int) {
    this[offset] = ((value shr 8) and 0xFF).toByte()
    this[offset + 1] = (value and 0xFF).toByte()
}

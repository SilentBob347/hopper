package com.aengix.hopper.model

object ChainTopology {
    fun chainOctet(chainId: String): Int {
        val hex = chainId.replace("-", "")
        var hash = 2_166_136_261L
        for (ch in hex.toByteArray(Charsets.UTF_8)) {
            hash = hash xor ch.toLong()
            hash = (hash * 16_777_619L) and 0xFFFF_FFFFL
        }
        return (1 + (hash % 254)).toInt()
    }

    fun overlayCIDR(chainId: String): String = "10.64.${chainOctet(chainId)}.0/24"

    fun overlaySubnet(chainId: String): String = "10.64.${chainOctet(chainId)}.0"

    fun listenPort(chainId: String): Int = 7400 + chainOctet(chainId)

    fun overlayAddr(chainId: String, index: Int): String =
        "10.64.${chainOctet(chainId)}.${HopConstants.OVERLAY_NODE_OCTET + index}"
}

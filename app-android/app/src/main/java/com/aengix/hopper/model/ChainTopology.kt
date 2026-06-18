package com.aengix.hopper.model

object ChainTopology {
    fun overlayAddr(index: Int): String =
        "10.64.0.${HopConstants.OVERLAY_NODE_OCTET + index}"
}

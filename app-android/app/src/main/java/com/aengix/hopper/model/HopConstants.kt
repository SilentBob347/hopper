package com.aengix.hopper.model

import android.content.Context

object HopConstants {
    const val APP_DISPLAY_NAME = "ɹǝddoH"
    const val PROFILE_STORE_FILE_NAME = "hopper-profiles.json"
    const val TUNNEL_LAST_ERROR_FILE_NAME = "last-tunnel-error.txt"

    const val TUNNEL_IPV4_ADDRESS = "10.64.0.2"
    const val TUNNEL_IPV4_MASK = "255.255.255.0"
    const val TUNNEL_REMOTE_ADDRESS = "10.64.0.1"
    const val TUNNEL_IPV4_SUBNET = "10.64.0.0/24"
    /** Dummy IPv6 address used to sinkhole IPv6 on Android versions before 10. */
    const val TUNNEL_IPV6_SINKHOLE = "fd00::1"

    const val HOPPER_PORT = 7400
    const val TUNNEL_MTU = 1280

    const val DEFAULT_SSH_PORT = 22
    const val DEFAULT_INSTALL_DIR = "~/hopper"

    const val OVERLAY_NODE_OCTET = 10

    fun appVersion(context: Context): String = runCatching {
        @Suppress("DEPRECATION")
        context.packageManager.getPackageInfo(context.packageName, 0).versionName
    }.getOrNull() ?: "?"
}

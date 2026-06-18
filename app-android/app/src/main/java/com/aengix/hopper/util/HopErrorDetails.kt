package com.aengix.hopper.util

object HopErrorDetails {
    fun describe(error: Throwable): String {
        val message = error.message.orEmpty()
        val rendered = error.toString()

        if (rendered.contains("NoSuchAlgorithmException", ignoreCase = true) ||
            rendered.contains("no such algorithm", ignoreCase = true) ||
            rendered.contains("X25519", ignoreCase = true)
        ) {
            return "SSH crypto provider error — reinstall the app and retry. ($rendered)"
        }
        if (rendered.contains("keyExchangeNegotiationFailure", ignoreCase = true)) {
            return "SSH key exchange failed — server must offer curve25519-sha256 or ecdh-sha2-nistp256. ($rendered)"
        }
        if (rendered.contains("channelSetupRejected", ignoreCase = true)) {
            return "SSH channel rejected — is hopperd running? Check: pgrep -af hopperd on the server. ($rendered)"
        }
        if (rendered.contains("Exhausted available authentication methods", ignoreCase = true) ||
            rendered.contains("invalidUserAuthSignature", ignoreCase = true) ||
            rendered.contains("Auth fail", ignoreCase = true)
        ) {
            return "SSH authentication failed — re-scan the hop QR code or re-import the server config. ($rendered)"
        }
        if (rendered.contains("tcpShutdown", ignoreCase = true) ||
            rendered.contains("Connection reset", ignoreCase = true)
        ) {
            return "SSH connection closed unexpectedly. Wait 5 seconds before reconnecting. ($rendered)"
        }
        if (rendered.contains("connectTimeout", ignoreCase = true) ||
            rendered.contains("timed out", ignoreCase = true)
        ) {
            return "SSH login timed out — check network reachability to the entry hop, then retry. ($rendered)"
        }
        if (message.isNotEmpty() && !message.contains("NIOSSH", ignoreCase = true)) {
            return message
        }
        return rendered.ifEmpty { "Tunnel error" }
    }

    fun describeMessage(message: String): String = message
}

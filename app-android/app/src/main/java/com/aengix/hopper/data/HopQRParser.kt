package com.aengix.hopper.data

import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.ssh.HopKeyProviders
import org.json.JSONObject

object HopQRParser {
    sealed class ParseError(message: String) : Exception(message) {
        data object EmptyPayload : ParseError("The QR code is empty.")
        data object InvalidJson : ParseError("The QR code contains invalid JSON.")
        data object MissingHost : ParseError("The hop config is missing a host.")
        data object MissingUser : ParseError("The hop config is missing a user.")
        data object MissingPrivateKey : ParseError("The hop config is missing a private key.")
    }

    fun parse(payload: String): HopNodeProfile {
        val trimmed = payload.trim()
        if (trimmed.isEmpty()) throw ParseError.EmptyPayload

        val json = runCatching { JSONObject(trimmed) }.getOrElse { throw ParseError.InvalidJson }

        val host = stringValue(json, "host", "server")?.trim().orEmpty()
        if (host.isEmpty()) throw ParseError.MissingHost

        val user = stringValue(json, "user", "username")?.trim().orEmpty()
        if (user.isEmpty()) throw ParseError.MissingUser

        val privateKey = HopKeyProviders.normalizePrivateKey(
            stringValue(json, "private_key", "privateKey").orEmpty(),
        )
        if (privateKey.isEmpty()) throw ParseError.MissingPrivateKey

        val portString = stringValue(json, "port") ?: HopConstants.DEFAULT_SSH_PORT.toString()
        val port = portString.toIntOrNull() ?: HopConstants.DEFAULT_SSH_PORT

        val hostKeys = when (val value = json.opt("host_key")) {
            is org.json.JSONArray -> (0 until value.length()).mapNotNull { index ->
                value.optString(index).takeIf { it.isNotEmpty() }
            }
            is String -> if (value.isNotEmpty()) listOf(value) else emptyList()
            else -> emptyList()
        }

        val installDir = stringValue(json, "install_dir", "installDir", "hopper_dir").orEmpty()

        return HopNodeProfile(
            name = stringValue(json, "name", "title", "remarks").orEmpty(),
            host = host,
            port = port,
            user = user,
            privateKey = privateKey,
            hostKeys = hostKeys,
            installDir = installDir,
        )
    }

    private fun stringValue(json: JSONObject, vararg keys: String): String? {
        for (key in keys) {
            val iterator = json.keys()
            while (iterator.hasNext()) {
                val existing = iterator.next()
                if (!existing.equals(key, ignoreCase = true)) continue
                val value = json.opt(existing)
                when (value) {
                    is String -> return value
                    is Number -> return value.toString()
                }
            }
        }
        return null
    }
}

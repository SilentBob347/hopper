package com.aengix.hopper.data

import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.ssh.HopKeyProviders
import org.json.JSONArray
import org.json.JSONObject

/** Wire-format codec for hopper node profile v2 (server configure / QR / export). */
object HopProfileCodec {
    const val PROFILE_VERSION = 2
    const val UNKNOWN_VERSION = "unknown"

    object Field {
        const val VERSION = "v"
        const val NAME = "name"
        const val HOST = "host"
        const val PORT = "port"
        const val USER = "user"
        const val PRIVATE_KEY = "private_key"
        const val INSTALL_DIR = "install_dir"
        const val SERVER_VERSION = "server_version"
        const val MIN_APP_VERSION = "min_app_version"
        const val HOST_KEY = "host_key"
    }

    fun exportJson(profile: HopNodeProfile): JSONObject {
        val json = JSONObject()
        json.put(Field.VERSION, PROFILE_VERSION)
        json.put(Field.NAME, exportName(profile))
        json.put(Field.HOST, profile.trimmedHost)
        json.put(Field.PORT, profile.port.toString())
        json.put(Field.USER, profile.trimmedUser)
        json.put(Field.PRIVATE_KEY, profile.privateKey)
        json.put(Field.INSTALL_DIR, profile.resolvedInstallDir)
        json.put(
            Field.SERVER_VERSION,
            profile.serverVersion.trim().ifEmpty { UNKNOWN_VERSION },
        )
        json.put(
            Field.MIN_APP_VERSION,
            profile.minAppVersion.trim().ifEmpty { UNKNOWN_VERSION },
        )
        if (profile.hostKeys.isNotEmpty()) {
            json.put(Field.HOST_KEY, JSONArray(profile.hostKeys))
        }
        return json
    }

    fun parse(payload: String): HopNodeProfile {
        val trimmed = payload.trim()
        if (trimmed.isEmpty()) throw HopQRParser.ParseError.EmptyPayload

        val json = runCatching { JSONObject(trimmed) }.getOrElse { throw HopQRParser.ParseError.InvalidJson }

        if (json.has(Field.VERSION)) {
            val version = json.optInt(Field.VERSION, -1)
            if (version != PROFILE_VERSION) throw HopQRParser.ParseError.InvalidJson
        }

        val host = stringValue(json, Field.HOST, "server")?.trim().orEmpty()
        if (host.isEmpty()) throw HopQRParser.ParseError.MissingHost

        val user = stringValue(json, Field.USER, "username")?.trim().orEmpty()
        if (user.isEmpty()) throw HopQRParser.ParseError.MissingUser

        val privateKey = HopKeyProviders.normalizePrivateKey(
            stringValue(json, Field.PRIVATE_KEY, "privateKey").orEmpty(),
        )
        if (privateKey.isEmpty()) throw HopQRParser.ParseError.MissingPrivateKey

        val portString = stringValue(json, Field.PORT) ?: HopConstants.DEFAULT_SSH_PORT.toString()
        val port = portString.toIntOrNull() ?: HopConstants.DEFAULT_SSH_PORT

        return HopNodeProfile(
            name = stringValue(json, Field.NAME, "title", "remarks").orEmpty(),
            host = host,
            port = port,
            user = user,
            privateKey = privateKey,
            hostKeys = parseHostKeys(json),
            installDir = stringValue(json, Field.INSTALL_DIR, "installDir", "hopper_dir").orEmpty(),
            serverVersion = stringValue(json, Field.SERVER_VERSION, "serverVersion").orEmpty(),
            minAppVersion = stringValue(json, Field.MIN_APP_VERSION, "minAppVersion").orEmpty(),
        )
    }

    private fun exportName(profile: HopNodeProfile): String = when {
        profile.trimmedName.isNotEmpty() -> profile.trimmedName
        profile.trimmedHost.isNotEmpty() -> profile.trimmedHost
        else -> "Untitled"
    }

    private fun parseHostKeys(json: JSONObject): List<String> {
        val fromHostKey = when (val value = json.opt(Field.HOST_KEY)) {
            is JSONArray -> (0 until value.length()).mapNotNull { index ->
                value.optString(index).takeIf { it.isNotEmpty() }
            }
            is String -> if (value.isNotEmpty()) listOf(value) else emptyList()
            else -> emptyList()
        }
        if (fromHostKey.isNotEmpty()) return fromHostKey

        return when (val value = json.opt("hostKeys")) {
            is JSONArray -> (0 until value.length()).mapNotNull { index ->
                value.optString(index).takeIf { it.isNotEmpty() }
            }
            is String -> if (value.isNotEmpty()) listOf(value) else emptyList()
            else -> emptyList()
        }
    }

    private fun stringValue(json: JSONObject, vararg keys: String): String? {
        for (key in keys) {
            val iterator = json.keys()
            while (iterator.hasNext()) {
                val existing = iterator.next()
                if (!existing.equals(key, ignoreCase = true)) continue
                when (val value = json.opt(existing)) {
                    is String -> return value
                    is Number -> return value.toString()
                }
            }
        }
        return null
    }
}

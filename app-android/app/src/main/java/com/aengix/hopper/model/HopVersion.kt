package com.aengix.hopper.model

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.BufferedReader
import java.io.InputStreamReader

@Serializable
data class VersionManifest(
    val version: String,
    val min_app_version: String,
    val min_server_version: String,
    val protocol_version: Int = 2,
)

@Serializable
data class ServerVersionInfo(
    val version: String? = null,
    val min_app_version: String? = null,
)

object HopVersion {
    lateinit var manifest: VersionManifest
        private set

    private val json = Json { ignoreUnknownKeys = true }

    fun init(context: Context) {
        manifest = loadManifest(context)
    }

    private fun loadManifest(context: Context): VersionManifest {
        val fallback = VersionManifest("2.6.0", "2.6.0", "2.0.0", 2)
        return runCatching {
            context.assets.open("VERSION.json").use { stream ->
                val text = BufferedReader(InputStreamReader(stream)).readText()
                json.decodeFromString<VersionManifest>(text)
            }
        }.getOrElse { fallback }
    }
}

object SemVer {
    fun compare(lhs: String, rhs: String): Int {
        val a = parts(lhs)
        val b = parts(rhs)
        val n = maxOf(a.size, b.size)
        for (i in 0 until n) {
            val av = a.getOrElse(i) { 0 }
            val bv = b.getOrElse(i) { 0 }
            if (av != bv) return av.compareTo(bv)
        }
        return 0
    }

    private fun parts(value: String): List<Int> =
        value.split('.').take(3).mapNotNull { it.toIntOrNull() }
}

enum class VersionCheckOutcome {
    Compatible,
    AppTooOld,
    ServerTooOld,
}

data class ServerUpdatePrompt(
    val hopNames: List<String>,
    val hops: List<HopNodeProfile>,
    val targetVersion: String,
)

@Serializable
data class TunnelConnectContext(
    val chainId: String,
    val hopperPort: Int,
    val overlayCIDR: String,
    val deviceId: String,
)

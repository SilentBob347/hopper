package com.aengix.hopper.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class HopReadyReport(
    val ready: Boolean,
    val mode: String,
    val addr: String,
    val index: Int,
    val overlay: String,
    val port: Int,
    val listen_port: Int? = null,
    val chain_id: String? = null,
    val nat: Boolean? = null,
) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun parse(output: String): HopReadyReport {
            val lines = output.lines()
                .map { it.trim() }
                .filter { it.isNotEmpty() }

            for (line in lines.asReversed()) {
                if (!line.startsWith("{")) continue
                runCatching {
                    val report = json.decodeFromString<HopReadyReport>(line)
                    if (report.ready) return report
                }
            }
            throw IllegalStateException("Server did not return ready JSON. Output: ${output.takeLast(200)}")
        }
    }
}

@Serializable
data class ChainStatusReport(
    val host: String? = null,
    val server_version: String? = null,
    val min_app_version: String? = null,
    val checked_at: String? = null,
    val chains: List<ChainStatusEntry> = emptyList(),
)

@Serializable
data class ChainStatusEntry(
    val chain_id: String? = null,
    val overlay: String? = null,
    val listen_port: Int? = null,
    val role: String? = null,
    val hop_addr: String? = null,
    val started_at: String? = null,
    val running: Boolean? = null,
    val last_activity: String? = null,
    val sessions: List<ChainSessionStatus> = emptyList(),
)

@Serializable
data class ChainSessionStatus(
    val client_addr: String? = null,
    val device_id: String? = null,
    val connected_at: String? = null,
    val last_seen: String? = null,
    val remote: String? = null,
)

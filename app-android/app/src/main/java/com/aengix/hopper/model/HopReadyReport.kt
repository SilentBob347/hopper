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

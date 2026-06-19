package com.aengix.hopper.ssh

import com.aengix.hopper.model.HopConstants
import com.aengix.hopper.model.HopNodeProfile
import com.aengix.hopper.util.HopErrorDetails
import com.aengix.hopper.util.IPv4Only
import com.aengix.hopper.util.TunnelLog
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.connection.channel.direct.DirectConnection
import net.schmizz.sshj.transport.verification.PromiscuousVerifier
import net.schmizz.sshj.userauth.UserAuthException
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket

class HopSSHException(message: String) : Exception(message)

object HopSSH {
    fun connect(
        node: HopNodeProfile,
        onProtect: ((Socket) -> Boolean)? = null,
    ): SSHClient {
        HopSecurityProviders.ensureRegistered()
        val host = IPv4Only.resolveHost(node.trimmedHost)
        val retryDelaysMs = listOf(0L, 300L, 700L, 1500L)
        var lastError: Throwable? = null

        for ((attempt, delayMs) in retryDelaysMs.withIndex()) {
            if (delayMs > 0) {
                TunnelLog.info("SSH connect retry ${attempt + 1}/${retryDelaysMs.size} after ${delayMs}ms")
                Thread.sleep(delayMs)
            }

            val sshClient = SSHClient()
            sshClient.addHostKeyVerifier(PromiscuousVerifier())
            sshClient.socketFactory = IPv4Only.socketFactory(onProtect)

            try {
                TunnelLog.info("SSH connect to ${node.trimmedUser}@$host:${node.port}")
                sshClient.connect(host, node.port)
                sshClient.timeout = 60_000

                val keyProvider = HopKeyProviders.keyProviderFor(node.privateKey)
                sshClient.authPublickey(node.trimmedUser, keyProvider)
                return sshClient
            } catch (error: UserAuthException) {
                runCatching { sshClient.disconnect() }
                TunnelLog.error("SSH auth failed for ${node.trimmedUser}@${node.trimmedHost}: ${error.message}")
                throw error
            } catch (error: Throwable) {
                lastError = error
                runCatching { sshClient.disconnect() }
                if (!isRetryableConnectError(error) || attempt == retryDelaysMs.lastIndex) {
                    throw error
                }
                TunnelLog.info("SSH connect attempt ${attempt + 1} failed: ${HopErrorDetails.describe(error)}")
            }
        }

        throw lastError ?: HopSSHException("SSH connect failed")
    }

    fun runCommand(sshClient: SSHClient, command: String): String {
        sshClient.startSession().use { session ->
            session.exec(command).use { commandSession ->
                val output = commandSession.inputStream.bufferedReader().readText()
                val exitStatus = commandSession.exitStatus
                if (exitStatus != null && exitStatus != 0) {
                    val stderr = commandSession.errorStream.bufferedReader().readText()
                    TunnelLog.error("Command failed ($exitStatus): $stderr")
                }
                return output
            }
        }
    }

    fun <T> withSession(
        node: HopNodeProfile,
        onProtect: ((Socket) -> Boolean)? = null,
        block: (SSHClient) -> T,
    ): T {
        val sshClient = connect(node, onProtect)
        return try {
            block(sshClient)
        } finally {
            runCatching { sshClient.disconnect() }
        }
    }

    private fun isRetryableConnectError(error: Throwable): Boolean {
        val rendered = error.toString() + (error.message.orEmpty())
        return rendered.contains("ECONNABORTED", ignoreCase = true) ||
            rendered.contains("connection abort", ignoreCase = true) ||
            rendered.contains("Connection reset", ignoreCase = true) ||
            rendered.contains("ETIMEDOUT", ignoreCase = true) ||
            rendered.contains("ENETUNREACH", ignoreCase = true)
    }
}

class SSHByteStream(
    private val connection: DirectConnection,
) {
    private val input: InputStream = connection.inputStream
    private val output: OutputStream = connection.outputStream
    @Volatile
    private var closed = false

    fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (closed) throw SSHByteStreamException("SSH tunnel stream closed by the server — check ~/.hopper/hopper.log on the entry hop.")
        return input.read(buffer, offset, length)
    }

    fun write(data: ByteArray) {
        if (closed) throw SSHByteStreamException("SSH tunnel stream closed by the server — check ~/.hopper/hopper.log on the entry hop.")
        output.write(data)
        output.flush()
    }

    fun close() {
        closed = true
        runCatching { connection.close() }
    }
}

class SSHByteStreamException(message: String) : Exception(message)

data class SSHHopSession(
    val client: SSHClient,
    val chainStream: SSHByteStream,
)

object SSHHopConnector {
    fun connect(
        entry: HopNodeProfile,
        onProtect: ((Socket) -> Boolean)? = null,
    ): SSHHopSession {
        TunnelLog.info("SSH connect to ${entry.trimmedUser}@${entry.trimmedHost}:${entry.port}")
        val sshClient = HopSSH.connect(entry, onProtect)
        Thread.sleep(300)

        val chainStream = openChainStream(sshClient)
        return SSHHopSession(sshClient, chainStream)
    }

    private fun openChainStream(sshClient: SSHClient): SSHByteStream {
        var lastError: Throwable? = null
        repeat(6) { attempt ->
            if (attempt > 0) Thread.sleep(300)
            TunnelLog.info("Opening hopper stream to 127.0.0.1:${HopConstants.HOPPER_PORT} (attempt ${attempt + 1})")
            try {
                val connection = sshClient.newDirectConnection("127.0.0.1", HopConstants.HOPPER_PORT)
                return SSHByteStream(connection)
            } catch (error: Throwable) {
                lastError = error
                TunnelLog.error("Chain stream attempt ${attempt + 1} failed: ${HopErrorDetails.describe(error)}")
            }
        }
        throw SSHHopConnectorException(
            "Could not open chain tunnel: ${HopErrorDetails.describe(lastError ?: SSHByteStreamException("closed"))}",
        )
    }
}

class SSHHopConnectorException(message: String) : Exception(message)

private object HopErrorDetails {
    fun describe(error: Throwable): String = com.aengix.hopper.util.HopErrorDetails.describe(error)
}

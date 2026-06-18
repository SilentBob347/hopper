package com.aengix.hopper.ssh

import com.aengix.hopper.util.TunnelLog
import com.hierynomus.sshj.userauth.keyprovider.OpenSSHKeyV1KeyFile
import net.schmizz.sshj.userauth.keyprovider.FileKeyProvider
import net.schmizz.sshj.userauth.keyprovider.KeyFormat
import net.schmizz.sshj.userauth.keyprovider.KeyProvider
import net.schmizz.sshj.userauth.keyprovider.KeyProviderUtil
import net.schmizz.sshj.userauth.keyprovider.OpenSSHKeyFile
import java.io.StringReader

object HopKeyProviders {
    fun normalizePrivateKey(key: String): String =
        key.trim()
            .replace("\\n", "\n")
            .replace("\r\n", "\n")

    fun keyProviderFor(privateKeyPem: String): KeyProvider {
        HopSecurityProviders.ensureRegistered()
        val normalized = normalizePrivateKey(privateKeyPem)
        val format = KeyProviderUtil.detectKeyFileFormat(normalized, false)
        TunnelLog.info("Private key format: $format")

        val provider: FileKeyProvider = when (format) {
            KeyFormat.OpenSSHv1 -> OpenSSHKeyV1KeyFile()
            KeyFormat.OpenSSH, KeyFormat.PKCS8 -> OpenSSHKeyFile()
            else -> throw HopSSHException("Unsupported private key format: $format")
        }
        provider.init(StringReader(normalized))

        runCatching {
            val algorithm = provider.public?.algorithm ?: "unknown"
            TunnelLog.info("Loaded SSH key algorithm: $algorithm")
        }.onFailure { error ->
            TunnelLog.error("Failed to load private key: ${error.message}")
            throw HopSSHException("Invalid private key: ${error.message}")
        }

        return provider
    }
}

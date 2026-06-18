package com.aengix.hopper.ssh

import net.schmizz.sshj.common.SecurityUtils
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.security.Security

object HopSecurityProviders {
    @Volatile
    private var registered = false

    fun ensureRegistered() {
        if (registered) return
        synchronized(this) {
            if (registered) return
            Security.removeProvider(BouncyCastleProvider.PROVIDER_NAME)
            Security.insertProviderAt(BouncyCastleProvider(), 1)
            SecurityUtils.setSecurityProvider(SecurityUtils.BOUNCY_CASTLE)
            registered = true
        }
    }
}

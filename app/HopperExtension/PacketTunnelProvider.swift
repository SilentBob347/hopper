import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let coordinator = TunnelCoordinator()

    override func startTunnel(options startOptions: [String: NSObject]?) async throws {
        TunnelLog.info("startTunnel")
        ProfileStore.clearLastTunnelError()
        coordinator.onSessionFailure = { [weak self] message in
            self?.failTunnel(message)
        }

        do {
            let excluded = try await coordinator.prepare(options: startOptions)

            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: HopConstants.tunnelRemoteAddress)
            let ipv4 = NEIPv4Settings(
                addresses: [HopConstants.tunnelIPv4Address],
                subnetMasks: [HopConstants.tunnelIPv4Mask]
            )
            ipv4.includedRoutes = [NEIPv4Route.default()]
            var excludedRoutes = excluded.map {
                NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255")
            }
            excludedRoutes.append(NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"))
            excludedRoutes.append(NEIPv4Route(destinationAddress: "10.64.0.0", subnetMask: "255.255.255.0"))
            ipv4.excludedRoutes = excludedRoutes
            settings.ipv4Settings = ipv4

            let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
            dns.matchDomains = [""]
            settings.dnsSettings = dns

            let ipv6 = NEIPv6Settings()
            ipv6.includedRoutes = []
            ipv6.excludedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6

            settings.mtu = NSNumber(value: HopConstants.tunnelMTU)

            try await setTunnelNetworkSettings(settings)
            TunnelLog.info("TUN routes applied")
            coordinator.startRelay(packetFlow: packetFlow)
        } catch {
            failTunnel(HopErrorDetails.describe(error))
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        TunnelLog.info("stopTunnel: \(String(describing: reason))")
        if reason != .userInitiated && reason != .providerDisabled {
            ProfileStore.saveLastTunnelError("Tunnel stopped: \(String(describing: reason))")
        }
        coordinator.stop()
    }

    private func failTunnel(_ detail: String) {
        TunnelLog.error("Tunnel failed: \(detail)")
        ProfileStore.saveLastTunnelError(detail)
        coordinator.stop()
        cancelTunnelWithError(NSError(
            domain: HopConstants.mainBundleID,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: detail]
        ))
    }
}

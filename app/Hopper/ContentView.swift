import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var vpn: VPNController
    @State private var showConnectOptions = false

    var body: some View {
        NavigationStack {
            List {
                Section("Chain") {
                    if let chain = vpn.state.selectedChain {
                        Picker("Active chain", selection: Binding(
                            get: { vpn.state.selectedChainID },
                            set: { vpn.selectChain($0) }
                        )) {
                            ForEach(vpn.state.chains) { item in
                                Text(item.displayName).tag(Optional(item.id))
                            }
                        }

                        NavigationLink {
                            ChainDetailView(chainID: chain.id)
                        } label: {
                            Text(chainRouteSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No chain selected")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        ChainConfiguratorView()
                    } label: {
                        Label("Configure chains", systemImage: "link")
                    }
                }

                Section("Connect") {
                    if let entry = vpn.state.entryHop {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Entry: \(entry.displayName)").font(.headline)
                            Text("\(entry.trimmedUser)@\(entry.trimmedHost):\(entry.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Add servers and build a chain (entry → exit).")
                            .foregroundStyle(.secondary)
                    }

                    Button(vpn.isConnected ? "Disconnect" : "Connect") {
                        if vpn.isConnected || vpn.isBusy {
                            vpn.disconnect()
                        } else {
                            showConnectOptions = true
                        }
                    }
                    .disabled(vpn.isBusy || vpn.state.entryHop == nil || vpn.provisionStatus != nil)
                    .confirmationDialog(
                        "Connect to chain",
                        isPresented: $showConnectOptions,
                        titleVisibility: .visible
                    ) {
                        Button("Connect") {
                            Task { await vpn.connect(restartHopperd: false) }
                        }
                        Button("Connect & restart hopperd") {
                            Task { await vpn.connect(restartHopperd: true) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Restart hopperd on all nodes if you've changed the chain or are having connection issues on the servers. Leave off for faster reconnects.")
                    }

                    Text(statusLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let provision = vpn.provisionStatus {
                        Text(provision)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if let hops = optionalActiveHops, !hops.isEmpty {
                    Section("Route") {
                        ForEach(Array(hops.enumerated()), id: \.element.id) { index, hop in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chainRole(index: index, total: hops.count, hop: hop))
                                    .font(.subheadline)
                                Text("\(hop.trimmedUser)@\(hop.trimmedHost):\(hop.port)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = vpn.errorMessage {
                    Section("Error") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("\(HopConstants.appDisplayName) \(HopConstants.appVersion)")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Update servers?",
                isPresented: Binding(
                    get: { vpn.serverUpdatePrompt != nil },
                    set: { if !$0 { vpn.cancelServerUpdate() } }
                ),
                presenting: vpn.serverUpdatePrompt
            ) { prompt in
                Button("Update \(prompt.hops.count) hop(s)") {
                    Task { await vpn.confirmServerUpdate() }
                }
                Button("Cancel", role: .cancel) {
                    vpn.cancelServerUpdate()
                }
            } message: { prompt in
                Text("Server software is older than app v\(prompt.targetVersion). Update before connecting?")
            }
        }
    }

    private var optionalActiveHops: [HopNodeProfile]? {
        let hops = vpn.state.activeHops
        return hops.isEmpty ? nil : hops
    }

    private var chainRouteSummary: String {
        let hops = vpn.state.activeHops
        if hops.isEmpty { return "No servers in chain" }
        if hops.count == 1 { return hops[0].displayName }
        return "\(hops.first!.displayName) → \(hops.last!.displayName) (\(hops.count) hops)"
    }

    private func chainRole(index: Int, total: Int, hop: HopNodeProfile) -> String {
        let role: String
        if total == 1 {
            role = "Exit"
        } else if index == 0 {
            role = "Entry"
        } else if index == total - 1 {
            role = "Exit"
        } else {
            role = "Relay"
        }
        return "\(index + 1). \(role) — \(hop.displayName)"
    }

    private var statusLabel: String {
        switch vpn.vpnStatus {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .reasserting: return "Reconnecting…"
        case .disconnected: return "Disconnected"
        default: return "Not configured"
        }
    }
}

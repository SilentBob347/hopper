import SwiftUI

struct ChainConfiguratorView: View {
    @EnvironmentObject private var vpn: VPNController

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ServerLibraryView()
                } label: {
                    Label("Server library", systemImage: "server.rack")
                }
            } footer: {
                Text("Scan QR codes or import JSON here to add servers. Then build chains from those servers below.")
            }

            Section("Chains") {
                if vpn.state.chains.isEmpty {
                    Text("Create a chain and add servers in entry → exit order.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vpn.state.chains) { chain in
                        NavigationLink {
                            ChainDetailView(chainID: chain.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chain.displayName).font(.headline)
                                    Text(chainSummary(chain))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vpn.state.selectedChainID == chain.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Use") {
                                vpn.selectChain(chain.id)
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { offsets in vpn.deleteChains(at: offsets) }
                }

                Button {
                    let id = vpn.addChain()
                    vpn.selectChain(id)
                } label: {
                    Label("New chain", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Chains")
    }

    private func chainSummary(_ chain: HopChain) -> String {
        let hops = vpn.state.resolveHops(chain)
        if hops.isEmpty { return "No servers" }
        if hops.count == 1 { return "1 hop — \(hops[0].displayName)" }
        return "\(hops.count) hops — \(hops.first!.displayName) → \(hops.last!.displayName)"
    }
}

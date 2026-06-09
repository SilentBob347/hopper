import SwiftUI

struct ServerLibraryView: View {
    @EnvironmentObject private var vpn: VPNController
    @State private var showScanner = false

    var body: some View {
        List {
            if vpn.state.servers.isEmpty {
                ContentUnavailableView(
                    "No servers",
                    systemImage: "server.rack",
                    description: Text("Scan a QR code from configure_server.sh on each hop.")
                )
            } else {
                ForEach(vpn.state.servers) { server in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.displayName).font(.headline)
                        Text("\(server.trimmedUser)@\(server.trimmedHost):\(server.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in vpn.deleteServers(at: offsets) }
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Scan QR") { showScanner = true }
            }
        }
        .sheet(isPresented: $showScanner) {
            QRCodeScannerView { payload in
                do {
                    let hop = try HopQRParser.parse(payload)
                    vpn.addServer(hop)
                    showScanner = false
                } catch {
                    vpn.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

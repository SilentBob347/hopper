import SwiftUI

struct ChainExportView: View {
    let chainName: String
    let hops: [HopNodeProfile]
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var errorMessage: String?

    private var payload: HopperConf.Payload {
        .chain(name: chainName, hops: hops)
    }

    private var qrJSON: String {
        (try? HopperConf.qrPayloadJSON(for: payload)) ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Scan on another device to import this chain and its servers. The QR is only for in-person transfer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if hops.isEmpty {
                        Text("Add servers to this chain before exporting.")
                            .foregroundStyle(.secondary)
                    } else if let qr = HopQRCodeImage.make(from: qrJSON) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    } else {
                        Text("Could not generate QR code (payload may be too large). Use Share file instead.")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("QR (device to device)")
                }

                Section {
                    SecureField("Optional encryption password", text: $password)
                    Text("Leave empty to use the default password. The file always encrypts private keys.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Share .hopperconf…") {
                        shareFile()
                    }
                    .disabled(hops.isEmpty)
                } header: {
                    Text("Share file")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export chain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func shareFile() {
        errorMessage = nil
        do {
            let data = try HopperConf.encryptFile(payload: payload, password: password)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(HopperConf.suggestedFileName(for: payload))
            try data.write(to: url, options: .atomic)
            HopperConfSharePresenter.present(fileURL: url) {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

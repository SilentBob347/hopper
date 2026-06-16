import SwiftUI

struct HopImportJSONView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: (HopNodeProfile) -> Void

    @State private var jsonText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste hop config JSON from deploy.sh (copy from the browser page).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $jsonText)
                    .font(.system(.caption, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Import JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importJSON() }
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importJSON() {
        errorMessage = nil
        do {
            let hop = try HopQRParser.parse(jsonText)
            onImport(hop)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

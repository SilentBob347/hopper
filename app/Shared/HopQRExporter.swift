import Foundation

enum HopQRExporter {
    static func exportJSON(_ profile: HopNodeProfile) -> String {
        let dict = HopProfileCodec.exportDictionary(profile)
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]))
            ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

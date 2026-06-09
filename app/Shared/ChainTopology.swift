import Foundation

enum ChainTopology {
    /// Overlay address for hop at chain index (0 = entry, last = exit).
    static func overlayAddr(index: Int) -> String {
        "10.64.0.\(HopConstants.overlayNodeOctet + index)"
    }
}

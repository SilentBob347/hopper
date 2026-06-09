import Foundation

enum HopConstants {
    static let appDisplayName = "ɹǝddoH"

    static let appGroupID = "group.com.aengix.hopper"
    static let mainBundleID = "com.aengix.hopper"
    static let tunnelBundleID = "com.aengix.hopper.tunnel"

    static let profileStoreFileName = "hopper-profiles.json"
    static let tunnelLastErrorFileName = "last-tunnel-error.txt"

    /// Client address on the overlay network (see server hopper.json).
    static let tunnelIPv4Address = "10.64.0.2"
    static let tunnelIPv4Mask = "255.255.255.0"
    static let tunnelRemoteAddress = "10.64.0.1"
    static let tunnelIPv4Subnet = "10.64.0.0/24"

    static let hopperPort = 7400
    static let tunnelMTU = 1280

    static let defaultSSHPort = 22
    static let defaultInstallDir = "~/hopper"

    /// First overlay address octet for hop index 0 (entry).
    static let overlayNodeOctet = 10
}

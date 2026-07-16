import ArgumentParser
import Foundation
import MobileDevice

struct DevicesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List attached iOS devices."
    )

    @Flag(name: .long, help: "Emit structured JSON.")
    var json = false

    func run() throws {
        let devices = try DeviceApps.summaries()
        if json {
            let payload = devices.map { device in
                [
                    "udid": device.udid,
                    "connectionType": device.connectionType,
                    "name": device.name as Any,
                    "productType": device.productType as Any,
                    "productVersion": device.productVersion as Any,
                ] as [String: Any]
            }
            try emit(jsonText(payload), to: nil)
            return
        }
        guard !devices.isEmpty else {
            print("No iOS devices attached.")
            return
        }
        for device in devices {
            print("\(device.udid)  \(device.connectionType.padded(to: 8))\(device.label)")
        }
    }
}

struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List apps installed on an attached iOS device, and whether each is FairPlay-encrypted.",
        discussion: """
        Talks to the device over usbmux → lockdown → installation_proxy. No root \
        required: the pairing record is fetched through usbmuxd rather than read \
        from /var/db/lockdown.

        Encryption is reported from the app's FairPlay ApplicationSINF blob, which \
        App Store builds carry and development-signed and system apps do not. An \
        encrypted app's __TEXT cannot be disassembled without decryption, so \
        `swiftdc analyze` on its binary will warn about cryptid.
        """
    )

    @Option(name: .long, help: "Target device UDID. Optional when exactly one device is attached.")
    var udid: String?

    @Option(name: .long, help: "Which apps to list: user, system, internal, or any.")
    var type: String = "user"

    @Flag(name: .long, help: "List only FairPlay-encrypted apps.")
    var encryptedOnly = false

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Emit structured JSON.")
    var json = false

    private static let types = ["user": "User", "system": "System", "internal": "Internal", "any": "Any"]

    func run() throws {
        guard let applicationType = Self.types[type.lowercased()] else {
            throw ValidationError("--type must be one of: \(Self.types.keys.sorted().joined(separator: ", "))")
        }

        let (device, all) = try DeviceApps.installedApps(udid: udid, applicationType: applicationType)
        let apps = (encryptedOnly ? all.filter { $0.encryption.isEncrypted } : all)
            .sorted { $0.bundleID.lowercased() < $1.bundleID.lowercased() }

        if json {
            let payload: [String: Any] = [
                "device": [
                    "udid": device.udid,
                    "name": device.name as Any,
                    "productType": device.productType as Any,
                    "productVersion": device.productVersion as Any,
                ],
                "apps": apps.map { app in
                    [
                        "bundleID": app.bundleID,
                        "name": app.label,
                        "executable": app.executable as Any,
                        "shortVersion": app.shortVersion as Any,
                        "version": app.version as Any,
                        "path": app.path as Any,
                        "applicationType": app.applicationType as Any,
                        "signerIdentity": app.signerIdentity as Any,
                        "encryption": app.encryption.rawValue,
                        "encrypted": app.encryption.isEncrypted,
                        "sinfLength": app.sinfLength,
                    ] as [String: Any]
                },
            ]
            try emit(jsonText(payload), to: output)
            return
        }

        try emit(render(device: device, apps: apps, total: all.count), to: output)
    }

    private func render(device: DeviceSummary, apps: [InstalledApp], total: Int) -> String {
        var lines = ["\(device.label) — \(device.udid)", ""]
        guard !apps.isEmpty else {
            lines.append("No \(type) apps installed.")
            return lines.joined(separator: "\n")
        }

        let bundleWidth = min(apps.map(\.bundleID.count).max() ?? 20, 52)
        let versionWidth = min(apps.compactMap(\.shortVersion?.count).max() ?? 7, 14)
        for app in apps {
            let marker = app.encryption.isEncrypted ? "ENC" : "  ·"
            let version = app.shortVersion ?? "-"
            lines.append("\(marker)  \(app.bundleID.padded(to: bundleWidth))  \(version.padded(to: versionWidth))  \(app.label)")
        }

        let encrypted = apps.filter { $0.encryption.isEncrypted }.count
        lines.append("")
        lines.append("\(apps.count) of \(total) apps — \(encrypted) FairPlay-encrypted, \(apps.count - encrypted) plaintext")
        return lines.joined(separator: "\n")
    }
}

private func jsonText(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

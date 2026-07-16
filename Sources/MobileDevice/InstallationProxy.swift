import Foundation

/// Whether an app's executable is FairPlay-encrypted on disk.
public enum EncryptionStatus: String, Sendable {
    /// The app carries a FairPlay `ApplicationSINF` blob — App Store DRM. Its
    /// `__TEXT` is encrypted (`LC_ENCRYPTION_INFO_64.cryptid != 0`).
    case fairPlay
    /// No SINF: a system app, or one signed by a development/enterprise
    /// certificate. The executable is plaintext.
    case none

    public var isEncrypted: Bool { self == .fairPlay }
}

/// An app installed on a device, as reported by installation_proxy.
public struct InstalledApp: Sendable {
    public let bundleID: String
    public let displayName: String?
    public let name: String?
    public let executable: String?
    public let shortVersion: String?
    public let version: String?
    public let path: String?
    /// `User`, `System`, or `Internal`.
    public let applicationType: String?
    public let signerIdentity: String?
    /// Size of the FairPlay SINF blob, or 0 when absent. Kept as the raw
    /// evidence behind `encryption`.
    public let sinfLength: Int

    public var encryption: EncryptionStatus { sinfLength > 0 ? .fairPlay : .none }

    /// Best available human-facing label.
    public var label: String { displayName ?? name ?? bundleID }
}

/// Client for `com.apple.mobile.installation_proxy`.
public enum InstallationProxy {
    public static let serviceName = "com.apple.mobile.installation_proxy"

    /// Attributes requested per app.
    ///
    /// `ApplicationSINF` is the load-bearing one: it is the FairPlay "secure
    /// info" blob, present exactly for App Store-distributed apps, which are the
    /// ones whose `__TEXT` is encrypted. Restricting the attribute set also
    /// keeps the reply small — the default Browse returns every Info.plist key
    /// for every app.
    static let returnAttributes = [
        "CFBundleIdentifier",
        "CFBundleDisplayName",
        "CFBundleName",
        "CFBundleExecutable",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "Path",
        "ApplicationType",
        "SignerIdentity",
        "ApplicationSINF",
    ]

    /// Enumerate installed apps.
    ///
    /// - Parameter applicationType: `User`, `System`, `Internal`, or `Any`.
    public static func browse(
        _ connection: ServiceConnection,
        applicationType: String = "Any"
    ) throws -> [InstalledApp] {
        try connection.send([
            "Command": "Browse",
            "ClientOptions": [
                "ApplicationType": applicationType,
                "ReturnAttributes": returnAttributes,
            ],
        ])

        // Browse streams results: repeated `BrowsingApplications` pages, then a
        // final `Complete`.
        var apps: [InstalledApp] = []
        while true {
            let response = try connection.receive()
            if let error = response["Error"] as? String {
                throw DeviceError("installation_proxy Browse failed: \(error)")
            }
            if let page = response["CurrentList"] as? [[String: Any]] {
                apps.append(contentsOf: page.compactMap(parse))
            }
            if response["Status"] as? String == "Complete" { break }
        }
        return apps
    }

    private static func parse(_ entry: [String: Any]) -> InstalledApp? {
        guard let bundleID = entry["CFBundleIdentifier"] as? String else { return nil }
        return InstalledApp(
            bundleID: bundleID,
            displayName: entry["CFBundleDisplayName"] as? String,
            name: entry["CFBundleName"] as? String,
            executable: entry["CFBundleExecutable"] as? String,
            shortVersion: entry["CFBundleShortVersionString"] as? String,
            version: entry["CFBundleVersion"] as? String,
            path: entry["Path"] as? String,
            applicationType: entry["ApplicationType"] as? String,
            signerIdentity: entry["SignerIdentity"] as? String,
            sinfLength: (entry["ApplicationSINF"] as? Data)?.count ?? 0
        )
    }
}

/// Identifying details for an attached device.
public struct DeviceSummary: Sendable {
    public let udid: String
    public let connectionType: String
    public let name: String?
    public let productType: String?
    public let productVersion: String?

    /// `iPhone (iPhone15,3, iOS 27.0)`
    public var label: String {
        let model = [productType, productVersion.map { "iOS \($0)" }]
            .compactMap { $0 }
            .joined(separator: ", ")
        let base = name ?? udid
        return model.isEmpty ? base : "\(base) (\(model))"
    }
}

/// High-level entry point: the whole usbmux → lockdown → installation_proxy
/// chain in one call.
public enum DeviceApps {
    /// The attached devices, or an empty array when none are connected.
    public static func devices() throws -> [DeviceInfo] {
        try UsbmuxClient.listDevices()
    }

    /// Identifying details for every attached device. A device that is attached
    /// but unpaired still appears, with its lockdown-only fields left nil.
    public static func summaries() throws -> [DeviceSummary] {
        try devices().map { device in
            guard let pairRecord = try? UsbmuxClient.readPairRecord(udid: device.udid),
                  let lockdown = try? LockdownClient(device: device, pairRecord: pairRecord)
            else {
                return DeviceSummary(
                    udid: device.udid, connectionType: device.connectionType,
                    name: nil, productType: nil, productVersion: nil
                )
            }
            defer { lockdown.close() }
            // Device identity is readable without a session; skip StartSession.
            return DeviceSummary(
                udid: device.udid,
                connectionType: device.connectionType,
                name: try? lockdown.value(for: "DeviceName") as? String,
                productType: try? lockdown.value(for: "ProductType") as? String,
                productVersion: try? lockdown.value(for: "ProductVersion") as? String
            )
        }
    }

    /// Resolve a device by UDID, or the only attached device when `udid` is nil.
    public static func resolveDevice(udid: String?) throws -> DeviceInfo {
        let attached = try devices()
        guard !attached.isEmpty else {
            throw DeviceError("no iOS device connected — attach one over USB and unlock it")
        }
        guard let udid else {
            guard attached.count == 1 else {
                let list = attached.map(\.udid).joined(separator: "\n  ")
                throw DeviceError("multiple devices attached; pass --udid to choose one:\n  \(list)")
            }
            return attached[0]
        }
        guard let match = attached.first(where: { $0.udid == udid }) else {
            throw DeviceError("no attached device with UDID \(udid)")
        }
        return match
    }

    /// List apps installed on a device.
    public static func installedApps(
        udid: String? = nil,
        applicationType: String = "Any"
    ) throws -> (device: DeviceSummary, apps: [InstalledApp]) {
        let device = try resolveDevice(udid: udid)
        let pairRecord = try UsbmuxClient.readPairRecord(udid: device.udid)

        let lockdown = try LockdownClient(device: device, pairRecord: pairRecord)
        defer { lockdown.close() }

        let type = try lockdown.queryType()
        guard type == "com.apple.mobile.lockdown" else {
            throw DeviceError("unexpected service on lockdown port: \(type)")
        }

        let summary = DeviceSummary(
            udid: device.udid,
            connectionType: device.connectionType,
            name: try? lockdown.value(for: "DeviceName") as? String,
            productType: try? lockdown.value(for: "ProductType") as? String,
            productVersion: try? lockdown.value(for: "ProductVersion") as? String
        )

        try lockdown.startSession()
        let service = try lockdown.startService(InstallationProxy.serviceName)
        let connection = try lockdown.connect(to: service)
        defer { connection.close() }

        return (summary, try InstallationProxy.browse(connection, applicationType: applicationType))
    }
}

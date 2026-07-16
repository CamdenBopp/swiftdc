import Foundation

/// Property-list helpers. Every protocol in this stack (usbmux, lockdown,
/// installation_proxy) exchanges plists; only the framing differs.
enum Plist {
    static func encode(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = object as? [String: Any] else {
            throw DeviceError("expected a plist dictionary, got \(type(of: object))")
        }
        return dict
    }
}

/// A device as reported by usbmuxd's `ListDevices`.
public struct DeviceInfo: Sendable {
    public let deviceID: Int
    public let udid: String
    public let connectionType: String
}

/// The subset of a usbmux pair record this tool needs.
public struct PairRecord {
    public let hostID: String
    public let systemBUID: String
    public let identity: TLSIdentity
}

/// Client for the usbmuxd multiplexer on `/var/run/usbmuxd`.
///
/// usbmuxd owns the USB transport and the pairing database. Each request opens
/// its own connection because a successful `Connect` converts the socket into a
/// transparent tunnel to a device port — it stops speaking usbmux at that point.
public enum UsbmuxClient {
    static let socketPath = "/var/run/usbmuxd"
    private static let lockdownPort = 62078

    // Computed, not `static let`: a stored `[String: Any]` is not Sendable and
    // so can't be a global under Swift 6 concurrency checking.
    private static var baseRequest: [String: Any] {
        [
            "ClientVersionString": "swiftdc",
            "ProgName": "swiftdc",
            "kLibUSBMuxVersion": 3,
        ]
    }

    /// usbmux framing: a 16-byte little-endian header (total length, version,
    /// message type, tag) followed by an XML plist. Version 1 / type 8 is the
    /// plist protocol.
    private static func request(_ socket: DeviceSocket, _ payload: [String: Any]) throws -> [String: Any] {
        let body = try Plist.encode(payload.merging(baseRequest) { current, _ in current })
        var header = Data()
        for word in [UInt32(16 + body.count), 1, 8, 1] as [UInt32] {
            withUnsafeBytes(of: word.littleEndian) { header.append(contentsOf: $0) }
        }
        try socket.write(header + body)

        let responseHeader = try socket.read(exactly: 16)
        let length = responseHeader.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard length >= 16, length < 64 * 1024 * 1024 else {
            throw DeviceError("usbmuxd returned an implausible message length (\(length))")
        }
        return try Plist.decode(try socket.read(exactly: Int(length) - 16))
    }

    /// Devices currently attached (USB or network).
    public static func listDevices() throws -> [DeviceInfo] {
        let socket = try DeviceSocket(unixPath: socketPath)
        defer { socket.close() }
        let response = try request(socket, ["MessageType": "ListDevices"])
        let list = response["DeviceList"] as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard let deviceID = entry["DeviceID"] as? Int,
                  let properties = entry["Properties"] as? [String: Any],
                  let udid = properties["SerialNumber"] as? String
            else { return nil }
            return DeviceInfo(
                deviceID: deviceID,
                udid: udid,
                connectionType: properties["ConnectionType"] as? String ?? "Unknown"
            )
        }
    }

    /// Fetch the pair record for `udid`.
    ///
    /// This asks usbmuxd — which already runs as root — to read
    /// `/var/db/lockdown/<udid>.plist` on our behalf, so `swiftdc` needs no
    /// elevated privileges. Reading that directory directly requires root (and
    /// is TCC-blocked besides), which is why tools that parse it want `sudo`.
    public static func readPairRecord(udid: String) throws -> PairRecord {
        let socket = try DeviceSocket(unixPath: socketPath)
        defer { socket.close() }
        let response = try request(socket, ["MessageType": "ReadPairRecord", "PairRecordID": udid])
        guard let blob = response["PairRecordData"] as? Data else {
            throw DeviceError("""
            no pair record for \(udid) — the device is attached but not paired with this Mac. \
            Unlock it and tap Trust, then retry.
            """)
        }
        let record = try Plist.decode(blob)
        guard let hostID = record["HostID"] as? String,
              let systemBUID = record["SystemBUID"] as? String,
              let certificate = record["HostCertificate"] as? Data,
              let key = record["HostPrivateKey"] as? Data
        else {
            throw DeviceError("pair record for \(udid) is missing HostID/SystemBUID/HostCertificate/HostPrivateKey")
        }
        return PairRecord(
            hostID: hostID,
            systemBUID: systemBUID,
            identity: TLSIdentity(certificatePEM: certificate, privateKeyPEM: key)
        )
    }

    /// Open a tunnel to `port` on `device`. The returned socket speaks whatever
    /// service lives behind that port, not usbmux.
    public static func connect(to device: DeviceInfo, port: Int) throws -> DeviceSocket {
        let socket = try DeviceSocket(unixPath: socketPath)
        // usbmux takes the port in network byte order.
        let response = try request(socket, [
            "MessageType": "Connect",
            "DeviceID": device.deviceID,
            "PortNumber": Int(UInt16(port).bigEndian),
        ])
        let number = response["Number"] as? Int ?? -1
        guard number == 0 else {
            socket.close()
            throw DeviceError("usbmuxd refused a connection to port \(port) (error \(number))")
        }
        return socket
    }

    /// Open a tunnel to lockdownd, the device's service broker.
    public static func connectToLockdown(_ device: DeviceInfo) throws -> DeviceSocket {
        try connect(to: device, port: lockdownPort)
    }
}

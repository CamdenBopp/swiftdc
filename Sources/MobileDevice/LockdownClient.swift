import Foundation

/// A device service speaking the shared framing: a 4-byte big-endian length
/// followed by an XML plist. Used by lockdownd and by the services it brokers.
public final class ServiceConnection {
    let socket: DeviceSocket

    init(socket: DeviceSocket) { self.socket = socket }

    public func close() { socket.close() }

    public func send(_ payload: [String: Any]) throws {
        let body = try Plist.encode(payload)
        var frame = Data()
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { frame.append(contentsOf: $0) }
        try socket.write(frame + body)
    }

    public func receive() throws -> [String: Any] {
        let header = try socket.read(exactly: 4)
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
        guard length > 0, length < 128 * 1024 * 1024 else {
            throw DeviceError("service returned an implausible message length (\(length))")
        }
        return try Plist.decode(try socket.read(exactly: Int(length)))
    }

    public func request(_ payload: [String: Any]) throws -> [String: Any] {
        try send(payload)
        return try receive()
    }
}

/// A service brokered by lockdownd.
public struct ServiceDescriptor {
    public let name: String
    public let port: Int
    public let requiresSSL: Bool
}

/// Client for lockdownd — the device's service broker, reached on port 62078.
///
/// The flow is: connect, `StartSession` with the pair record's HostID/SystemBUID,
/// upgrade the socket to TLS, then `StartService` to get a port for the service
/// you actually want.
public final class LockdownClient {
    private let connection: ServiceConnection
    private let device: DeviceInfo
    private let pairRecord: PairRecord
    private var sessionID: String?

    public static let label = "swiftdc"

    public init(device: DeviceInfo, pairRecord: PairRecord) throws {
        self.device = device
        self.pairRecord = pairRecord
        self.connection = ServiceConnection(socket: try UsbmuxClient.connectToLockdown(device))
    }

    public func close() {
        if sessionID != nil { try? stopSession() }
        connection.close()
    }

    /// Confirm we're actually talking to lockdownd before trusting later replies.
    public func queryType() throws -> String {
        let response = try connection.request(["Request": "QueryType", "Label": Self.label])
        try Self.checkError(response, context: "QueryType")
        guard let type = response["Type"] as? String else {
            throw DeviceError("lockdown QueryType returned no Type")
        }
        return type
    }

    /// Authenticate with the pair record and upgrade the socket to TLS.
    public func startSession() throws {
        let response = try connection.request([
            "Request": "StartSession",
            "Label": Self.label,
            "HostID": pairRecord.hostID,
            "SystemBUID": pairRecord.systemBUID,
        ])
        try Self.checkError(response, context: "StartSession")
        sessionID = response["SessionID"] as? String
        if response["EnableSessionSSL"] as? Bool == true {
            try connection.socket.startTLS(identity: pairRecord.identity)
        }
    }

    private func stopSession() throws {
        guard let sessionID else { return }
        _ = try? connection.request([
            "Request": "StopSession", "Label": Self.label, "SessionID": sessionID,
        ])
        self.sessionID = nil
    }

    /// Read a device property (e.g. `ProductVersion`, `DeviceName`).
    public func value(for key: String, domain: String? = nil) throws -> Any? {
        var payload: [String: Any] = ["Request": "GetValue", "Label": Self.label, "Key": key]
        if let domain { payload["Domain"] = domain }
        let response = try connection.request(payload)
        try Self.checkError(response, context: "GetValue(\(key))")
        return response["Value"]
    }

    /// Ask lockdownd to start `service` and tell us which port it landed on.
    public func startService(_ service: String) throws -> ServiceDescriptor {
        let response = try connection.request([
            "Request": "StartService", "Label": Self.label, "Service": service,
        ])
        try Self.checkError(response, context: "StartService(\(service))")
        guard let port = response["Port"] as? Int else {
            throw DeviceError("lockdown StartService(\(service)) returned no Port")
        }
        return ServiceDescriptor(
            name: service,
            port: port,
            requiresSSL: response["EnableServiceSSL"] as? Bool ?? false
        )
    }

    /// Open a connection to a brokered service, applying TLS if it asked for it.
    public func connect(to service: ServiceDescriptor) throws -> ServiceConnection {
        let socket = try UsbmuxClient.connect(to: device, port: service.port)
        if service.requiresSSL {
            try socket.startTLS(identity: pairRecord.identity)
        }
        return ServiceConnection(socket: socket)
    }

    private static func checkError(_ response: [String: Any], context: String) throws {
        guard let error = response["Error"] as? String else { return }
        let hint: String
        switch error {
        case "InvalidHostID":
            hint = " — the pair record is stale; re-pair the device (unlock and tap Trust)"
        case "PasswordProtected":
            hint = " — unlock the device and retry"
        case "InvalidService":
            hint = " — this iOS version does not broker that service over lockdown"
        default:
            hint = ""
        }
        throw DeviceError("lockdown \(context) failed: \(error)\(hint)")
    }
}

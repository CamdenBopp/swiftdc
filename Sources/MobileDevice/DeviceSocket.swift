import COpenSSL
import Darwin
import Foundation

/// A human-readable error surfaced to the CLI.
public struct DeviceError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// The host's TLS identity for a paired device, as stored in the usbmux pair
/// record. Both blobs are PEM.
public struct TLSIdentity {
    public let certificatePEM: Data
    public let privateKeyPEM: Data
}

/// A byte stream to usbmuxd or, once tunnelled, to a service on the device.
///
/// Lockdown negotiates TLS *mid-stream* — the socket carries plaintext plists
/// until `StartSession` returns `EnableSessionSSL`, then the same fd is upgraded
/// in place. That rules out `NWConnection` (TLS must be declared at connect
/// time) and SecureTransport (building a `SecIdentity` from a detached PEM
/// cert+key needs either a keychain round-trip or private API), so this uses
/// OpenSSL's `SSL_set_fd` the way libimobiledevice does.
public final class DeviceSocket {
    private var fd: Int32
    private var ssl: OpaquePointer?
    private var ctx: OpaquePointer?
    private var closed = false

    /// Connect to a Unix domain socket (usbmuxd).
    public init(unixPath: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DeviceError("socket(AF_UNIX) failed: \(errnoText())") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(unixPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw DeviceError("socket path too long: \(unixPath)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.baseAddress!.copyMemory(from: pathBytes, byteCount: pathBytes.count)
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            Darwin.close(fd)
            throw DeviceError("connect(\(unixPath)) failed: \(errnoText()) — is usbmuxd running?")
        }
    }

    deinit { close() }

    public func close() {
        guard !closed else { return }
        closed = true
        if let ssl {
            SSL_shutdown(ssl)
            SSL_free(ssl)
            self.ssl = nil
        }
        if let ctx {
            SSL_CTX_free(ctx)
            self.ctx = nil
        }
        Darwin.close(fd)
    }

    // MARK: - TLS

    /// Upgrade this connection to TLS in place, presenting `identity` as the
    /// client certificate.
    ///
    /// Verification is disabled: lockdown presents a self-signed device
    /// certificate, and mutual trust is already established by the pair record
    /// itself (we hold a key the device provisioned). Verified against iOS 27,
    /// which negotiates TLS 1.2 / ECDHE-RSA-AES256-GCM-SHA384 at OpenSSL's
    /// default security level — no cipher or renegotiation downgrade needed.
    public func startTLS(identity: TLSIdentity) throws {
        guard ssl == nil else { throw DeviceError("TLS already started on this socket") }
        guard let context = SSL_CTX_new(TLS_client_method()) else {
            throw DeviceError("SSL_CTX_new failed: \(Self.opensslError())")
        }
        ctx = context
        SSL_CTX_set_verify(context, SSL_VERIFY_NONE, nil)

        try Self.useCertificate(identity.certificatePEM, in: context)
        try Self.usePrivateKey(identity.privateKeyPEM, in: context)

        guard let connection = SSL_new(context) else {
            throw DeviceError("SSL_new failed: \(Self.opensslError())")
        }
        ssl = connection
        guard SSL_set_fd(connection, fd) == 1 else {
            throw DeviceError("SSL_set_fd failed: \(Self.opensslError())")
        }
        guard SSL_connect(connection) == 1 else {
            throw DeviceError("TLS handshake failed: \(Self.opensslError())")
        }
    }

    private static func useCertificate(_ pem: Data, in ctx: OpaquePointer) throws {
        let x509 = try withPEMBIO(pem) { bio in
            PEM_read_bio_X509(bio, nil, nil, nil)
        }
        guard let x509 else { throw DeviceError("pair record HostCertificate is not valid PEM") }
        defer { X509_free(x509) }
        guard SSL_CTX_use_certificate(ctx, x509) == 1 else {
            throw DeviceError("SSL_CTX_use_certificate failed: \(opensslError())")
        }
    }

    private static func usePrivateKey(_ pem: Data, in ctx: OpaquePointer) throws {
        let key = try withPEMBIO(pem) { bio in
            PEM_read_bio_PrivateKey(bio, nil, nil, nil)
        }
        guard let key else { throw DeviceError("pair record HostPrivateKey is not valid PEM") }
        defer { EVP_PKEY_free(key) }
        guard SSL_CTX_use_PrivateKey(ctx, key) == 1 else {
            throw DeviceError("SSL_CTX_use_PrivateKey failed: \(opensslError())")
        }
    }

    private static func withPEMBIO<T>(_ pem: Data, _ body: (OpaquePointer) -> T) throws -> T {
        try pem.withUnsafeBytes { raw -> T in
            guard let base = raw.baseAddress, raw.count <= Int(Int32.max) else {
                throw DeviceError("empty PEM blob in pair record")
            }
            guard let bio = BIO_new_mem_buf(base, Int32(raw.count)) else {
                throw DeviceError("BIO_new_mem_buf failed")
            }
            defer { BIO_free(bio) }
            return body(bio)
        }
    }

    private static func opensslError() -> String {
        var messages: [String] = []
        while true {
            let code = ERR_get_error()
            if code == 0 { break }
            var buffer = [CChar](repeating: 0, count: 256)
            ERR_error_string_n(code, &buffer, buffer.count)
            messages.append(String(cString: buffer))
        }
        return messages.isEmpty ? "unknown OpenSSL error" : messages.joined(separator: "; ")
    }

    // MARK: - I/O

    public func write(_ data: Data) throws {
        var sent = 0
        while sent < data.count {
            let n: Int = try data.withUnsafeBytes { raw in
                let base = raw.baseAddress!.advanced(by: sent)
                let remaining = data.count - sent
                if let ssl {
                    let written = SSL_write(ssl, base, Int32(remaining))
                    guard written > 0 else { throw DeviceError("SSL_write failed: \(Self.opensslError())") }
                    return Int(written)
                }
                let written = Darwin.write(fd, base, remaining)
                guard written > 0 else { throw DeviceError("write failed: \(errnoText())") }
                return written
            }
            sent += n
        }
    }

    /// Read exactly `count` bytes, or throw. Service framing is length-prefixed,
    /// so a short read is always a protocol error rather than a message boundary.
    public func read(exactly count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var buffer = [UInt8](repeating: 0, count: count)
        var filled = 0
        while filled < count {
            let n: Int = try buffer.withUnsafeMutableBytes { raw in
                let base = raw.baseAddress!.advanced(by: filled)
                let remaining = count - filled
                if let ssl {
                    let got = SSL_read(ssl, base, Int32(remaining))
                    guard got > 0 else { throw DeviceError("SSL_read failed: \(Self.opensslError())") }
                    return Int(got)
                }
                let got = Darwin.read(fd, base, remaining)
                guard got > 0 else {
                    throw DeviceError(got == 0 ? "connection closed by peer" : "read failed: \(errnoText())")
                }
                return got
            }
            filled += n
        }
        return Data(buffer)
    }
}

private func errnoText() -> String { String(cString: strerror(errno)) }

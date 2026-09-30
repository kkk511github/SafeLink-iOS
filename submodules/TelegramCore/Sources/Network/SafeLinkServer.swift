import Foundation
import CryptoKit
import Security
import Darwin

public struct SafeLinkServer: Codable, Equatable {
    public let version: Int
    public let serverId: String
    public let name: String
    public let host: String
    public let port: Int
    public let dcId: Int
    public let rsaPublicKey: String
    public let rsaFingerprint: String

    enum CodingKeys: String, CodingKey {
        case version, name, host, port
        case serverId = "server_id"
        case dcId = "dc_id"
        case rsaPublicKey = "rsa_public_key"
        case rsaFingerprint = "rsa_fingerprint"
    }

    public var address: String {
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    public static func == (lhs: SafeLinkServer, rhs: SafeLinkServer) -> Bool {
        return lhs.version == rhs.version && lhs.serverId == rhs.serverId
            && lhs.name == rhs.name && lhs.host == rhs.host && lhs.port == rhs.port
            && lhs.dcId == rhs.dcId && lhs.rsaFingerprint == rhs.rsaFingerprint
            && lhs.rsaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
                == rhs.rsaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func validate() throws {
        var v4 = in_addr()
        var v6 = in6_addr()
        guard version == 1, (1...65535).contains(port), (1...1000).contains(dcId),
            !name.isEmpty, name.count <= 80, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1,
            host != "0.0.0.0", host != "::", rsaPublicKey.utf8.count <= 4096,
            rsaPublicKey.hasPrefix("-----BEGIN RSA PUBLIC KEY-----\n"),
            rsaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("-----END RSA PUBLIC KEY-----") else {
            throw SafeLinkServerError.invalidConfiguration
        }
        let payload = rsaPublicKey.replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let der = Data(base64Encoded: payload),
            let key = SecKeyCreateWithData(der as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
            let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
            attributes[kSecAttrKeySizeInBits] as? Int == 2048,
            let canonical = SecKeyCopyExternalRepresentation(key, nil) as Data?, canonical == der,
            SHA256.hash(data: der).map({ String(format: "%02x", $0) }).joined() == serverId,
            der.count == 270,
            der.starts(with: [0x30, 0x82, 0x01, 0x0a, 0x02, 0x82, 0x01, 0x01, 0x00]),
            der.suffix(5) == Data([0x02, 0x03, 0x01, 0x00, 0x01]) else {
            throw SafeLinkServerError.invalidConfiguration
        }
        // Canonical RSA-2048/65537: TL-encoded unsigned modulus and exponent.
        let fingerprintInput = Data([254, 0, 1, 0]) + der.subdata(in: 9..<265) + Data([3, 1, 0, 1])
        let fingerprint = Insecure.SHA1.hash(data: fingerprintInput).suffix(8).reversed().map { String(format: "%02x", $0) }.joined()
        guard fingerprint == rsaFingerprint else { throw SafeLinkServerError.invalidConfiguration }
    }

    public static let primary = SafeLinkServer(version: 1,
        serverId: "5cc5b7bffe3c42758a7d4a44c168feb59039b8099ae6a759740d90d5e0393507",
        name: "SafeLink", host: "212.189.31.87", port: 2398, dcId: 2,
        rsaPublicKey: """
        -----BEGIN RSA PUBLIC KEY-----
        MIIBCgKCAQEAzmgJTNhh+Rfz1sBBb2htmPUtIJULMB2YRFElh59UbNl7tHe0h73m
        4wDxMNWd5R/0TInVrXP1XEGwztIdZ56/xKUsm+VvioP+Ohk4vsYK73eArzx4afs4
        Us1eZhLfEdO6ouAjeuE2oMyoyk9BfDI8vhYU6flAZcHHlAfmFbflkdXvHEqm+PHW
        76CSmQDJ9yhNoy41cVPvCLw5UKbgu8c/xdIpIIGEk01BJjtCNbiLJKRLjUIFVIlv
        nsSnrnQwou4I2p90PWjqAQODKiRMscrgYRXj4GO8W9zVibf1ZPzWznmRZVWERWm9
        Q0XxobndWXPc8Ei4Y2LAp7uA8/iL94nN/wIDAQAB
        -----END RSA PUBLIC KEY-----
        """, rsaFingerprint: "4be27a5bb0fc10c4")

    public static func load(accountPath: String) throws -> SafeLinkServer {
        let url = URL(fileURLWithPath: accountPath).appendingPathComponent("safelink-server.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw SafeLinkServerError.invalidConfiguration }
        let data = try Data(contentsOf: url)
        guard data.count <= 16384 else { throw SafeLinkServerError.invalidConfiguration }
        let server = try JSONDecoder().decode(SafeLinkServer.self, from: data)
        try server.validate()
        return server
    }

    public func bind(accountPath: String) throws {
        try self.validate()
        let directory = URL(fileURLWithPath: accountPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("safelink-server.json")
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Self.load(accountPath: accountPath) == self else { throw SafeLinkServerError.identityChanged }
            return
        }
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func prepareAccount(accountPath: String, hasBackup: Bool) throws {
        let binding = URL(fileURLWithPath: accountPath).appendingPathComponent("safelink-server.json")
        if FileManager.default.fileExists(atPath: binding.path) {
            _ = try Self.load(accountPath: accountPath)
        } else {
            guard !hasBackup, !FileManager.default.fileExists(atPath: accountPath + "/postbox") else {
                throw SafeLinkServerError.invalidConfiguration
            }
            try Self.primary.bind(accountPath: accountPath)
        }
    }

    public static func saved(rootPath: String) throws -> [SafeLinkServer] {
        let url = URL(fileURLWithPath: rootPath).appendingPathComponent("safelink-servers.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [.primary] }
        let data = try Data(contentsOf: url)
        guard data.count <= 262144 else { throw SafeLinkServerError.invalidConfiguration }
        var servers = try JSONDecoder().decode([SafeLinkServer].self, from: data)
        guard servers.count <= 32, Set(servers.map { $0.serverId }).count == servers.count else { throw SafeLinkServerError.invalidConfiguration }
        for server in servers { try server.validate() }
        if !servers.contains(where: { $0.serverId == primary.serverId }) { servers.insert(.primary, at: 0) }
        return servers
    }

    public func save(rootPath: String) throws {
        try self.validate()
        var servers = try Self.saved(rootPath: rootPath)
        if let existing = servers.first(where: { $0.serverId == serverId }) {
            guard existing == self else { throw SafeLinkServerError.identityChanged }
            return
        }
        guard !servers.contains(where: { $0.host == host && $0.port == port }), servers.count < 32 else { throw SafeLinkServerError.identityChanged }
        servers.append(self)
        let url = URL(fileURLWithPath: rootPath).appendingPathComponent("safelink-servers.json")
        try JSONEncoder().encode(servers).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func discoveryURL(_ input: String) throws -> URL {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: input.contains("://") ? input : "https://" + input),
            components.scheme == "https", let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
            components.path.isEmpty || components.path == "/", (1...65535).contains(components.port ?? 443) else {
            throw SafeLinkServerError.invalidAddress
        }
        components.path = "/.well-known/safelink-client.json"
        guard let url = components.url else { throw SafeLinkServerError.invalidAddress }
        return url
    }
}

public enum SafeLinkServerError: Error, LocalizedError {
    case invalidAddress, invalidConfiguration, identityChanged, requestFailed
    public var errorDescription: String? {
        switch self {
        case .invalidAddress: return "请输入有效的服务器 IP 或 HTTPS 地址。"
        case .invalidConfiguration: return "服务器连接配置或 RSA 公钥无效。"
        case .identityChanged: return "服务器地址或身份与已保存的配置冲突，未覆盖现有账号。"
        case .requestFailed: return "无法安全获取服务器配置，请检查 HTTPS 证书和服务部署。"
        }
    }
}

public final class SafeLinkServerDiscovery: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var data = Data()
    private var completion: ((Result<SafeLinkServer, Error>) -> Void)?

    public func fetch(address: String, completion: @escaping (Result<SafeLinkServer, Error>) -> Void) {
        self.cancel()
        do {
            let url = try SafeLinkServer.discoveryURL(address)
            self.completion = completion
            self.data = Data()
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.urlCache = nil
            let session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
            self.session = session
            session.dataTask(with: url).resume()
        } catch { completion(.failure(error)) }
    }

    public func cancel() {
        self.completion = nil
        self.session?.invalidateAndCancel()
        self.session = nil
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard session === self.session, let response = response as? HTTPURLResponse, response.statusCode == 200, response.expectedContentLength <= 16384, response.mimeType == "application/json" else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard session === self.session, self.data.count + data.count <= 16384 else { dataTask.cancel(); return }
        self.data.append(data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard session === self.session else { return }
        let completion = self.completion
        self.completion = nil
        self.session = nil
        session.finishTasksAndInvalidate()
        do {
            if error != nil { throw SafeLinkServerError.requestFailed }
            let server = try JSONDecoder().decode(SafeLinkServer.self, from: data)
            try server.validate()
            completion?(.success(server))
        } catch { completion?(.failure(error)) }
    }
}

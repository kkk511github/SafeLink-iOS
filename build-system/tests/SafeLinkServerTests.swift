import Foundation

@main
struct SafeLinkServerTests {
    static func rejects(_ action: () throws -> Void) {
        do { try action(); fatalError("Expected invalid configuration to be rejected") } catch {}
    }

    static func main() throws {
        try SafeLinkServer.primary.validate()
        precondition(SafeLinkServer.primary.host == "212.189.31.87")
        let discoveryURL = try SafeLinkServer.discoveryURL("212.189.31.87")
        precondition(discoveryURL.absoluteString == "https://212.189.31.87/.well-known/safelink-client.json")
        for value in ["http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com?x=1", "https://example.com#x"] {
            rejects { _ = try SafeLinkServer.discoveryURL(value) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = root.appendingPathComponent("account-1").path
        try SafeLinkServer.prepareAccount(accountPath: account, hasBackup: false)
        let saved = try SafeLinkServer.load(accountPath: account)
        precondition(saved == .primary)
        try saved.bind(accountPath: account)
        try saved.save(rootPath: root.path)
        let servers = try SafeLinkServer.saved(rootPath: root.path)
        precondition(servers.count == 1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        json["rsa_public_key"] = saved.rsaPublicKey + "\n"
        let newlineKey = try JSONDecoder().decode(SafeLinkServer.self, from: JSONSerialization.data(withJSONObject: json))
        try newlineKey.validate()
        precondition(newlineKey == saved)
        try newlineKey.bind(accountPath: account)
        try newlineKey.save(rootPath: root.path)
        json["server_id"] = String(repeating: "0", count: 64)
        let tampered = try JSONDecoder().decode(SafeLinkServer.self, from: JSONSerialization.data(withJSONObject: json))
        rejects { try tampered.validate() }
        json["server_id"] = saved.serverId
        json["rsa_fingerprint"] = "0000000000000000"
        let wrongFingerprint = try JSONDecoder().decode(SafeLinkServer.self, from: JSONSerialization.data(withJSONObject: json))
        rejects { try wrongFingerprint.validate() }
        json["rsa_fingerprint"] = saved.rsaFingerprint
        json["host"] = "192.0.2.10"
        let moved = try JSONDecoder().decode(SafeLinkServer.self, from: JSONSerialization.data(withJSONObject: json))
        rejects { try moved.bind(accountPath: account) }
        let oldAccount = root.appendingPathComponent("unbound").path
        try FileManager.default.createDirectory(atPath: oldAccount + "/postbox", withIntermediateDirectories: true)
        rejects { try SafeLinkServer.prepareAccount(accountPath: oldAccount, hasBackup: false) }
        let bound = try SafeLinkServer.load(accountPath: account)
        precondition(bound == saved)
        print("SafeLink server configuration, HTTPS input, identity pinning and account isolation tests passed")
    }
}

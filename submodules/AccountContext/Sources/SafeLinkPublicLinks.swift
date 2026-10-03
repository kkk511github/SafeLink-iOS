import Foundation

public func safeLinkPublicLinkPrefix(_ configuredPrefix: String?) -> String {
    let fallback = "https://safelink.chat/"
    guard let configuredPrefix, var components = URLComponents(string: configuredPrefix.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
          let host = components.host, !host.isEmpty,
          !["t.me", "telegram.me", "telegram.dog"].contains(host.lowercased().replacingOccurrences(of: "www.", with: "")),
          components.user == nil, components.password == nil,
          components.query == nil, components.fragment == nil,
          components.port.map({ (1 ... 65535).contains($0) }) ?? true else {
        return fallback
    }
    components.scheme = scheme
    guard let value = components.string else { return fallback }
    return value.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
}

public func safeLinkPublicLink(_ path: String, prefix: String?) -> String {
    return safeLinkPublicLinkPrefix(prefix) + path.drop(while: { $0 == "/" })
}

public func safeLinkPublicLinkDisplay(_ url: String) -> String {
    if url.hasPrefix("https://") {
        return String(url.dropFirst(8))
    } else if url.hasPrefix("http://") {
        return String(url.dropFirst(7))
    }
    return url
}

public func safeLinkPublicLinkFooter(_ text: String, prefix: String?) -> String {
    let displayPrefix = safeLinkPublicLinkDisplay(safeLinkPublicLinkPrefix(prefix))
    let pattern = "(?i)(?:https?://)?(?:www\\.)?(?:safelink\\.chat|t\\.me|telegram\\.me|telegram\\.dog)/"
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
        return text
    }
    return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: displayPrefix))
}

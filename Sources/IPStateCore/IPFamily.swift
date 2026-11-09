import Foundation
import Darwin

public enum IPFamily: String, CaseIterable, Codable, Sendable {
    case ipv4, ipv6
    public var label: String { self == .ipv4 ? "IPv4" : "IPv6" }

    @MainActor
    public static func automatic(ipv4: IPMonitor, ipv6: IPMonitor, previous: IPFamily) -> IPFamily {
        if ipv4.ip != nil, !ipv4.isStale { return .ipv4 }
        if ipv6.ip != nil, !ipv6.isStale { return .ipv6 }
        let previousMonitor = previous == .ipv4 ? ipv4 : ipv6
        if previousMonitor.ip != nil { return previous }
        if ipv4.ip != nil { return .ipv4 }
        if ipv6.ip != nil { return .ipv6 }
        return .ipv4
    }
}

func normalizedIPAddress(_ value: String, family: IPFamily) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let domain = family == .ipv4 ? AF_INET : AF_INET6
    var bytes = [UInt8](repeating: 0, count: 16)
    guard value.withCString({ inet_pton(domain, $0, &bytes) }) == 1 else { return nil }
    var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    guard inet_ntop(domain, &bytes, &text, socklen_t(text.count)) != nil else { return nil }
    return String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

func normalizedIPAddress(_ value: String) -> String? {
    normalizedIPAddress(value, family: .ipv4) ?? normalizedIPAddress(value, family: .ipv6)
}

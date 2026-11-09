import Foundation

public struct IPNotificationInfo: Equatable, Sendable {
    public let ip: String?
    public let family: IPFamily
    public let location: IPLocation?
    public let isStale: Bool

    public init(ip: String?, family: IPFamily, location: IPLocation?, isStale: Bool = false) {
        self.ip = ip
        self.family = family
        self.location = location
        self.isStale = isStale
    }

    @MainActor public init(monitor: IPMonitor, markStale: Bool = false) {
        let location = monitor.countryCode.map { IPLocation(countryCode: $0, city: monitor.city) }
        self.init(ip: monitor.ip, family: monitor.family, location: location, isStale: markStale || monitor.isStale)
    }

    public func locationText(locale: Locale = .current) -> String {
        guard let ip, !ip.isEmpty else { return "" }
        guard let location else { return "🌐 Location unavailable" }
        let code = normalizedCountryCode(location.countryCode)
        let flag = code.map {
            String(String.UnicodeScalarView($0.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
        } ?? "🌐"
        let country = code.map { locale.localizedString(forRegionCode: $0) ?? $0 } ?? "Country unavailable"
        return "\(flag) \(country) · \(location.city ?? "City unavailable")"
    }

    public var addressText: String {
        guard let ip, !ip.isEmpty else { return "No IP address available yet." }
        return isStale ? "Last known \(family.label): \(ip)" : ip
    }
}

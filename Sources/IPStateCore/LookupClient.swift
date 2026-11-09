import Foundation
import OSLog

public struct IPLocation: Equatable, Sendable {
    public let countryCode: String
    public let city: String?

    public init(countryCode: String, city: String?) {
        self.countryCode = countryCode
        let trimmed = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.city = trimmed?.isEmpty == false ? trimmed : nil
    }
}

public struct LookupClient: IPLookingUp {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    private let logger = Logger(subsystem: "com.hypnodron.IPState", category: "Lookup")

    public init() {
        transport = { request in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 4
            configuration.timeoutIntervalForResource = 5
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            return try await session.data(for: request)
        }
    }

    init(transport: @escaping Transport) { self.transport = transport }

    public func publicIPv4() async throws -> String {
        try await address(for: .ipv4)
    }

    public func publicIPv6() async throws -> String {
        try await address(for: .ipv6)
    }

    private func address(for family: IPFamily) async throws -> String {
        let endpoints = family == .ipv4
            ? ["https://api.ipify.org", "https://v4.api.ipinfo.io/ip"]
            : ["https://api6.ipify.org", "https://v6.api.ipinfo.io/ip"]
        for endpoint in endpoints {
            do {
                let data = try await fetch(endpoint)
                let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let normalized = normalizedIPAddress(value, family: family) else { throw LookupError.invalidAddress }
                return normalized
            } catch {
                try propagateCancellation(error)
                logger.debug("IP lookup failed; trying the next service: \(error.localizedDescription)")
            }
        }
        throw LookupError.unavailable
    }

    public func location(for ip: String) async throws -> IPLocation {
        guard let ip = normalizedIPAddress(ip) else { throw LookupError.invalidAddress }
        var countryOnly: IPLocation?
        for provider in LocationProvider.allCases {
            do {
                let data = try await fetch(provider.endpoint(for: ip))
                let location = try provider.location(from: data, for: ip)
                if let countryOnly, countryOnly.countryCode != location.countryCode {
                    logger.debug("Location provider disagrees with the first country result: \(provider.rawValue, privacy: .public)")
                    continue
                }
                if location.city != nil { return location }
                countryOnly = location
            } catch {
                try propagateCancellation(error)
                logger.debug("Location lookup failed for \(provider.rawValue, privacy: .public): \(error.localizedDescription)")
            }
        }
        if let countryOnly { return countryOnly }
        throw LookupError.unavailable
    }

    private func fetch(_ endpoint: String) async throws -> Data {
        try Task.checkCancellation()
        guard let url = URL(string: endpoint) else { throw LookupError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 4)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 65_536 else {
            throw LookupError.invalidResponse
        }
        return data
    }

    private func propagateCancellation(_ error: any Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
        try Task.checkCancellation()
    }
}

private enum LocationProvider: String, CaseIterable {
    case countryIS = "Country.is"
    case ipwhoIS = "IPWHOIS"
    case geoJS = "GeoJS"
    case freeIPAPI = "FreeIPAPI"

    func endpoint(for ip: String) -> String {
        switch self {
        case .countryIS: "https://api.country.is/\(ip)?fields=city"
        case .ipwhoIS: "https://ipwho.is/\(ip)?fields=success,ip,country_code,city"
        case .geoJS: "https://get.geojs.io/v1/ip/geo/\(ip).json"
        case .freeIPAPI: "https://free.freeipapi.com/api/v1/json/\(ip)"
        }
    }

    func location(from data: Data, for ip: String) throws -> IPLocation {
        let decoder = JSONDecoder()
        let fields: (ip: String?, country: String?, city: String?)
        switch self {
        case .countryIS:
            let result = try decoder.decode(CountryResult.self, from: data)
            fields = (result.ip, result.country, result.city)
        case .ipwhoIS:
            let result = try decoder.decode(FallbackCountryResult.self, from: data)
            guard result.success else { throw LookupError.invalidResponse }
            fields = (result.ip, result.country_code, result.city)
        case .geoJS:
            let result = try decoder.decode(GeoJSResult.self, from: data)
            fields = (result.ip, result.country_code, result.city)
        case .freeIPAPI:
            let result = try decoder.decode(FreeIPAPIResult.self, from: data)
            fields = (result.ipAddress, result.countryCode, result.cityName)
        }
        guard fields.ip.flatMap({ normalizedIPAddress($0) }) == ip,
              let code = normalizedCountryCode(fields.country) else { throw LookupError.invalidResponse }
        return IPLocation(countryCode: code, city: fields.city)
    }
}

private struct CountryResult: Decodable { let ip: String; let country: String?; let city: String? }
private struct FallbackCountryResult: Decodable { let success: Bool; let ip: String?; let country_code: String?; let city: String? }
private struct GeoJSResult: Decodable { let ip: String; let country_code: String?; let city: String? }
private struct FreeIPAPIResult: Decodable { let ipAddress: String; let countryCode: String?; let cityName: String? }

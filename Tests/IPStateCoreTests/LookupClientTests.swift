import Foundation
import Testing
@testable import IPStateCore

private func response(_ request: URLRequest, _ body: String, status: Int = 200) -> (Data, URLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
}

private actor LocationRequests {
    var hosts: [String] = []
    func record(_ request: URLRequest) { hosts.append(request.url!.host!) }
}

struct LookupClientTests {
    @Test func failedPrimaryUsesIPv4Fallback() async throws {
        let client = LookupClient { request in
            if request.url?.host == "api.ipify.org" { return response(request, "Unavailable", status: 503) }
            #expect(request.url?.host == "v4.api.ipinfo.io")
            return response(request, "203.0.113.20\n")
        }
        #expect(try await client.publicIPv4() == "203.0.113.20")
    }

    @Test func malformedSuccessfulResponseAlsoUsesFallback() async throws {
        let client = LookupClient { request in
            if request.url?.host == "api.ipify.org" { return response(request, "<html>Error</html>") }
            return response(request, "203.0.113.21")
        }
        #expect(try await client.publicIPv4() == "203.0.113.21")
    }

    @Test func countryBelongsToTheQueriedAddress() async throws {
        let client = LookupClient { request in
            #expect(request.url?.path == "/203.0.113.20")
            return response(request, #"{"ip":"203.0.113.20","country":"NL","city":"Amsterdam"}"#)
        }
        #expect(try await client.location(for: "203.0.113.20").countryCode == "NL")
    }

    @Test func wrongAddressCountryResponseUsesFallback() async throws {
        let client = LookupClient { request in
            if request.url?.host == "api.country.is" {
                return response(request, #"{"ip":"203.0.113.99","country":"US"}"#)
            }
            #expect(request.url?.host == "ipwho.is")
            return response(request, #"{"ip":"203.0.113.20","success":true,"country_code":"NL","city":"Amsterdam"}"#)
        }
        let location = try await client.location(for: "203.0.113.20")
        #expect(location.countryCode == "NL")
        #expect(location.city == "Amsterdam")
    }

    @Test func rateLimitAndApplicationErrorAreFailures() async {
        let client = LookupClient { request in
            if request.url?.host == "api.country.is" { return response(request, "Too many requests", status: 429) }
            return response(request, #"{"success":false,"message":"Rate limit exceeded"}"#)
        }
        await #expect(throws: (any Error).self) { try await client.location(for: "203.0.113.20") }
    }

    @Test func cancellationDoesNotBecomeAnOrdinaryLookupFailure() async {
        let client = LookupClient { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await client.publicIPv4() }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["IPSTATE_LIVE_LOOKUP"] == "1"))
    func liveLookupReturnsIPv4AndCountry() async throws {
        let client = LookupClient()
        let ip = try await client.publicIPv4()
        #expect(isValidIPv4(ip))
        let location = try await client.location(for: ip)
        #expect(location.countryCode.count == 2)
    }

    @Test func cityIsReturnedAlongsideCountry() async throws {
        let requests = LocationRequests()
        let client = LookupClient { request in
            await requests.record(request)
            #expect(request.url?.query == "fields=city")
            return response(request, #"{"ip":"203.0.113.20","country":"NL","city":"Amsterdam"}"#)
        }
        let location = try await client.location(for: "203.0.113.20")
        #expect(location.countryCode == "NL")
        #expect(location.city == "Amsterdam")
        #expect(await requests.hosts == ["api.country.is"])
    }

    @Test func cityCanBeMissingWithoutFailingTheLocation() async throws {
        let client = LookupClient { request in
            if request.url?.host == "api.country.is" {
                return response(request, #"{"ip":"203.0.113.20","country":"NL","city":null}"#)
            }
            throw URLError(.timedOut)
        }
        let location = try await client.location(for: "203.0.113.20")
        #expect(location.countryCode == "NL")
        #expect(location.city == nil)
    }

    @Test(arguments: ["203.0.113.20", "2001:db8::1"])
    func geoJSRecoversAfterTheFirstTwoProvidersFail(ip: String) async throws {
        let requests = LocationRequests()
        let client = LookupClient { request in
            await requests.record(request)
            switch request.url?.host {
            case "api.country.is": return response(request, "Unavailable", status: 503)
            case "ipwho.is": return response(request, #"{"success":false,"message":"Rate limit exceeded"}"#)
            case "get.geojs.io":
                #expect(request.url?.path == "/v1/ip/geo/\(ip).json")
                return response(request, "{\"ip\":\"\(ip)\",\"country_code\":\"NL\",\"city\":\"Amsterdam\"}")
            default: throw URLError(.badServerResponse)
            }
        }
        #expect(try await client.location(for: ip) == IPLocation(countryCode: "NL", city: "Amsterdam"))
        #expect(await requests.hosts == ["api.country.is", "ipwho.is", "get.geojs.io"])
    }

    @Test(arguments: [
        "<html>Service unavailable</html>",
        #"{"ip":"203.0.113.99","country_code":"US","city":"New York"}"#,
        #"{"ip":"203.0.113.20","country_code":"???","city":"Amsterdam"}"#
    ])
    func freeIPAPIRecoversAfterAnInvalidGeoJSResponse(geoJSBody: String) async throws {
        let requests = LocationRequests()
        let client = LookupClient { request in
            await requests.record(request)
            switch request.url?.host {
            case "get.geojs.io": return response(request, geoJSBody)
            case "free.freeipapi.com":
                #expect(request.url?.path == "/api/v1/json/203.0.113.20")
                return response(request, #"{"ipVersion":4,"ipAddress":"203.0.113.20","countryCode":"NL","cityName":" Amsterdam "}"#)
            default: return response(request, "Too many requests", status: 429)
            }
        }
        #expect(try await client.location(for: "203.0.113.20") == IPLocation(countryCode: "NL", city: "Amsterdam"))
        #expect(await requests.hosts == ["api.country.is", "ipwho.is", "get.geojs.io", "free.freeipapi.com"])
    }

    @Test(arguments: ["get.geojs.io", "free.freeipapi.com"])
    func newFallbacksAcceptEquivalentIPv6Addresses(host: String) async throws {
        let client = LookupClient { request in
            guard request.url?.host == host else { throw URLError(.cannotConnectToHost) }
            if host == "get.geojs.io" {
                #expect(request.url?.path == "/v1/ip/geo/2001:db8::1.json")
                return response(request, #"{"ip":"2001:0DB8:0:0:0:0:0:1","country_code":"nl","city":"Amsterdam"}"#)
            }
            #expect(request.url?.path == "/api/v1/json/2001:db8::1")
            return response(request, #"{"ipVersion":6,"ipAddress":"2001:0DB8:0:0:0:0:0:1","countryCode":"nl","cityName":"Amsterdam"}"#)
        }
        #expect(try await client.location(for: "2001:db8::1") == IPLocation(countryCode: "NL", city: "Amsterdam"))
    }

    @Test func missingCityUsesALaterProviderWithTheSameCountry() async throws {
        let client = LookupClient { request in
            switch request.url?.host {
            case "api.country.is": return response(request, #"{"ip":"203.0.113.20","country":"NL","city":"  "}"#)
            case "ipwho.is": return response(request, #"{"success":false}"#)
            case "get.geojs.io":
                return response(request, #"{"ip":"203.0.113.20","country_code":"NL","city":"Amsterdam"}"#)
            default: throw URLError(.badServerResponse)
            }
        }
        #expect(try await client.location(for: "203.0.113.20") == IPLocation(countryCode: "NL", city: "Amsterdam"))
    }

    @Test func conflictingFallbacksDoNotReplaceTheFirstValidCountry() async throws {
        let requests = LocationRequests()
        let client = LookupClient { request in
            await requests.record(request)
            switch request.url?.host {
            case "api.country.is": return response(request, #"{"ip":"203.0.113.20","country":"NL"}"#)
            case "ipwho.is": return response(request, #"{"success":true,"ip":"203.0.113.20","country_code":"DE","city":"Berlin"}"#)
            case "get.geojs.io": return response(request, "Unavailable", status: 503)
            default: return response(request, #"{"ipVersion":4,"ipAddress":"203.0.113.20","countryCode":"US","cityName":"New York"}"#)
            }
        }
        #expect(try await client.location(for: "203.0.113.20") == IPLocation(countryCode: "NL", city: nil))
        #expect(await requests.hosts == ["api.country.is", "ipwho.is", "get.geojs.io", "free.freeipapi.com"])
    }

    @Test(arguments: [
        #"{"ipAddress":"203.0.113.99","countryCode":"US","cityName":"New York"}"#,
        #"{"ipAddress":"203.0.113.20","countryCode":"USA","cityName":"New York"}"#,
        #"{"error":"Rate limit exceeded"}"#
    ])
    func invalidLastProviderDoesNotProduceALocation(body: String) async {
        let requests = LocationRequests()
        let client = LookupClient { request in
            await requests.record(request)
            if request.url?.host == "free.freeipapi.com" { return response(request, body) }
            return response(request, "Unavailable", status: 503)
        }
        await #expect(throws: (any Error).self) { try await client.location(for: "203.0.113.20") }
        #expect(await requests.hosts == ["api.country.is", "ipwho.is", "get.geojs.io", "free.freeipapi.com"])
    }

    @Test(arguments: [false, true])
    func cancelledLocationLookupDoesNotTryMoreProviders(urlCancellation: Bool) async {
        let requests = LocationRequests()
        let client = LookupClient { request in
            await requests.record(request)
            if request.url?.host == "api.country.is" { return response(request, "Unavailable", status: 503) }
            if urlCancellation { throw URLError(.cancelled) }
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) { try await client.location(for: "203.0.113.20") }
        #expect(await requests.hosts == ["api.country.is", "ipwho.is"])
    }

    @Test func IPv6UsesOnlyIPv6EndpointsAndRejectsIPv4FallbackData() async throws {
        let client = LookupClient { request in
            if request.url?.host == "api6.ipify.org" { return response(request, "203.0.113.20") }
            #expect(request.url?.host == "v6.api.ipinfo.io")
            return response(request, "2001:0DB8:0000:0000:0000:0000:0000:0002\n")
        }
        #expect(try await client.publicIPv6() == "2001:db8::2")
    }

    @Test func IPv6LocationAcceptsAnEquivalentAddressSpelling() async throws {
        let client = LookupClient { request in
            #expect(request.url?.path == "/2001:db8::1")
            return response(request, #"{"ip":"2001:0DB8:0:0:0:0:0:1","country":"NL","city":"Amsterdam"}"#)
        }
        let location = try await client.location(for: "2001:db8::1")
        #expect(location.countryCode == "NL")
        #expect(location.city == "Amsterdam")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["IPSTATE_LIVE_IPV6"] == "1"))
    func liveIPv6Lookup() async throws {
        let client = LookupClient()
        let ip = try await client.publicIPv6()
        #expect(normalizedIPAddress(ip, family: .ipv6) != nil)
        let location = try await client.location(for: ip)
        #expect(location.countryCode.count == 2)
    }

    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["IPSTATE_LIVE_LOCATION_FALLBACKS"] == "1"),
        arguments: ["get.geojs.io", "free.freeipapi.com"], ["8.8.8.8", "2001:4860:4860::8888"]
    )
    func liveLocationFallbacks(host: String, ip: String) async throws {
        let client = LookupClient { request in
            guard request.url?.host == host else { throw URLError(.cannotConnectToHost) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = 5
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            return try await session.data(for: request)
        }
        let location = try await client.location(for: ip)
        // Anycast addresses can map to different countries across provider databases.
        #expect(location.countryCode.count == 2)
    }
}

import XCTest
@testable import HopGauge

final class RouteTracerTests: XCTestCase {
    func testParsesSilentAndRespondingHops() {
        let output = """
        traceroute to example.com (93.184.216.34), 20 hops max, 40 byte packets
         1  *
         2  192.0.2.1  4.812 ms
         3  93.184.216.34  18.420 ms
        """

        let result = RouteTracer.parse(output, target: "example.com")

        XCTAssertEqual(result.resolvedAddress, "93.184.216.34")
        XCTAssertEqual(result.hops.count, 3)
        XCTAssertEqual(result.hops[0], RouteHop(index: 1, address: nil, latencyMs: nil, annotation: nil))
        XCTAssertEqual(result.hops[1].address, "192.0.2.1")
        XCTAssertEqual(try XCTUnwrap(result.hops[1].latencyMs), 4.812, accuracy: 0.001)
        XCTAssertTrue(result.reachedDestination)
    }

    func testParsesPartialTraceAndAnnotation() {
        let output = """
        traceroute to 203.0.113.7 (203.0.113.7), 20 hops max, 40 byte packets
         1  10.0.0.1  0.921 ms
         2  198.51.100.1  12.340 ms !H
         3  *
        """

        let result = RouteTracer.parse(output, target: "203.0.113.7", method: .icmp)

        XCTAssertEqual(result.method, .icmp)
        XCTAssertEqual(result.hops[1].annotation, "!H")
        XCTAssertFalse(result.reachedDestination)
    }

    func testParsesHeaderWithoutParenthesizedAddress() {
        let output = """
        traceroute6 to 2001:db8::1, 20 hops max, 12 byte packets
         1  2001:db8::1  0.115 ms
        """

        let result = RouteTracer.parse(output, target: "2001:db8::1")

        XCTAssertEqual(result.resolvedAddress, "2001:db8::1")
        XCTAssertTrue(result.reachedDestination)
    }

    func testIgnoresErrorsAndHeadersAsHops() {
        let output = """
        traceroute: unknown host invalid.example
        route probe could not start
        """

        let result = RouteTracer.parse(output, target: "invalid.example")

        XCTAssertTrue(result.hops.isEmpty)
        XCTAssertFalse(result.reachedDestination)
    }

    func testLoopbackTrace() async throws {
        let result = await RouteTracer.trace(rawTarget: "127.0.0.1")

        XCTAssertNil(result.failure)
        XCTAssertEqual(result.hops.first?.address, "127.0.0.1")
        XCTAssertTrue(result.reachedDestination)
    }
}

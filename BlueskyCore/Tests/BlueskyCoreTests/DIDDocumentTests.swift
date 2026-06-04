import XCTest
@testable import BlueskyCore

final class DIDDocumentTests: XCTestCase {
    func test_decodesAndExtractsPDSByServiceId() throws {
        let json = Data(#"""
        {
          "id": "did:plc:abc123",
          "service": [
            {"id": "#atproto_pds", "type": "AtprotoPersonalDataServer", "serviceEndpoint": "https://pds.example.com"}
          ]
        }
        """#.utf8)

        let doc = try JSONDecoder().decode(DIDDocument.self, from: json)

        XCTAssertEqual(doc.id, "did:plc:abc123")
        XCTAssertEqual(doc.pdsEndpoint, URL(string: "https://pds.example.com"))
    }

    func test_pdsEndpoint_isNilWhenNoAtprotoService() throws {
        let json = Data(##"{"id":"did:plc:x","service":[{"id":"#other","type":"Foo","serviceEndpoint":"https://nope.example"}]}"##.utf8)

        let doc = try JSONDecoder().decode(DIDDocument.self, from: json)

        XCTAssertNil(doc.pdsEndpoint)
    }
}

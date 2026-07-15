import Foundation
import XCTest
@testable import TwentyNinerNext

final class BlossomAttachmentUploaderTests: XCTestCase {
    func testRelayOriginBecomesBlossomServer() throws {
        XCTAssertEqual(
            try BlossomAttachmentUploader.serverURL(for: "wss://nip29.f7z.io/groups?id=1"),
            URL(string: "https://nip29.f7z.io/")
        )
        XCTAssertEqual(
            try BlossomAttachmentUploader.serverURL(for: "ws://localhost:8080/api/"),
            URL(string: "http://localhost:8080/")
        )
    }

    func testUnsupportedRelaySchemeIsRejected() {
        XCTAssertThrowsError(try BlossomAttachmentUploader.serverURL(for: "ftp://relay.example")) {
            XCTAssertEqual($0 as? BlossomUploadError, .invalidRelay)
        }
    }

    func testSHA256MatchesBlossomBodyHash() {
        XCTAssertEqual(
            BlossomAttachmentUploader.sha256Hex(Data("hello".utf8)),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testAuthorizationEventMatchesMosaicoContract() throws {
        let hash = String(repeating: "a", count: 64)
        let event = try BlossomAttachmentUploader.authorizationEvent(
            server: XCTUnwrap(URL(string: "https://NIP29.f7z.io/")),
            hash: hash,
            createdAt: 1_000
        )

        XCTAssertEqual(event.createdAt, 1_000)
        XCTAssertEqual(event.kind, 24_242)
        XCTAssertEqual(event.content, "Upload Blob")
        XCTAssertEqual(
            event.tags,
            [
                ["t", "upload"],
                ["expiration", "1300"],
                ["x", hash],
                ["server", "nip29.f7z.io"]
            ]
        )
    }

    func testDescriptorMustMatchUploadedBody() throws {
        let hash = String(repeating: "a", count: 64)
        let descriptor = BlossomDescriptor(
            url: "https://relay.example/\(hash).png",
            sha256: hash,
            size: 5,
            type: "image/png",
            uploaded: 1
        )

        XCTAssertEqual(
            try BlossomAttachmentUploader.validatedURL(
                descriptor: descriptor,
                expectedHash: hash,
                expectedSize: 5
            ),
            URL(string: descriptor.url)
        )
        XCTAssertThrowsError(
            try BlossomAttachmentUploader.validatedURL(
                descriptor: descriptor,
                expectedHash: String(repeating: "b", count: 64),
                expectedSize: 5
            )
        ) {
            XCTAssertEqual($0 as? BlossomUploadError, .hashMismatch)
        }
        XCTAssertThrowsError(
            try BlossomAttachmentUploader.validatedURL(
                descriptor: descriptor,
                expectedHash: hash,
                expectedSize: 6
            )
        ) {
            XCTAssertEqual($0 as? BlossomUploadError, .incompleteDescriptor)
        }
    }
}

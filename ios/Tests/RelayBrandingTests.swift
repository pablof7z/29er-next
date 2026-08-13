import NMPUI
import XCTest
@testable import TwentyNinerNext

final class RelayBrandingTests: XCTestCase {
    func testIconPolicyAcceptsPublicHTTPSURL() {
        XCTAssertEqual(
            RelayIconURL.value(from: "https://cdn.example.com/relay.png"),
            URL(string: "https://cdn.example.com/relay.png")
        )
    }

    func testIconPolicyRejectsUnsafeAndLocalURLs() {
        let rejected = [
            "http://cdn.example.com/relay.png",
            "https://user@cdn.example.com/relay.png",
            "https://localhost/relay.png",
            "https://relay.local/relay.png",
            "https://relay.internal/relay.png",
            "https://127.0.0.1/relay.png",
            "https://10.0.0.1/relay.png",
            "https://100.64.0.1/relay.png",
            "https://172.16.0.1/relay.png",
            "https://192.168.1.1/relay.png",
            "https://198.18.0.1/relay.png",
            "https://[::1]/relay.png",
            "data:image/png;base64,AAAA"
        ]

        rejected.forEach { value in
            XCTAssertNil(RelayIconURL.value(from: value), value)
        }
    }

    func testSubtitleKeepsTheHostWhenNIP11AdvertisesAName() {
        let relay = FavoriteRelayChoice(url: "wss://pyramid.fiatjaf.com", roomCount: 2)
        let information = NMPRelayInformationState.available(
            NMPRelayPresentation(
                relay: relay.url,
                advertisedName: "Pyramid",
                freshness: .fresh
            )
        )

        XCTAssertEqual(
            FavoriteRelayBranding.subtitle(for: relay, information: information),
            "pyramid.fiatjaf.com · 2 remembered rooms"
        )
    }

    func testSubtitleRetainsRoomCountWhenNoNameIsAdvertised() {
        let relay = FavoriteRelayChoice(url: "wss://pyramid.fiatjaf.com", roomCount: 1)
        let information = NMPRelayInformationState.loading(relay: relay.url)

        XCTAssertEqual(
            FavoriteRelayBranding.subtitle(for: relay, information: information),
            "1 remembered room"
        )
    }
}

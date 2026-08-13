import Foundation
import NMP
import NMPUI
@preconcurrency import Network
import XCTest
@testable import TwentyNinerNext

final class RelayBrandingNIP11IntegrationTests: XCTestCase {
    func testNIP11IconFeedsThePickerPresentation() async throws {
        let server = try LocalRelayInformationServer(
            body: #"{"name":"Example Relay","icon":"https://cdn.example.com/relay.png"}"#
        )
        let engine = try NMPEngine(config: NMPConfig(allowedLocalRelayHosts: ["localhost"]))
        defer { engine.shutdown() }

        let information = try await engine.relayInformation(for: server.relayURL, policy: .refresh)
        let state = NMPRelayInformationState(information)

        XCTAssertEqual(state.displayName, "Example Relay")
        XCTAssertEqual(
            RelayIconURL.value(from: information.document.icon),
            URL(string: "https://cdn.example.com/relay.png")
        )
    }
}

private final class LocalRelayInformationServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "app.relay-branding.nip11")
    private let body: Data

    private(set) var relayURL = ""

    init(body: String) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.body = Data(body.utf8)

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection, received: Data())
        }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 2) == .success, let port = listener.port else {
            listener.cancel()
            throw FixtureError.listenerDidNotStart
        }
        relayURL = "ws://localhost:\(port.rawValue)"
    }

    deinit {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection, received: Data) {
        connection.start(queue: queue)
        receiveHeaders(connection, received: received)
    }

    private func receiveHeaders(_ connection: NWConnection, received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, _, error in
            guard let self else { return }
            var received = received
            if let data { received.append(data) }
            if received.range(of: Data("\r\n\r\n".utf8)) == nil, error == nil {
                self.receiveHeaders(connection, received: received)
                return
            }

            let headers = Data(
                ("HTTP/1.1 200 OK\r\n" +
                    "Content-Type: application/nostr+json\r\n" +
                    "Content-Length: \(self.body.count)\r\n" +
                    "Connection: close\r\n\r\n").utf8
            )
            connection.send(content: headers + self.body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private enum FixtureError: Error {
        case listenerDidNotStart
    }
}

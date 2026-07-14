#if os(iOS)
import NMP
import SwiftUI
import WebKit

struct NIP07BrowserView: View {
    let url: URL
    let engine: NMPEngine
    @Environment(\.dismiss) private var dismiss
    @StateObject private var consent = NIP07ConsentController()

    var body: some View {
        NavigationStack {
            NIP07WebView(url: url, engine: engine, consent: consent)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host() ?? "Web app")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
        .alert(item: $consent.prompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text("Allow")) { consent.resolve(true) },
                secondaryButton: .cancel { consent.resolve(false) }
            )
        }
    }
}

private struct NIP07Prompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
private final class NIP07ConsentController: ObservableObject {
    @Published var prompt: NIP07Prompt?
    private var continuation: CheckedContinuation<Bool, Never>?

    func request(origin: String, method: String, event: NMPUnsignedEvent?) async -> Bool {
        guard continuation == nil else { return false }
        let title = method == "getPublicKey" ? "Share public key?" : "Sign Nostr event?"
        let detail: String
        if let event {
            let preview = event.content.prefix(180)
            detail = "Kind (event.kind)\n\n\(preview)"
        } else {
            detail = "This reveals your active Nostr public key."
        }
        prompt = NIP07Prompt(title: title, message: "\(origin)\n\n\(detail)")
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ allowed: Bool) {
        prompt = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: allowed)
    }
}

private struct NIP07WebView: UIViewRepresentable {
    let url: URL
    let engine: NMPEngine
    let consent: NIP07ConsentController

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine, consent: consent)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: "nip07")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nip07")
        webView.navigationDelegate = nil
        coordinator.webView = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let engine: NMPEngine
        let consent: NIP07ConsentController
        weak var webView: WKWebView?

        init(engine: NMPEngine, consent: NIP07ConsentController) {
            self.engine = engine
            self.consent = consent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.frameInfo.isMainFrame,
                  let webView = message.webView,
                  let origin = validatedOrigin(message: message, webView: webView),
                  let body = message.body as? [String: Any],
                  let id = body["id"] as? String,
                  let method = body["method"] as? String else {
                return
            }
            Task { await handle(id: id, method: method, body: body, origin: origin, webView: webView) }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let target = navigationAction.request.url else { return .cancel }
            return target.scheme?.lowercased() == "https" ? .allow : .cancel
        }

        private func handle(
            id: String,
            method: String,
            body: [String: Any],
            origin: String,
            webView: WKWebView
        ) async {
            switch method {
            case "getPublicKey":
                guard await consent.request(origin: origin, method: method, event: nil) else {
                    respond(id: id, error: "User denied public-key access", webView: webView)
                    return
                }
                do {
                    guard let pubkey = try engine.activeAccount() else {
                        respond(id: id, error: "No active Nostr account", webView: webView)
                        return
                    }
                    respond(id: id, result: pubkey, webView: webView)
                } catch {
                    respond(id: id, error: String(describing: error), webView: webView)
                }
            case "signEvent":
                guard let event = parseEvent(body["params"]) else {
                    respond(id: id, error: "Invalid unsigned event", webView: webView)
                    return
                }
                guard await consent.request(origin: origin, method: method, event: event) else {
                    respond(id: id, error: "User denied signing", webView: webView)
                    return
                }
                do {
                    let signed = try await engine.signEvent(event)
                    respond(id: id, result: signed.dictionary, webView: webView)
                } catch {
                    respond(id: id, error: String(describing: error), webView: webView)
                }
            default:
                respond(id: id, error: "Unsupported NIP-07 method", webView: webView)
            }
        }

        private func parseEvent(_ value: Any?) -> NMPUnsignedEvent? {
            guard let event = value as? [String: Any],
                  let createdAt = event["created_at"] as? NSNumber,
                  let kind = event["kind"] as? NSNumber,
                  createdAt.int64Value >= 0,
                  kind.intValue >= 0,
                  kind.intValue <= Int(UInt16.max),
                  let tags = event["tags"] as? [[String]],
                  let content = event["content"] as? String else {
                return nil
            }
            return NMPUnsignedEvent(
                createdAt: createdAt.uint64Value,
                kind: kind.uint16Value,
                tags: tags,
                content: content
            )
        }

        private func validatedOrigin(message: WKScriptMessage, webView: WKWebView) -> String? {
            let security = message.frameInfo.securityOrigin
            guard security.protocol.lowercased() == "https",
                  let page = webView.url,
                  page.scheme?.lowercased() == "https",
                  page.host?.lowercased() == security.host.lowercased() else {
                return nil
            }
            let pagePort = page.port ?? 443
            let messagePort = security.port == 0 ? 443 : security.port
            guard pagePort == messagePort else { return nil }
            return messagePort == 443
                ? "https://\(security.host)"
                : "https://\(security.host):\(messagePort)"
        }

        private func respond(id: String, result: Any, webView: WKWebView) {
            respond(envelope: ["id": id, "result": result], webView: webView)
        }

        private func respond(id: String, error: String, webView: WKWebView) {
            respond(envelope: ["id": id, "error": error], webView: webView)
        }

        private func respond(envelope: [String: Any], webView: WKWebView) {
            guard JSONSerialization.isValidJSONObject(envelope),
                  let data = try? JSONSerialization.data(withJSONObject: envelope),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript("window.__nmpNip07Resolve(\(json));")
        }
    }

    private static let bridgeScript = #"""
    (() => {
      const pending = new Map();
      let nextId = 1;
      window.__nmpNip07Resolve = ({ id, result, error }) => {
        const callbacks = pending.get(id);
        if (!callbacks) return;
        pending.delete(id);
        error ? callbacks.reject(new Error(error)) : callbacks.resolve(result);
      };
      const request = (method, params) => new Promise((resolve, reject) => {
        const id = String(nextId++);
        pending.set(id, { resolve, reject });
        try {
          window.webkit.messageHandlers.nip07.postMessage({ id, method, params });
        } catch (error) {
          pending.delete(id);
          reject(error);
        }
      });
      Object.defineProperty(window, "nostr", {
        configurable: false,
        writable: false,
        value: Object.freeze({
          getPublicKey: () => request("getPublicKey", null),
          signEvent: event => request("signEvent", event)
        })
      });
    })();
    """#
}

private extension NMPSignedEvent {
    var dictionary: [String: Any] {
        [
            "id": id,
            "pubkey": pubkey,
            "created_at": NSNumber(value: createdAt),
            "kind": NSNumber(value: kind),
            "tags": tags,
            "content": content,
            "sig": sig
        ]
    }
}
#endif

import SwiftUI

/// In-app preview for an attachment: a zoomable image, or fetched text /
/// Markdown. Audio and other files open through the system instead.
struct TTS29AttachmentPreview: View {
    let attachment: TTS29Artifact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                switch attachment.kind {
                case .image:
                    TTS29ZoomableImage(url: attachment.resolvedURL)
                default:
                    TTS29TextDocumentView(attachment: attachment)
                }
            }
            .navigationTitle(attachment.displayName)
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: PlatformSupport.leadingToolbarPlacement) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: PlatformSupport.trailingToolbarPlacement) {
                    if let url = attachment.resolvedURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open", systemImage: "safari")
                        }
                    }
                }
            }
        }
    }
}

private struct TTS29ZoomableImage: View {
    let url: URL?
    @State private var scale: CGFloat = 1

    var body: some View {
        TTS29RemoteImage(url: url)
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = max(1, $0.magnification) }
                    .onEnded { _ in withAnimation(.spring) { scale = 1 } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TTS29TextDocumentView: View {
    let attachment: TTS29Artifact
    @State private var phase = LoadPhase.loading

    private enum LoadPhase: Equatable {
        case loading
        case loaded(AttributedString)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            switch phase {
            case .loading:
                ProgressView("Loading…").padding(.top, 40)
            case .loaded(let text):
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            case .failed(let message):
                ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text(message))
                    .padding(.top, 40)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let url = attachment.resolvedURL else {
            phase = .failed("The attachment has no URL.")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let string = String(decoding: data, as: UTF8.self)
            if attachment.mediaType.lowercased().contains("markdown"),
               let markdown = try? AttributedString(
                markdown: string,
                options: .init(interpretedSyntax: .full)
               ) {
                phase = .loaded(markdown)
            } else {
                var attributed = AttributedString(string)
                attributed.font = .system(.callout, design: .monospaced)
                phase = .loaded(attributed)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

import Kingfisher
import SwiftUI

struct PresentedURL: Identifiable {
    let id = UUID()
    let url: URL

    init(_ url: URL) {
        self.url = url
    }
}

struct InlineRemoteImage: View {
    let url: URL
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            KFImage(url)
                .placeholder {
                    ZStack {
                        Color.secondary.opacity(0.08)
                        ProgressView()
                    }
                }
                .onFailureView {
                    Label("Open image", systemImage: "photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.08))
                }
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 440)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open image")
    }
}

struct ZoomableRemoteImage: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero

    private var effectiveScale: CGFloat {
        min(max(scale * pinchScale, 1), 6)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                KFImage(url)
                    .placeholder {
                        ProgressView().tint(.white)
                    }
                    .onFailureView {
                        ContentUnavailableView(
                            "Image Unavailable",
                            systemImage: "photo.badge.exclamationmark",
                            description: Text(url.absoluteString)
                        )
                        .foregroundStyle(.white)
                    }
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(effectiveScale)
                    .offset(
                        x: offset.width + dragOffset.width,
                        y: offset.height + dragOffset.height
                    )
                    .gesture(zoomGesture)
                    .simultaneousGesture(panGesture)
                    .onTapGesture(count: 2, perform: toggleZoom)
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                scale = min(max(scale * value.magnification, 1), 6)
                if scale == 1 { offset = .zero }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                guard effectiveScale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard effectiveScale > 1 else { return }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = scale > 1 ? 1 : 2
            if scale == 1 { offset = .zero }
        }
    }
}

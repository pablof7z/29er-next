import SwiftUI

private struct ReactionFailureAlertModifier: ViewModifier {
    @Binding var failure: String?

    func body(content: Content) -> some View {
        content.alert(
            "Couldn’t Send Reaction",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            ),
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

extension View {
    func reactionFailureAlert(_ failure: Binding<String?>) -> some View {
        modifier(ReactionFailureAlertModifier(failure: failure))
    }
}

import Foundation
import NMP

@MainActor
extension AppModel {
    @discardableResult
    func signIn(secretKey: String) async -> Bool {
        guard let engine else {
            identityError = "NMP is not available."
            return false
        }
        guard !isSigningIn else { return false }

        isSigningIn = true
        identityError = nil
        defer { isSigningIn = false }

        do {
            let pubkey = try await engine.addAccount(secretKey: secretKey)
            try engine.setActiveAccount(pubkey)
            activePubkey = pubkey
            resetIdentityScopedState()
            return true
        } catch {
            identityError = Self.identityMessage(for: error)
            return false
        }
    }

    private func resetIdentityScopedState() {
        remembered = .empty
        hasReceivedRememberedGroups = false
        rememberedGroupsError = nil
        favoriteRelayEditState = .idle
        selectedHost = nil
        selectedGroup = nil
    }

    static func identityMessage(for error: Error) -> String {
        switch error as? NMPError {
        case .invalidSecretKey:
            return "That secret key is not a valid nsec or secret hex key."
        default:
            return "NMP could not replace this account."
        }
    }
}

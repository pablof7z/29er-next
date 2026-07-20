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
            try await validateSecretKey(secretKey)
            if activePubkey != nil {
                try detachCurrentAccount(from: engine)
            }
            activePubkey = nil

            let registration = try await engine.addAccount(secretKey: secretKey)
            do {
                try engine.setActiveAccount(registration.publicKey)
                activeRegistration = registration
                activePubkey = registration.publicKey
                resetIdentityScopedState()
                return true
            } catch {
                _ = try? engine.removeAccount(registration)
                throw error
            }
        } catch {
            identityError = Self.identityMessage(for: error)
            return false
        }
    }

    private func validateSecretKey(_ secretKey: String) async throws {
        let validationEngine = try NMPEngine(config: NMPConfig())
        defer { validationEngine.shutdown() }
        let registration = try await validationEngine.addAccount(secretKey: secretKey)
        _ = try validationEngine.removeAccount(registration)
    }

    private func detachCurrentAccount(from engine: NMPEngine) throws {
        if let activeRegistration {
            guard try engine.removeAccount(activeRegistration) else {
                throw IdentityReplacementError.couldNotDetach
            }
            self.activeRegistration = nil
            return
        }
        guard try engine.detachPersistedAccount() else {
            throw IdentityReplacementError.couldNotDetach
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

private enum IdentityReplacementError: Error {
    case couldNotDetach
}

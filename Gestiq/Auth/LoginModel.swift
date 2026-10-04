import Foundation
import Observation

@MainActor
@Observable
final class LoginModel {
    var email = ""
    var password = ""
    private(set) var isLoading = false
    private(set) var isCheckingSession = true
    private(set) var errorMessage: String?
    private(set) var authenticatedSession: LoginSession?
    private var client: AuthClient?
    private var hasStarted = false

    init(client: AuthClient? = nil) { self.client = client }

    var canSubmit: Bool {
        !isLoading && !isCheckingSession && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func authClient() throws -> AuthClient {
        if let client { return client }
        let configured = AuthClient(configuration: try AuthConfiguration.load())
        client = configured
        return configured
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await restoreSession()
    }

    func restoreSession() async {
        guard !isLoading else { return }
        isLoading = true
        isCheckingSession = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let client = try authClient()
            if try client.hasSavedSession() { authenticatedSession = try await client.refresh() }
            isCheckingSession = false
        } catch AuthError.expired {
            authenticatedSession = nil
            isCheckingSession = false
        } catch {
            // Keep the saved refresh session and offer retry on a temporary outage.
            errorMessage = message(for: error)
        }
    }

    func login() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            authenticatedSession = try await authClient().login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), password: password
            )
            password = ""
        } catch { errorMessage = message(for: error) }
    }

    func logout() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authClient().logout()
            authenticatedSession = nil
            password = ""
            email = ""
        } catch { errorMessage = message(for: error) }
    }

    func renewIfNeeded() async {
        guard !isLoading, !isCheckingSession, let current = authenticatedSession, current.needsRenewal else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            authenticatedSession = try await authClient().refresh()
            errorMessage = nil
        } catch AuthError.expired {
            authenticatedSession = nil
            errorMessage = AuthError.expired.localizedDescription
        } catch { errorMessage = message(for: error) }
    }

    private func message(for error: Error) -> String {
        if let error = error as? URLError {
            return error.code == .timedOut
                ? "La conexión tardó demasiado. Intenta de nuevo."
                : "No se pudo conectar. Revisa tu conexión e intenta de nuevo."
        }
        return error.localizedDescription
    }
}

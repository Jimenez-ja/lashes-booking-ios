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
    private(set) var adminRevision = 0
    private(set) var businessRevision = 0
    private(set) var authenticatedSession: LoginSession?
    private var client: AuthClient?
    private var isSigningOut = false
    private var renewal: Task<LoginSession, Error>?
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
        isSigningOut = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false; isSigningOut = false }
        do {
            if let renewal { _ = try? await renewal.value }
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
            _ = try await refreshAccess()
            errorMessage = nil
        } catch AuthError.expired {
            authenticatedSession = nil
            errorMessage = AuthError.expired.localizedDescription
        } catch { errorMessage = message(for: error) }
    }

    func authorizedData(path: String, query: [URLQueryItem] = [], method: APIRequestMethod = .get, body: Data? = nil) async throws -> Data {
        guard !isSigningOut else { throw CancellationError() }
        guard var current = authenticatedSession else { throw AuthError.expired }
        do {
            if current.needsRenewal { current = try await refreshAccess() }
            let client = try authClient()
            do {
                return try await client.request(path: path, query: query, token: current.token, method: method, body: body)
            } catch AuthError.unauthorized {
                let refreshed = try await refreshAccess()
                do {
                    return try await client.request(path: path, query: query, token: refreshed.token, method: method, body: body)
                } catch AuthError.unauthorized {
                    try client.invalidate()
                    throw AuthError.expired
                }
            }
        } catch AuthError.expired {
            authenticatedSession = nil
            errorMessage = AuthError.expired.localizedDescription
            throw AuthError.expired
        }
    }

    func businessChanged() { businessRevision += 1 }

    func administrationChanged() { adminRevision += 1 }

    private func refreshAccess() async throws -> LoginSession {
        guard !isSigningOut else { throw CancellationError() }
        if let renewal { return try await renewal.value }
        let client = try authClient()
        let task = Task { try await client.refresh() }
        renewal = task
        defer { renewal = nil }
        let refreshed = try await task.value
        guard !isSigningOut else { throw CancellationError() }
        guard authenticatedSession != nil else { throw AuthError.expired }
        authenticatedSession = refreshed
        return refreshed
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

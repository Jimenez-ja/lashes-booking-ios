import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, body) = try Self.responder!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                           httpVersion: nil, headerFields: ["Set-Cookie": "gestiq_refresh=test-refresh; Path=/api/auth; Secure; HttpOnly; Max-Age=604800"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class MemorySessionStore: RefreshSessionStore {
    var saved: StoredRefreshSession?
    func read() throws -> StoredRefreshSession? { saved }
    func save(_ session: StoredRefreshSession) throws { saved = session }
    func clear() throws { saved = nil }
}

@main
@MainActor
struct AuthClientChecks {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let store = MemorySessionStore()
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = AuthClient(configuration: AuthConfiguration(
            baseURL: URL(string: "https://example.test/api")!, origin: "https://gestiq.app"
        ), session: session, store: store)

        MockURLProtocol.responder = { request in
            precondition(request.url?.path == "/api/auth/login")
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Origin") == "https://gestiq.app")
            precondition(request.value(forHTTPHeaderField: "X-Gestiq-Session") == "1")
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = request.httpBodyStream!
                stream.open()
                defer { stream.close() }
                var body = Data()
                var bytes = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
                data = body
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: String]
            precondition(body == ["identifier": "test@example.test", "password": "test-password"])
            return (200, Data(#"{"data":{"token":"test-token","user":{"userId":"test","email":"test@example.test","firstname":"Test","surname":"User"}},"message":"OK"}"#.utf8))
        }
        let result = try await client.login(email: "test@example.test", password: "test-password")
        precondition(result.token == "test-token")

        for (status, body, expected) in [
            (401, #"{"message":"Credenciales incorrectas"}"#, "Credenciales incorrectas"),
            (403, #"{"message":"Origen de sesión no permitido"}"#, "Origen de sesión no permitido"),
            (400, #"{"message":["Correo inválido","Contraseña requerida"]}"#, "Correo inválido\nContraseña requerida"),
            (200, #"{"data":{"token":""}}"#, "La respuesta de inicio de sesión está incompleta."),
            (200, "invalid", "La respuesta de inicio de sesión está incompleta."),
            (503, "unavailable", "El servidor no está disponible. Intenta de nuevo.")
        ] {
            MockURLProtocol.responder = { _ in (status, Data(body.utf8)) }
            do {
                _ = try await client.login(email: "test@example.test", password: "test-password")
                fatalError("An invalid session must not authenticate")
            } catch {
                precondition(error.localizedDescription == expected, error.localizedDescription)
            }
        }
        // A new client/model restores through the server, not a locally trusted access token.
        let valid = Data(#"{"data":{"token":"test-token","user":{"userId":"test","email":"test@example.test","firstname":"Test","surname":"User"}}}"#.utf8)
        let hasSavedSession = try client.hasSavedSession()
        precondition(hasSavedSession)
        let reopened = AuthClient(configuration: client.configuration, session: session, store: store)
        MockURLProtocol.responder = { request in
            precondition(request.url?.path == "/api/auth/refreshToken")
            precondition(request.value(forHTTPHeaderField: "Cookie") == "gestiq_refresh=test-refresh")
            return (200, valid)
        }
        let restored = LoginModel(client: reopened)
        await restored.start()
        precondition(restored.authenticatedSession?.user.displayName == "Test User")
        precondition(!restored.isCheckingSession)

        // Failed logout keeps the session available for retry; successful logout clears it.
        MockURLProtocol.responder = { _ in (503, Data()) }
        await restored.logout()
        precondition(restored.authenticatedSession != nil && store.saved != nil)
        MockURLProtocol.responder = { request in
            precondition(request.url?.path == "/api/auth/logout")
            precondition(request.value(forHTTPHeaderField: "Cookie") == "gestiq_refresh=test-refresh")
            return (200, Data(#"{"data":true}"#.utf8))
        }
        await restored.logout()
        precondition(restored.authenticatedSession == nil && store.saved == nil)

        // Temporary restoration failures keep the saved cookie and offer a retry.
        store.saved = StoredRefreshSession(token: "test-refresh", expiresAt: Date().addingTimeInterval(3600))
        MockURLProtocol.responder = { _ in throw URLError(.notConnectedToInternet) }
        let offline = LoginModel(client: reopened)
        await offline.start()
        precondition(offline.isCheckingSession && offline.errorMessage != nil && store.saved != nil)
        MockURLProtocol.responder = { _ in (200, valid) }
        await offline.restoreSession()
        precondition(!offline.isCheckingSession && offline.authenticatedSession != nil)

        // Revoked/expired refresh credentials return to login and clear persistence.
        MockURLProtocol.responder = { _ in (401, Data()) }
        await offline.renewIfNeeded()
        precondition(offline.authenticatedSession == nil && store.saved == nil)
        precondition(offline.errorMessage != nil)

        store.saved = StoredRefreshSession(token: "expired", expiresAt: Date().addingTimeInterval(-1))
        let expired = LoginModel(client: reopened)
        await expired.start()
        precondition(!expired.isCheckingSession && store.saved == nil)

        print("PASS: login request, session decoding, rejected credentials/origin, validation errors, invalid session, persistence, restore/retry, logout and revocation")
    }
}

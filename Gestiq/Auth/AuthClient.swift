import Foundation

struct AuthConfiguration {
    let baseURL: URL
    let origin: String

    static func load(bundle: Bundle = .main) throws -> AuthConfiguration {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "APIBaseURL") as? String,
              let url = URL(string: rawURL), url.scheme == "https", url.host != nil,
              let origin = bundle.object(forInfoDictionaryKey: "AuthOrigin") as? String,
              let originURL = URL(string: origin), originURL.scheme == "https",
              originURL.host != nil else {
            throw AuthError.message("Revisa la configuración de conexión de la app.")
        }
        return AuthConfiguration(baseURL: url, origin: origin)
    }
}

struct AccountUser: Decodable {
    let userId: String
    let email: String?
    let firstname: String?
    let surname: String?
    let role: AccountRole?
    let mercadoPagoPublicKey: String?

    var canManageBusiness: Bool { role?.canonicalName == "customer" || (!isAdministrator && allows(route: "/services")) }
    var canManageAccounts: Bool { role?.canonicalName == "admin_master" }
    var isAdministrator: Bool { role?.canonicalName == "admin_master" || role?.canonicalName == "admin_intern" }

    func allows(route: String) -> Bool {
        role?.pageRoles?.contains { $0.page?.route == route } ?? false
    }

    var displayName: String {
        let name = [firstname, surname].compactMap { $0 }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Mi cuenta" : name
    }
}

struct AccountRole: Decodable {
    let name: String?
    let roleName: String?
    let pageRoles: [AccountPageRole]?
    var canonicalName: String? {
        (name ?? roleName)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
struct AccountPageRole: Decodable {
    let page: AccountPage?
}
struct AccountPage: Decodable {
    let route: String?
}

struct LoginSession: Decodable {
    let token: String
    let user: AccountUser

    var needsRenewal: Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let expiry = payload["exp"] as? Double else { return true }
        // Used only for scheduling. The server remains responsible for JWT validation.
        return expiry <= Date().timeIntervalSince1970 + 60
    }
}

enum AuthError: LocalizedError {
    case message(String)
    case expired
    case unauthorized
    case noCompany

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .noCompany: return "Todavía no tienes un negocio registrado."
        case .unauthorized: return "No se pudo validar tu sesión."
        case .expired: return "Tu sesión caducó. Inicia sesión de nuevo."
        }
    }
}

struct StoredRefreshSession: Codable {
    let token: String
    let expiresAt: Date
}

protocol RefreshSessionStore {
    func read() throws -> StoredRefreshSession?
    func save(_ session: StoredRefreshSession) throws
    func clear() throws
}

enum APIRequestMethod: String { case get = "GET", delete = "DELETE", patch = "PATCH", post = "POST" }

final class AuthClient {
    let configuration: AuthConfiguration
    let session: URLSession
    private let store: any RefreshSessionStore

    init(configuration: AuthConfiguration, session: URLSession? = nil, store: (any RefreshSessionStore)? = nil) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: settings)
        self.store = store ?? KeychainSessionStore(service: "app.gestiq.ios.session.\(configuration.baseURL.absoluteString)")
    }

    func hasSavedSession() throws -> Bool {
        guard let saved = try store.read() else { return false }
        if saved.expiresAt <= Date() { try store.clear(); return false }
        return true
    }

    func login(email: String, password: String) async throws -> LoginSession {
        struct Credentials: Encodable { let identifier: String; let password: String }
        return try await authenticate(path: "auth/login", body: JSONEncoder().encode(
            Credentials(identifier: email, password: password)
        ))
    }

    func refresh() async throws -> LoginSession {
        guard try hasSavedSession() else { throw AuthError.expired }
        return try await authenticate(path: "auth/refreshToken", body: nil)
    }

    func logout() async throws {
        _ = try await post(path: "auth/logout", body: nil)
        try store.clear()
    }

    func request(path: String, query: [URLQueryItem], token: String, method: APIRequestMethod, body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.httpMethod = method.rawValue
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.message("El servidor no devolvió una respuesta válida.")
        }
        if http.statusCode == 401 { throw AuthError.unauthorized }
        if http.statusCode == 403 { throw AuthError.message("Tu cuenta no tiene permiso para realizar esta acción.") }
        if http.statusCode == 404 { throw AuthError.message("Este registro ya no está disponible.") }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (object?["message"] as? String) ?? (object?["message"] as? [String])?.joined(separator: "\n")
            if http.statusCode == 400, path == "company/myself", message == "No tienes una empresa registrada" {
                throw AuthError.noCompany
            }
            let knownMessages = ["User is not active": "La cuenta ya no está activa. Actualiza el detalle.",
                "User is not removed": "La cuenta ya no está desactivada. Actualiza el detalle."]
            throw AuthError.message(knownMessages[message ?? ""] ?? ((400..<500).contains(http.statusCode) && message != nil ? message! : (http.statusCode == 429
                ? "Demasiadas solicitudes. Espera un momento e intenta de nuevo."
                : "No se pudo completar la solicitud. Intenta de nuevo.")))
        }
        return data
    }

    func invalidate() throws { try store.clear() }

    private func authenticate(path: String, body: Data?) async throws -> LoginSession {
        struct Envelope: Decodable { let data: LoginSession }
        let (data, response) = try await post(path: path, body: body)
        guard let result = try? JSONDecoder().decode(Envelope.self, from: data),
              !result.data.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.data.user.userId.isEmpty else {
            throw AuthError.message("La respuesta de inicio de sesión está incompleta.")
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let key = field.key as? String { result[key] = String(describing: field.value) }
        }
        guard let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.url!)
            .first(where: { $0.name == "gestiq_refresh" }),
              !cookie.value.isEmpty, let expiry = cookie.expiresDate, expiry > Date() else {
            throw AuthError.message("El servidor no devolvió una sesión persistente válida.")
        }
        try store.save(StoredRefreshSession(token: cookie.value, expiresAt: expiry))
        return result.data
    }

    private func post(path: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "X-Gestiq-Session")
        request.setValue(configuration.origin, forHTTPHeaderField: "Origin")
        if let saved = try store.read(), saved.expiresAt > Date() {
            request.setValue("gestiq_refresh=\(saved.token)", forHTTPHeaderField: "Cookie")
        }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AuthError.message("El servidor no devolvió una respuesta válida.")
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 && path == "auth/refreshToken" {
                try store.clear()
                throw AuthError.expired
            }
            if response.statusCode >= 500 {
                throw AuthError.message("El servidor no está disponible. Intenta de nuevo.")
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let text = (object?["message"] as? String)
                ?? (object?["message"] as? [String])?.joined(separator: "\n")
            throw AuthError.message(text ?? (response.statusCode == 429
                ? "Demasiados intentos. Espera un minuto y vuelve a intentar."
                : "No se pudo completar la solicitud. Intenta de nuevo."))
        }
        return (data, response)
    }
}

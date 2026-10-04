import Foundation

final class AdminMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Set-Cookie": "gestiq_refresh=admin-test; Path=/api/auth; Secure; HttpOnly; Max-Age=604800"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class AdminTestStore: RefreshSessionStore {
    var value: StoredRefreshSession?
    func read() throws -> StoredRefreshSession? { value }
    func save(_ session: StoredRefreshSession) throws { value = session }
    func clear() throws { value = nil }
}

@main
@MainActor
struct AdminChecks {
    static func main() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        settings.protocolClasses = [AdminMockProtocol.self]
        let network = URLSession(configuration: settings)
        defer { network.invalidateAndCancel() }
        let client = AuthClient(configuration: AuthConfiguration(baseURL: URL(string: "https://example.test/api")!,
            origin: "https://gestiq.app"), session: network, store: AdminTestStore())
        let payload = try JSONSerialization.data(withJSONObject: ["exp": Date().timeIntervalSince1970 + 3600])
        let token = "header.\(payload.base64EncodedString()).signature"
        let loginData = try JSONSerialization.data(withJSONObject: ["data": ["token": token, "user": [
            "userId": "admin", "role": ["name": "admin_master", "pageRoles": [["page": ["route": "/clients"]], ["page": ["route": "/customers"]], ["page": ["route": "/dashboard"]]]]
        ]]])
        AdminMockProtocol.respond = { _ in (200, loginData) }
        let auth = LoginModel(client: client)
        await auth.start()
        auth.email = "test@example.test"
        auth.password = "test-password"
        await auth.login()
        precondition(auth.authenticatedSession?.user.allows(route: "/clients") == true)
        precondition(auth.authenticatedSession?.user.allows(route: "/customers") == true)
        precondition(auth.authenticatedSession?.user.allows(route: "/services") == false)

        let pageData = Data(#"{"data":[{"userId":"client-1","firstname":"Ana","surname":"Prueba","email":null,"status":{"name":"active"},"bookingCount":3}],"pagination":{"page":2,"pageSize":10,"totalItems":11,"totalPages":2}}"#.utf8)
        AdminMockProtocol.respond = { request in
            precondition(request.httpMethod == "GET")
            precondition(request.url?.path == "/api/user/clients")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.first { $0.name == "page" }?.value == "2")
            precondition(query.first { $0.name == "wildcard" }?.value == "a+b@example.test")
            return (200, pageData)
        }
        let directory = AdminDirectoryModel()
        await directory.load(kind: .clients, page: 2, search: "a+b@example.test", auth: auth)
        precondition(directory.people.first?.name == "Ana Prueba")
        precondition(directory.pagination?.totalItems == 11)
        precondition(directory.people.first?.verification == "Sin correo")

        let detailData = Data(#"{"data":{"userId":"business-1","firstname":"Responsable","status":{"name":"active"},"company":{"name":"Negocio prueba","isTest":true,"companyHours":[{"day":1,"open":"09:00:00","close":"18:00:00"}]},"businessSummary":{"totalBookings":4,"completed":2,"canceled":1,"noShow":1,"services":3},"paymentConfiguration":{"linked":true,"liveMode":null,"linkedAt":null},"recentBookings":[{"bookingId":"booking-1","visitOutcome":"no_show"}]}}"#.utf8)
        AdminMockProtocol.respond = { request in
            precondition(request.url?.path == "/api/user/customers/business-1")
            return (200, detailData)
        }
        let detail = AdminDetailModel()
        await detail.load(kind: .businesses, id: "business-1", auth: auth)
        precondition(detail.person?.company?.name == "Negocio prueba")
        precondition(detail.person?.paymentConfiguration?.liveMode == nil)
        precondition(detail.person?.recentBookings?.first?.outcome == "No asistió")

        AdminMockProtocol.respond = { _ in (403, Data()) }
        await directory.load(kind: .clients, page: 1, search: "", auth: auth)
        precondition(directory.people.isEmpty && directory.pagination == nil)
        precondition(directory.error?.contains("permiso") == true)
        precondition(auth.authenticatedSession != nil)

        AdminMockProtocol.respond = { _ in (200, Data(#"{"data":[]}"#.utf8)) }
        await directory.load(kind: .clients, page: 1, search: "", auth: auth)
        precondition(directory.error != nil && directory.pagination == nil)

        // GET 401 renews once and retries with the new access session.
        var gets = 0
        var refreshes = 0
        AdminMockProtocol.respond = { request in
            if request.httpMethod == "GET" {
                gets += 1
                return gets == 1 ? (401, Data()) : (200, pageData)
            }
            precondition(request.url?.path == "/api/auth/refreshToken")
            refreshes += 1
            return (200, loginData)
        }
        await directory.load(kind: .clients, page: 2, search: "", auth: auth)
        precondition(gets == 2 && refreshes == 1 && directory.error == nil)

        // A rejected write retains its JSON body when retried after renewal.
        let writeBody = Data(#"{"name":"Servicio"}"#.utf8)
        var posts = 0
        AdminMockProtocol.respond = { request in
            if request.url?.path == "/api/auth/refreshToken" { return (200, loginData) }
            precondition(request.httpMethod == "POST" && request.url?.path == "/api/services")
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let stream = request.httpBodyStream
            stream?.open(); defer { stream?.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var received = request.httpBody ?? Data()
            if received.isEmpty, let stream {
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    received.append(contentsOf: bytes.prefix(count))
                }
            }
            precondition(received == writeBody)
            posts += 1
            return posts == 1 ? (401, Data()) : (200, Data(#"{"data":true}"#.utf8))
        }
        _ = try await auth.authorizedData(path: "services", method: .post, body: writeBody)
        precondition(posts == 2)

        // Resolve the newest search first; a late old search must not replace it.
        var pending: [String: CheckedContinuation<Data, Error>] = [:]
        let races = AdminDirectoryModel(fetch: { _, query in
            let search = query.first { $0.name == "wildcard" }!.value!
            return try await withCheckedThrowingContinuation { pending[search] = $0 }
        })
        let old = Task { await races.load(kind: .clients, page: 1, search: "old", auth: auth) }
        while pending["old"] == nil { await Task.yield() }
        let new = Task { await races.load(kind: .clients, page: 1, search: "new", auth: auth) }
        while pending["new"] == nil { await Task.yield() }
        pending["new"]!.resume(returning: pageData)
        await new.value
        pending["old"]!.resume(returning: Data(#"{"data":[],"pagination":{"page":1,"pageSize":10,"totalItems":0,"totalPages":0}}"#.utf8))
        await old.value
        precondition(races.people.first?.id == "client-1" && races.pagination?.totalItems == 11)
        // Master-only account actions; inactive accounts are not eligible.
        let intern = try JSONDecoder().decode(AccountUser.self, from: Data(#"{"userId":"intern","role":{"name":"admin_intern"}}"#.utf8))
        precondition(!intern.canManageAccounts && intern.isAdministrator)
        precondition(!AccountAction.deactivate.isAvailable(for: detail.person!, user: intern))
        let inactive = try JSONDecoder().decode(AdminPerson.self, from: Data(#"{"userId":"inactive","status":{"name":"inactive"}}"#.utf8))
        precondition(AccountAction.availableAction(for: inactive, user: auth.authenticatedSession?.user) == nil)

        var changedDetail = try JSONSerialization.jsonObject(with: detailData) as! [String: Any]
        var changedPerson = changedDetail["data"] as! [String: Any]
        var mutations = 0
        AdminMockProtocol.respond = { request in
            if request.httpMethod == "DELETE" {
                precondition(request.url?.path == "/api/user/business-1")
                mutations += 1
                changedPerson["status"] = ["name": "removed"]
                changedDetail["data"] = changedPerson
                return (200, Data(#"{"data":true}"#.utf8))
            }
            if request.httpMethod == "PATCH" {
                precondition(request.url?.path == "/api/user/reactivate/business-1")
                mutations += 1
                changedPerson["status"] = ["name": "active"]
                changedDetail["data"] = changedPerson
                return (200, Data(#"{"data":true}"#.utf8))
            }
            return (200, try JSONSerialization.data(withJSONObject: changedDetail))
        }
        await detail.changeStatus(.deactivate, kind: .businesses, id: "business-1", auth: auth)
        precondition(detail.person?.status?.name == "removed" && detail.notice != nil)
        precondition(auth.adminRevision == 1 && mutations == 1)
        await detail.changeStatus(.deactivate, kind: .businesses, id: "business-1", auth: auth)
        precondition(mutations == 1) // Cannot deactivate the same removed account again.
        await detail.changeStatus(.reactivate, kind: .businesses, id: "business-1", auth: auth)
        precondition(detail.person?.status?.name == "active" && auth.adminRevision == 2 && mutations == 2)
        AdminMockProtocol.respond = { _ in (403, Data()) }
        await detail.changeStatus(.deactivate, kind: .businesses, id: "business-1", auth: auth)
        precondition(detail.mutationError != nil && detail.notice == nil && auth.adminRevision == 2)
        precondition(detail.person?.status?.name == "active")

        let statsObject: [String: Any] = ["data": [
            "period": ["month": "2026-10", "year": 2026, "timezone": "America/Mexico_City"],
            "generatedAt": "2026-10-04T12:00:00Z",
            "accounts": ["businesses": 10, "activeBusinesses": 8, "clients": 20, "activeClients": 19, "verifiedClients": 18, "activeServices": 30],
            "bookings": ["total": 12, "accepted": 9, "pending": 1, "canceled": 2, "completed": 5, "noShow": 1],
            "topBusinesses": [["companyId": "company-1", "ownerId": "business-1", "name": "Negocio prueba", "bookingCount": 7]]
        ]]
        let statsData = try JSONSerialization.data(withJSONObject: statsObject)
        AdminMockProtocol.respond = { request in
            precondition(request.url?.path == "/api/bookings/admin/statistics")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.first { $0.name == "month" }?.value == "2026-10")
            return (200, statsData)
        }
        let dashboard = AdminDashboardModel()
        await dashboard.load(month: "2026-10", auth: auth)
        precondition(dashboard.statistics?.accounts.activeBusinesses == 8)
        precondition(dashboard.statistics?.topBusinesses.first?.ownerId == "business-1")
        AdminMockProtocol.respond = { _ in (503, Data()) }
        await dashboard.load(month: "2026-09", auth: auth)
        precondition(dashboard.statistics == nil && dashboard.error != nil)

        var periods: [String: CheckedContinuation<Data, Error>] = [:]
        let dashboardRace = AdminDashboardModel(fetch: { _, query in
            return try await withCheckedThrowingContinuation { periods[query.first!.value!] = $0 }
        })
        let earlier = Task { await dashboardRace.load(month: "2026-09", auth: auth) }
        while periods["2026-09"] == nil { await Task.yield() }
        let later = Task { await dashboardRace.load(month: "2026-10", auth: auth) }
        while periods["2026-10"] == nil { await Task.yield() }
        periods["2026-10"]!.resume(returning: statsData)
        await later.value
        periods["2026-09"]!.resume(throwing: URLError(.timedOut))
        await earlier.value
        precondition(dashboardRace.statistics?.period.month == "2026-10" && dashboardRace.error == nil)
        precondition(AdminMonth(year: 2026, month: 1).value == "2026-01")

        print("PASS: permissions, authenticated pagination/search, business detail, missing fields, denied access, 401 renewal/retry stale search responses, deactivate/reactivate permissions and refresh, dashboard periods/errors/races")
    }
}

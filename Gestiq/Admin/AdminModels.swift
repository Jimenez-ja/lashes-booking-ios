import Foundation
import Observation

enum AdminDirectory: String, CaseIterable, Identifiable {
    case clients, businesses
    var id: String { rawValue }
    var title: String { self == .clients ? "Clientes" : "Negocios" }
    var path: String { self == .clients ? "user/clients" : "user/customers" }
    var route: String { self == .clients ? "/clients" : "/customers" }
    var icon: String { self == .clients ? "person.2" : "building.2" }
}

struct AdminStatus: Decodable {
    let name: String?
    var canonicalName: String? {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "activo": return "active"
        case "eliminado", "desactivado": return "removed"
        case "inactivo", "pendiente de activación": return "inactive"
        default: return value
        }
    }
    var displayName: String {
        switch canonicalName {
        case "active": return "Activo"
        case "removed": return "Desactivado"
        case "inactive": return "Pendiente de activación"
        default: return name ?? "Sin estatus"
        }
    }
}

enum AccountAction: String, Identifiable {
    case deactivate, reactivate
    var id: String { rawValue }
    static func availableAction(for person: AdminPerson, user: AccountUser?) -> AccountAction? {
        if AccountAction.deactivate.isAvailable(for: person, user: user) { return .deactivate }
        if AccountAction.reactivate.isAvailable(for: person, user: user) { return .reactivate }
        return nil
    }
    var title: String { self == .deactivate ? "Desactivar cuenta" : "Reactivar cuenta" }
    var success: String { self == .deactivate ? "Cuenta desactivada." : "Cuenta reactivada." }
    var method: APIRequestMethod { self == .deactivate ? .delete : .patch }
    func path(id: String) -> String { self == .deactivate ? "user/\(id)" : "user/reactivate/\(id)" }
    func isAvailable(for person: AdminPerson, user: AccountUser?) -> Bool {
        guard user?.canManageAccounts == true, user?.userId != person.id else { return false }
        return person.status?.canonicalName == (self == .deactivate ? "active" : "removed")
    }
}
struct AdminPerson: Decodable, Identifiable {
    let userId: String
    let firstname: String?
    let surname: String?
    let email: String?
    let phone: String?
    let emailVerifiedAt: String?
    let registered: String?
    let status: AdminStatus?
    let companyName: String?
    let bookingCount: Int?
    let serviceCount: Int?
    let bookingSummary: ClientSummary?
    let businessSummary: BusinessSummary?
    let recentBookings: [AdminBooking]?
    let company: AdminCompany?
    let paymentConfiguration: AdminPaymentConfiguration?
    var id: String { userId }
    var name: String {
        let text = [firstname, surname].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "Sin nombre registrado" : text
    }
    var verification: String {
        guard let email, !email.isEmpty else { return "Sin correo" }
        return emailVerifiedAt == nil ? "Correo pendiente" : "Correo verificado"
    }
}
struct ClientSummary: Decodable {
    let total: Int; let completed: Int; let canceled: Int; let noShow: Int
    let lastBookingDate: String?
}
struct BusinessSummary: Decodable {
    let totalBookings: Int; let completed: Int; let canceled: Int; let noShow: Int; let services: Int
}
struct AdminBooking: Decodable, Identifiable {
    let bookingId: String; let date: String?
    let companyName: String?; let serviceName: String?; let clientName: String?
    let statusName: String?; let visitOutcome: String?
    var id: String { bookingId }
    var outcome: String {
        switch visitOutcome {
        case "completed": return "Completada"
        case "no_show": return "No asistió"
        default: return statusName ?? "Sin estatus"
        }
    }
}
struct AdminCompany: Decodable {
    let name: String?; let description: String?
    let state: String?; let city: String?; let neighborhood: String?
    let isTest: Bool?; let cancellationNoticeHours: Int?
    let allowClientCancellation: Bool?; let allowClientReschedule: Bool?
    let companyHours: [AdminHours]?
}
struct AdminHours: Decodable { let day: Int; let open: String; let close: String }
struct AdminPaymentConfiguration: Decodable {
    let linked: Bool; let liveMode: Bool?; let linkedAt: String?
}
struct AdminPagination: Decodable {
    let page: Int; let pageSize: Int; let totalItems: Int; let totalPages: Int
}
struct DirectoryResponse: Decodable {
    let data: [AdminPerson]
    let pagination: AdminPagination
}
struct DetailResponse: Decodable { let data: AdminPerson }

@MainActor
@Observable
final class AdminDirectoryModel {
    private(set) var people: [AdminPerson] = []
    private(set) var pagination: AdminPagination?
    private(set) var isLoading = false
    private(set) var error: String?
    private var generation = 0
    private let fetch: ((String, [URLQueryItem]) async throws -> Data)?

    init(fetch: ((String, [URLQueryItem]) async throws -> Data)? = nil) { self.fetch = fetch }

    func load(kind: AdminDirectory, page: Int, search: String, auth: LoginModel) async {
        generation += 1
        let request = generation
        isLoading = true
        people = []
        pagination = nil
        error = nil
        defer { if request == generation { isLoading = false } }
        do {
            let query = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: "10"),
                URLQueryItem(name: "wildcard", value: search.trimmingCharacters(in: .whitespacesAndNewlines))
            ]
            let data: Data
            if let fetch { data = try await fetch(kind.path, query) }
            else { data = try await auth.authorizedData(path: kind.path, query: query) }
            let response = try JSONDecoder().decode(DirectoryResponse.self, from: data)
            guard request == generation, !Task.isCancelled else { return }
            people = response.data
            pagination = response.pagination
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = adminErrorMessage(error)
        }
    }
}

@MainActor
@Observable
final class AdminDetailModel {
    private(set) var person: AdminPerson?
    private(set) var isMutating = false
    private(set) var mutationError: String?
    private(set) var notice: String?
    private(set) var isLoading = false
    private(set) var error: String?
    private var generation = 0

    init(person: AdminPerson? = nil) { self.person = person }

    func load(kind: AdminDirectory, id: String, auth: LoginModel, afterMutation: Bool = false) async {
        guard !isMutating || afterMutation else { return }
        generation += 1
        let request = generation
        isLoading = true
        error = nil
        person = nil
        defer { if request == generation { isLoading = false } }
        do {
            let data = try await auth.authorizedData(path: "\(kind.path)/\(id)")
            let detail = try JSONDecoder().decode(DetailResponse.self, from: data).data
            guard request == generation, !Task.isCancelled else { return }
            person = detail
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = adminErrorMessage(error)
        }
    }

    func changeStatus(_ action: AccountAction, kind: AdminDirectory, id: String, auth: LoginModel) async {
        guard !isLoading, !isMutating, let person, person.id == id,
              action.isAvailable(for: person, user: auth.authenticatedSession?.user) else { return }
        isMutating = true
        mutationError = nil
        notice = nil
        defer { isMutating = false }
        do {
            struct Response: Decodable { let data: Bool }
            let data = try await auth.authorizedData(path: action.path(id: id), method: action.method)
            guard try JSONDecoder().decode(Response.self, from: data).data else {
                throw AuthError.message("El servidor no confirmó el cambio. Actualiza el detalle antes de reintentar.")
            }
            notice = action.success
            auth.administrationChanged()
            await load(kind: kind, id: id, auth: auth, afterMutation: true)
        } catch {
            mutationError = error is URLError
                ? "No se pudo confirmar el cambio. Actualiza el detalle para comprobar el estado antes de reintentar."
                : adminErrorMessage(error)
        }
    }

}

func adminErrorMessage(_ error: Error) -> String {
    if error is URLError { return "No se pudo conectar. Revisa tu conexión e intenta de nuevo." }
    if error is DecodingError { return "La información recibida está incompleta. Intenta de nuevo." }
    return error.localizedDescription
}

func adminDate(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "No disponible" }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = iso.date(from: raw)
    if date == nil {
        iso.formatOptions = [.withInternetDateTime]
        date = iso.date(from: raw)
    }
    guard let date else { return raw }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "es_MX")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

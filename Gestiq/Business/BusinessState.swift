import Foundation
import Observation

typealias BusinessRequest = @MainActor (String, APIRequestMethod, Data?, [URLQueryItem]) async throws -> Data

@MainActor
func businessRequest(_ auth: LoginModel) -> BusinessRequest {
    { path, method, body, query in try await auth.authorizedData(path: path, query: query, method: method, body: body) }
}

@MainActor
@Observable
final class CompanyEditorModel {
    var draft = CompanyDraft()
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    private(set) var error: String?
    private(set) var notice: String?
    private let request: BusinessRequest
    init(request: @escaping BusinessRequest) { self.request = request }

    func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true; loadError = nil
        defer { isLoading = false }
        do {
            let data = try await request("company/myself", .get, nil, [])
            let company = try JSONDecoder().decode(CompanyResponse.self, from: data).data
            guard !Task.isCancelled else { return }
            draft = CompanyDraft(company: company); hasLoaded = true
        } catch AuthError.noCompany {
            draft = CompanyDraft(); hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            loadError = adminErrorMessage(error)
        }
    }

    func save(auth: LoginModel) async {
        guard hasLoaded, !isSaving, !isLoading else { return }
        isSaving = true; error = nil; notice = nil
        defer { isSaving = false }
        do {
            let payload = try draft.payload()
            let data = try await request("company", draft.companyId == nil ? .post : .patch, JSONEncoder().encode(payload), [])
            let saved = try JSONDecoder().decode(CompanyResponse.self, from: data).data
            draft = CompanyDraft(company: saved)
            notice = "Configuración del negocio guardada."
            auth.businessChanged()
        } catch { self.error = businessSaveError(error) }
    }
}

@MainActor
@Observable
final class ServiceEditorModel {
    var draft = ServiceDraft()
    private(set) var service: BusinessService?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    private(set) var error: String?
    private(set) var saved = false
    private let request: BusinessRequest
    let serviceId: String?
    init(serviceId: String?, request: @escaping BusinessRequest) { self.serviceId = serviceId; self.request = request }

    func load() async {
        guard !isLoading, !isSaving else { return }
        guard let serviceId else { hasLoaded = true; return }
        isLoading = true; loadError = nil
        defer { isLoading = false }
        do {
            let data = try await request("services/\(serviceId)", .get, nil, [])
            let value = try JSONDecoder().decode(ServiceResponse.self, from: data).data
            guard !Task.isCancelled else { return }
            service = value; draft = ServiceDraft(service: value); hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            loadError = adminErrorMessage(error)
        }
    }
    func save(auth: LoginModel) async {
        guard hasLoaded, !isSaving, !isLoading else { return }
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            let payload = try draft.payload()
            let path = serviceId.map { "services/\($0)" } ?? "services"
            let data = try await request(path, serviceId == nil ? .post : .patch, JSONEncoder().encode(payload), [])
            _ = try JSONDecoder().decode(ServiceResponse.self, from: data)
            saved = true
            auth.businessChanged()
        } catch { self.error = businessSaveError(error) }
    }
    func changeStatus(auth: LoginModel) async {
        guard let serviceId, !isSaving, !isLoading else { return }
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            struct Response: Decodable { let data: String }
            let data = try await request("services/changeStatus/\(serviceId)", .patch, nil, [])
            _ = try JSONDecoder().decode(Response.self, from: data)
            saved = true; auth.businessChanged()
        } catch { self.error = businessSaveError(error) }
    }
}

@MainActor
@Observable
final class BusinessServicesModel {
    private(set) var services: [BusinessService] = []
    private(set) var pagination: AdminPagination?
    private(set) var isLoading = false
    private(set) var error: String?
    private var generation = 0
    private let request: BusinessRequest
    init(request: @escaping BusinessRequest) { self.request = request }
    func load(page: Int, search: String) async {
        generation += 1; let revision = generation
        isLoading = true; error = nil; services = []; pagination = nil
        defer { if revision == generation { isLoading = false } }
        do {
            let data = try await request("services", .get, nil, [
                URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "pageSize", value: "10"),
                URLQueryItem(name: "wildcard", value: search.trimmingCharacters(in: .whitespacesAndNewlines))
            ])
            let response = try JSONDecoder().decode(ServiceListResponse.self, from: data)
            guard revision == generation, !Task.isCancelled else { return }
            services = response.data; pagination = response.pagination
        } catch {
            guard revision == generation, !Task.isCancelled else { return }
            self.error = adminErrorMessage(error)
        }
    }
}

func businessSaveError(_ error: Error) -> String {
    if error is URLError { return "No se pudo confirmar el guardado. Comprueba los datos guardados antes de volver a enviar." }
    return adminErrorMessage(error)
}
